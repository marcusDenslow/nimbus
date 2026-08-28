import AppKit

/// Per-game customization the user supplies: a custom background image and/or a background video
/// (played with audio by default, mutable). Files live in `~/…/Nimbus/custom/<gameID>/` as
/// `bg.<ext>` / `video.<ext>`; the per-game mute preference is a small `mute.json`.
@MainActor
enum CustomStore {
    static let dir = AppModel.supportDir.appendingPathComponent("custom", isDirectory: true)
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "bmp", "tiff", "webp"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v"]

    private static func gameDir(_ id: Int) -> URL {
        dir.appendingPathComponent("\(id)", isDirectory: true)
    }
    private static func ensure(_ id: Int) {
        try? FileManager.default.createDirectory(at: gameDir(id), withIntermediateDirectories: true)
    }
    private static func find(_ id: Int, base: String, exts: Set<String>) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: gameDir(id), includingPropertiesForKeys: nil) else { return nil }
        return files.first {
            $0.deletingPathExtension().lastPathComponent == base
                && exts.contains($0.pathExtension.lowercased())
        }
    }

    static func imageURL(_ id: Int) -> URL? { find(id, base: "bg", exts: imageExts) }
    static func videoURL(_ id: Int) -> URL? { find(id, base: "video", exts: videoExts) }
    /// Custom shelf-card cover art (from the SteamGridDB picker), overriding the Steam capsule.
    static func cardURL(_ id: Int) -> URL? { find(id, base: "card", exts: imageExts) }
    /// User-chosen title logo, overriding the auto-fetched SGDB one.
    static func logoURL(_ id: Int) -> URL? { find(id, base: "logo", exts: imageExts) }

    private static func set(_ id: Int, base: String, from src: URL, exts: Set<String>) {
        ensure(id)
        clear(id, base: base, exts: exts)
        let dst = gameDir(id).appendingPathComponent("\(base).\(src.pathExtension.lowercased())")
        try? FileManager.default.copyItem(at: src, to: dst)
    }
    private static func clear(_ id: Int, base: String, exts: Set<String>) {
        if let f = find(id, base: base, exts: exts) { try? FileManager.default.removeItem(at: f) }
    }

    static func setImage(_ id: Int, from src: URL) { set(id, base: "bg", from: src, exts: imageExts) }
    static func clearImage(_ id: Int) { clear(id, base: "bg", exts: imageExts) }
    static func setVideo(_ id: Int, from src: URL) { set(id, base: "video", from: src, exts: videoExts) }
    static func clearVideo(_ id: Int) { clear(id, base: "video", exts: videoExts) }
    static func setCard(_ id: Int, from src: URL) { set(id, base: "card", from: src, exts: imageExts) }
    static func clearCard(_ id: Int) { clear(id, base: "card", exts: imageExts) }
    static func setLogo(_ id: Int, from src: URL) { set(id, base: "logo", from: src, exts: imageExts) }
    static func clearLogo(_ id: Int) { clear(id, base: "logo", exts: imageExts) }

    // MARK: - Mute preference

    private static var muteFile: URL { dir.appendingPathComponent("mute.json") }
    private static var muteMap: [String: Bool] = {
        (try? JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: muteFile))) ?? [:]
    }()

    static func isMuted(_ id: Int) -> Bool { muteMap["\(id)"] ?? false }
    static func setMuted(_ id: Int, _ value: Bool) {
        muteMap["\(id)"] = value
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(muteMap).write(to: muteFile, options: .atomic)
    }

    // MARK: - Video volume preference

    static let defaultVideoVolume: Float = 0.85
    private static var volumeFile: URL { dir.appendingPathComponent("videoVolume.json") }
    private static var volumeMap: [String: Float] = {
        (try? JSONDecoder().decode([String: Float].self, from: Data(contentsOf: volumeFile))) ?? [:]
    }()

    static func videoVolume(_ id: Int) -> Float { volumeMap["\(id)"] ?? defaultVideoVolume }
    static func setVideoVolume(_ id: Int, _ value: Float) {
        volumeMap["\(id)"] = value
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(volumeMap).write(to: volumeFile, options: .atomic)
    }
}
