import AppKit

/// UI sound layer backed by bundled Steam Deck / PS5-style UI clips in `Resources/Sounds`.
/// Each event loads its clip once (cached), and every play uses a fresh copy so rapid
/// navigation retriggers cleanly instead of cutting off the previous hit.
@MainActor
enum Sound {
    private static var cache: [String: NSSound] = [:]

    private static func play(_ file: String, volume: Float) {
        let base: NSSound
        if let cached = cache[file] {
            base = cached
        } else if let url = Bundle.main.url(forResource: file, withExtension: "wav", subdirectory: "Sounds"),
                  let sound = NSSound(contentsOf: url, byReference: false) {
            cache[file] = sound
            base = sound
        } else {
            return
        }
        guard let sound = base.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    /// Cursor move across the shelf / menus.
    static func tick() { play("deck_ui_navigation", volume: 0.35) }
    /// Confirm / activate the focused item.
    static func select() { play("deck_ui_default_activation", volume: 0.55) }
    /// Cancel / step back out.
    static func back() { play("deck_ui_out_of_game_detail", volume: 0.5) }
    /// Hand a game off to launch.
    static func launch() { play("deck_ui_launch_game", volume: 0.7) }
}
