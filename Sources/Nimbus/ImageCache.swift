import AppKit
import ImageIO

/// Loads game art with a memory cache, a disk cache, and in-flight request dedupe.
///
/// Two kinds are cached independently: `.capsule` is the portrait box art on the shelf
/// cards; `.hero` is the landscape banner used for the ambient background and the detail
/// page (kept widescreen so backgrounds don't jump aspect between games).
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    enum Kind: String { case capsule, hero }

    private var memory: [Kind: NSCache<NSNumber, NSImage>] = [:]
    private var inFlight: [Kind: [Int: Task<Data?, Never>]] = [:]
    private var knownMisses: [Kind: Set<Int>] = [:]
    private var dirs: [Kind: URL] = [:]

    private init() {
        for kind in [Kind.capsule, .hero] {
            let cache = NSCache<NSNumber, NSImage>()
            cache.countLimit = kind == .capsule ? 600 : 250
            memory[kind] = cache
            inFlight[kind] = [:]
            knownMisses[kind] = []
            let dir = AppModel.supportDir.appendingPathComponent(kind.rawValue, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dirs[kind] = dir
        }
    }

    func art(for game: Game) async -> NSImage? {
        await load(game, kind: .capsule, candidates: game.artCandidates)
    }

    func hero(for game: Game) async -> NSImage? {
        await load(game, kind: .hero, candidates: game.heroArtCandidates)
    }

    private func load(_ game: Game, kind: Kind, candidates: [URL]) async -> NSImage? {
        let key = NSNumber(value: game.id)
        if let cached = memory[kind]!.object(forKey: key) { return cached }
        if knownMisses[kind]!.contains(game.id) { return nil }
        if let existing = inFlight[kind]![game.id] {
            let data = await existing.value
            return data.flatMap { NSImage(data: $0) }
        }

        let dir = dirs[kind]!
        let gameID = game.id
        // Detached so the disk read, network fetch, and JPEG decode run OFF the main actor —
        // an inherited-actor Task would do all of that on the main thread and stutter the shelf.
        let task = Task<Data?, Never>.detached(priority: .utility) {
            let file = dir.appendingPathComponent("\(gameID).jpg")
            if let data = try? Data(contentsOf: file), NSImage(data: data) != nil {
                return data
            }
            for url in candidates {
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      NSImage(data: data) != nil else { continue }
                try? data.write(to: file, options: .atomic)
                return data
            }
            return nil
        }

        inFlight[kind]![game.id] = task
        let data = await task.value
        inFlight[kind]![game.id] = nil

        // Decode OFF the main actor with immediate caching, so the returned NSImage is already
        // rasterized. Otherwise SwiftUI decodes the full-size JPEG on the main thread at draw
        // time, and rapid focus changes stack those decodes into the ambient-background stutter.
        if let data, let image = await Self.decode(data) {
            memory[kind]!.setObject(image, forKey: key)
            return image
        }
        knownMisses[kind]!.insert(game.id)
        return nil
    }

    private static func decode(_ data: Data) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateImageAtIndex(
                    src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { return NSImage(data: data) }
            return NSImage(cgImage: cg, size: .zero)
        }.value
    }

    /// Warm shelf capsule art for games about to scroll into the lazy stack, so the first
    /// paint after a fast scroll doesn't wait on a disk/network round-trip — the visible lag.
    func prefetch(_ games: [Game]) {
        for game in games { prefetchOne(game, kind: .capsule, candidates: game.artCandidates) }
    }

    /// Warm the landscape background art so switching focus doesn't stall on the ambient fetch.
    func prefetchHeroes(_ games: [Game]) {
        for game in games { prefetchOne(game, kind: .hero, candidates: game.heroArtCandidates) }
    }

    private func prefetchOne(_ game: Game, kind: Kind, candidates: [URL]) {
        let key = NSNumber(value: game.id)
        if memory[kind]!.object(forKey: key) != nil { return }
        if knownMisses[kind]!.contains(game.id) || inFlight[kind]![game.id] != nil { return }
        Task { _ = await load(game, kind: kind, candidates: candidates) }
    }
}
