import AppKit

/// Per-game theme music the user supplies themselves (label themes are copyrighted, so nothing
/// ships). Files live in `~/…/Nimbus/themes/` named by game id — `<gameID>.<ext>` — and play on
/// hover. Assigned from the hero panel's "Set Theme…" button.
@MainActor
enum ThemeStore {
    static let dir = AppModel.supportDir.appendingPathComponent("themes", isDirectory: true)
    static let exts: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "flac", "caf"]

    private static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// The theme file for a game, if the user has assigned one.
    static func themeURL(gameID: Int) -> URL? {
        ensureDir()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return nil }
        return files.first {
            $0.deletingPathExtension().lastPathComponent == "\(gameID)"
                && exts.contains($0.pathExtension.lowercased())
        }
    }

    static func hasTheme(gameID: Int) -> Bool { themeURL(gameID: gameID) != nil }

    /// Copy the user's picked audio file in as this game's theme, replacing any existing one.
    static func setTheme(gameID: Int, from src: URL) {
        ensureDir()
        if let old = themeURL(gameID: gameID) { try? FileManager.default.removeItem(at: old) }
        let dst = dir.appendingPathComponent("\(gameID).\(src.pathExtension.lowercased())")
        try? FileManager.default.copyItem(at: src, to: dst)
    }

    // MARK: - Per-game playback volume

    /// Loud by default so an unconfigured theme still reads over the menu music.
    static let defaultVolume: Float = 0.9
    private static var volumeFile: URL { dir.appendingPathComponent("volume.json") }
    private static var volumeMap: [String: Float] = {
        (try? JSONDecoder().decode([String: Float].self, from: Data(contentsOf: volumeFile))) ?? [:]
    }()

    /// The user's chosen playback volume for this game's theme (0…1), or the loud default.
    static func volume(gameID: Int) -> Float { volumeMap["\(gameID)"] ?? defaultVolume }

    static func setVolume(gameID: Int, _ value: Float) {
        volumeMap["\(gameID)"] = value
        ensureDir()
        try? JSONEncoder().encode(volumeMap).write(to: volumeFile, options: .atomic)
    }
}
