import AppKit

/// Downloads and caches SteamGridDB logo art — the transparent game wordmarks shown in place
/// of the plain-text title on the hero panel and the detail page. Text stays the fallback for
/// games with no logo (or until a key is set; without one this does nothing).
///
/// A confirmed "this game has no logo" is remembered on disk and retried weekly, so boots
/// don't re-hit the API for logo-less games. Plain network failures are only remembered for
/// the session.
@MainActor
final class LogoCache {
    static let shared = LogoCache()

    private let dir = AppModel.supportDir.appendingPathComponent("logos", isDirectory: true)
    private var memory: [Int: NSImage] = [:]
    /// Games known to have no logo (from marker files or this session's lookups).
    private var misses: Set<Int> = []
    private var inFlight: [Int: Task<NSImage?, Never>] = [:]
    private static let missRetry: TimeInterval = 7 * 24 * 3600

    private enum Outcome { case image(NSImage), noLogo, error }

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// What the UI should actually show: the user's custom logo pick when one is set,
    /// otherwise the auto-fetched SGDB one.
    func displayLogo(for game: Game) async -> NSImage? {
        if let url = CustomStore.logoURL(game.id), let custom = NSImage(contentsOf: url) {
            return custom
        }
        return await logo(for: game)
    }

    func logo(for game: Game) async -> NSImage? {
        if let cached = memory[game.id] { return cached }
        if misses.contains(game.id) { return nil }
        if let running = inFlight[game.id] { return await running.value }

        if let file = diskFile(game.id), let image = NSImage(contentsOf: file) {
            memory[game.id] = image
            return image
        }

        // A fresh no-logo marker → don't ask the API again yet.
        let marker = dir.appendingPathComponent("\(game.id).miss")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: marker.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.missRetry {
            misses.insert(game.id)
            return nil
        }
        // No key yet: stay quiet and leave no trace, so the first fetch after the user adds
        // one isn't blocked by a stale marker.
        guard SteamGridDB.hasKey else { return nil }

        let dir = self.dir
        let task = Task<NSImage?, Never> { [weak self] in
            let outcome = await Self.fetch(game: game, dir: dir)
            guard let self else { if case .image(let img) = outcome { return img } else { return nil } }
            switch outcome {
            case .image(let image):
                self.memory[game.id] = image
                return image
            case .noLogo:
                self.misses.insert(game.id)
                try? Data().write(to: marker)
                return nil
            case .error:
                self.misses.insert(game.id)   // session-only; no marker so next boot retries
                return nil
            }
        }
        inFlight[game.id] = task
        let image = await task.value
        inFlight[game.id] = nil
        return image
    }

    private static func fetch(game: Game, dir: URL) async -> Outcome {
        guard let games = try? await SteamGridDB.searchGames(game.title),
              let top = games.first else { return .error }
        guard let logos = try? await SteamGridDB.logos(gameID: top.id) else { return .error }
        guard let first = logos.first, let url = URL(string: first.url) else { return .noLogo }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return .error }
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        try? data.write(to: dir.appendingPathComponent("\(game.id).\(ext)"), options: .atomic)
        return .image(image)
    }

    private func diskFile(_ id: Int) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return nil }
        return files.first {
            $0.deletingPathExtension().lastPathComponent == "\(id)"
                && $0.pathExtension.lowercased() != "miss"
        }
    }
}
