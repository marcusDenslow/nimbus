import AVFoundation
import AppKit

/// Looping menu music.
///
/// No track ships with the app — the PS3/PS5 themes and the like are copyrighted, so Nimbus
/// can't bundle them. Instead it plays whatever audio the user drops into
/// `~/Library/Application Support/Nimbus/music/` (mp3, m4a, wav, aiff, flac). A single file
/// loops forever; multiple files play as a shuffled playlist, reshuffled each full pass.
/// If the folder is empty, the app is simply silent.
@MainActor
final class MusicPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    private var player: AVAudioPlayer?
    private var enabled = true
    private var volume: Float = 0.5

    /// How long every fade in / fade out takes. Slow on purpose.
    private static let fadeDuration: TimeInterval = 2.5
    /// A game's custom theme rides in slowly, so its entrance never feels abrupt.
    private static let themeFadeIn: TimeInterval = 2.5
    /// Switching games, the outgoing theme fades out — quick, but a real fade, not a cut.
    private static let themeFadeOut: TimeInterval = 0.9
    /// Whatever was playing (menu music or the previous theme) ends fully, then this beat of dead
    /// silence, then the new theme starts — old ends → gap → new starts, never an overlap.
    private static let themeGap: TimeInterval = 0.6
    /// Menu music ducks out fast when a theme starts, so it's gone well before the gap.
    private static let menuDuckForTheme: TimeInterval = 0.45
    /// Leaving a themed game, the menu music fades back in gently over this.
    private static let menuRestore: TimeInterval = 2.5

    /// Pauses the player once the current fade-out finishes ramping to silence.
    private var pauseAfterFade: Task<Void, Never>?
    /// Runs the delayed fade-out after a game launch.
    private var gameLaunchFade: Task<Void, Never>?
    /// True when we faded the music out because a game launched, so we know to bring it
    /// back when the user returns to Nimbus.
    private var pausedForGame = false
    /// True from the moment a game is launched until the user moves focus to another item. While
    /// set, every audio source is silenced and stays that way — even when the user tabs back to
    /// Nimbus mid-game — so nothing plays under the running game. Cleared by `resumeAfterGame()`.
    private(set) var mutedForGame = false
    /// True while the menu music is ridden down to make room for something layered over it — a
    /// game trailer's audio or a game's custom theme. Separate from `pausedForGame`: nothing here
    /// pauses the player, it only ducks the volume and restores it the moment that thing stops.
    private var menuDucked = false

    static let musicDir = AppModel.supportDir.appendingPathComponent("music", isDirectory: true)
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "flac", "caf"]

    /// Shuffled play order over the music folder's files. With one track the player just loops
    /// it; with more, each plays once and the delegate advances to the next.
    private var playlist: [URL] = []
    private var trackIndex = 0
    /// Fired when the playlist advances to a new track (not on the initial start) — AppModel
    /// surfaces the "now playing" toast through this.
    var onTrackChange: ((String) -> Void)?

    private override init() {
        super.init()
        try? FileManager.default.createDirectory(at: Self.musicDir, withIntermediateDirectories: true)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        }
    }

    /// Whether a playable track exists in the music folder.
    var hasTrack: Bool { !scanTracks().isEmpty }
    /// How many playable tracks the music folder holds — drives the settings status line.
    var trackCount: Int { scanTracks().count }

    func configure(enabled: Bool, volume: Float) {
        self.enabled = enabled
        self.volume = volume
        if enabled { start() }
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if enabled {
            pausedForGame = false
            if player == nil { start() } else { fadeIn() }
        } else {
            fadeOutAndPause()
        }
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.setVolume(volume, fadeDuration: 0.15)
    }

    /// Called the instant the user launches a game: silence everything right away — the menu music,
    /// any game theme, and (via `mutedForGame`, honoured by the background-video player) the custom
    /// background video's audio too. Stays muted until `resumeAfterGame()`, so nothing sounds under
    /// the running game even when the user tabs back to Nimbus.
    func muteForGameLaunch() {
        mutedForGame = true
        pausedForGame = true
        gameLaunchFade?.cancel(); gameLaunchFade = nil
        // Stop the game theme now (quick fade, then hard stop).
        themeStartTask?.cancel(); themeStartTask = nil
        if let theme = themePlayer {
            themePlayer = nil
            theme.setVolume(0, fadeDuration: 0.3)
            Task { try? await Task.sleep(for: .milliseconds(350)); theme.stop() }
        }
        menuDucked = false
        // Fade the menu music out fast, then pause it.
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.3)
        pauseAfterFade?.cancel()
        pauseAfterFade = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.player?.pause()
        }
    }

    /// The user moved to another item after a game — lift the game mute and bring the menu music
    /// back. The newly focused game's theme (if any) is started separately by the focus handler.
    func resumeAfterGame() {
        guard mutedForGame else { return }
        mutedForGame = false
        pausedForGame = false
        pauseAfterFade?.cancel(); pauseAfterFade = nil
        guard enabled else { return }
        if player == nil { start() } else { fadeIn() }
    }

    /// Build (or refresh) the playlist and start playing. Re-scans the folder, so it picks up
    /// files the user just added without a relaunch. Fades up from silence.
    func start() {
        guard enabled else { return }
        let tracks = scanTracks()
        guard !tracks.isEmpty else { return }
        if Set(tracks) != Set(playlist) {
            playlist = tracks.count > 1 ? tracks.shuffled() : tracks
            trackIndex = 0
        }
        // Already on a current playlist track (playing or paused) — just ramp back up.
        if let player, let url = player.url, playlist.contains(url) {
            fadeIn()
            return
        }
        playTrack(at: trackIndex)
    }

    /// Load and play a playlist entry. Single-track folders loop forever; multi-track ones play
    /// each file once and advance via the delegate. While the menu bed is ducked under a theme or
    /// trailer, the new track starts silent so nothing swells in — unduck restores it.
    private func playTrack(at index: Int) {
        guard playlist.indices.contains(index),
              let loaded = try? AVAudioPlayer(contentsOf: playlist[index]) else { return }
        trackIndex = index
        loaded.numberOfLoops = playlist.count > 1 ? 0 : -1
        loaded.delegate = self
        loaded.volume = 0
        loaded.prepareToPlay()
        loaded.play()
        player = loaded
        if !menuDucked { fadeIn() }
    }

    /// A track ran out (multi-track folders only — single tracks loop in-player) → next one.
    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.advanceTrack(from: finished) }
    }

    private func advanceTrack(from finished: AVAudioPlayer) {
        guard enabled, player === finished, !playlist.isEmpty,
              !pausedForGame, gameLaunchFade == nil, pauseAfterFade == nil else { return }
        var next = trackIndex + 1
        if next >= playlist.count {
            // Reshuffle each full pass, and don't let the new order open with the track that
            // just finished.
            if playlist.count > 1 {
                let last = playlist[trackIndex]
                repeat { playlist.shuffle() } while playlist.first == last
            }
            next = 0
        }
        playTrack(at: next)
        if let name = player?.url?.deletingPathExtension().lastPathComponent {
            onTrackChange?(name)
        }
    }

    /// Resume (if needed) and ramp the volume up to the target over `fadeDuration`.
    private func fadeIn() {
        guard let player else { return }
        pauseAfterFade?.cancel()
        pauseAfterFade = nil
        if !player.isPlaying {
            player.volume = 0
            player.play()
        }
        player.setVolume(volume, fadeDuration: Self.fadeDuration)
    }

    /// Ramp the volume down to silence, then pause once the fade has finished.
    private func fadeOutAndPause() {
        guard let player, player.isPlaying else { return }
        gameLaunchFade?.cancel()
        gameLaunchFade = nil
        player.setVolume(0, fadeDuration: Self.fadeDuration)
        pauseAfterFade?.cancel()
        pauseAfterFade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeDuration))
            guard !Task.isCancelled else { return }
            self?.player?.pause()
        }
    }

    /// Separate player for a focused game's theme music (hover-to-play). Rides alongside the
    /// menu-music player, which it ducks while it plays.
    private var themePlayer: AVAudioPlayer?
    /// Target volume for the theme, set per game from the customize card. Defaults loud so an
    /// unconfigured theme still reads over the menu bed.
    private var themeVolume: Float = 0.9
    /// The delayed bring-up of a queued theme (runs after the old audio dies and the silent gap).
    private var themeStartTask: Task<Void, Never>?

    /// Whether a game's custom theme is currently sounding.
    var isThemePlaying: Bool { themePlayer?.isPlaying == true }

    /// Play a game's theme at `volume`. Whatever's currently sounding — the menu music (arriving
    /// fresh) or the previous game's theme (switching games) — is faded fully out first, then a beat
    /// of dead silence, then this theme rises in. Old ends → gap → new starts, never an overlap.
    /// No-op if this exact theme is already up (or already queued to come up).
    func playTheme(url: URL, volume: Float) {
        themeVolume = volume
        if themePlayer?.url == url {
            // Already the current/queued theme — just settle to the (possibly new) target volume.
            if themeStartTask == nil {
                if themePlayer?.isPlaying != true { themePlayer?.play() }
                themePlayer?.setVolume(volume, fadeDuration: 0.2)
            }
            return
        }
        themeStartTask?.cancel()
        let outgoing = themePlayer
        let switching = outgoing?.isPlaying == true
        // Kill whatever's playing: a live theme fades out quick, the menu music ducks out. If the
        // outgoing theme was already faded on the focus change and the menu is still ducked, there's
        // nothing to wait for — go straight to the silent gap.
        let outDuration: TimeInterval
        if switching {
            outDuration = Self.themeFadeOut
            outgoing?.setVolume(0, fadeDuration: Self.themeFadeOut)
        } else if menuDucked {
            outDuration = 0
        } else {
            outDuration = Self.menuDuckForTheme
            duckForTheme()
        }
        guard let loaded = try? AVAudioPlayer(contentsOf: url) else { return }
        loaded.numberOfLoops = -1
        loaded.volume = 0
        loaded.prepareToPlay()
        themePlayer = loaded
        themeStartTask = Task { [weak self] in
            // Let the outgoing audio finish dying, hold the silent gap, then bring the theme up.
            try? await Task.sleep(for: .seconds(outDuration))
            outgoing?.stop()
            try? await Task.sleep(for: .seconds(Self.themeGap))
            guard !Task.isCancelled, let self, self.themePlayer === loaded else { return }
            loaded.play()
            loaded.setVolume(self.themeVolume, fadeDuration: Self.themeFadeIn)
            self.themeStartTask = nil
        }
    }

    /// Live-adjust the playing theme's volume — driven by the customize card's slider.
    func setThemeVolume(_ volume: Float) {
        themeVolume = volume
        if themePlayer?.isPlaying == true { themePlayer?.setVolume(volume, fadeDuration: 0.15) }
    }

    /// Duck the menu music down out of a starting theme's way — quick and smooth, so it's gone
    /// before the theme is audible. Shares the `menuDucked` flag with trailer ducking.
    private func duckForTheme() {
        guard enabled, !pausedForGame, !menuDucked, let player, player.isPlaying else { return }
        menuDucked = true
        player.setVolume(0, fadeDuration: Self.menuDuckForTheme)
    }

    /// Stop the theme (and cancel any queued one) and fade the menu music gently back in.
    func stopTheme() {
        themeStartTask?.cancel()
        themeStartTask = nil
        guard let player = themePlayer else { unduckFromTrailer(fadeDuration: Self.menuRestore); return }
        player.setVolume(0, fadeDuration: Self.themeFadeOut)
        themePlayer = nil
        Task { try? await Task.sleep(for: .seconds(Self.themeFadeOut + 0.05)); player.stop() }
        unduckFromTrailer(fadeDuration: Self.menuRestore)
    }

    /// Fade the current theme out immediately (fast) the moment focus leaves a game — but keep the
    /// menu music ducked. That way its song stops promptly, yet the menu never swells back in the
    /// gap before the next game's theme starts (no blip between two custom games). If we then settle
    /// on a game with no theme, `stopTheme()` brings the menu back.
    func fadeOutTheme() {
        themeStartTask?.cancel()
        themeStartTask = nil
        guard let player = themePlayer else { return }
        themePlayer = nil
        player.setVolume(0, fadeDuration: Self.themeFadeOut)
        Task { try? await Task.sleep(for: .seconds(Self.themeFadeOut + 0.05)); player.stop() }
    }

    /// A trailer started playing under the shelf — fade the user's menu music down out of its
    /// way. Rides the volume only; the player keeps running so `unduckFromTrailer` can bring it
    /// straight back. No-op if music is off, already ducked, or paused for a launched game.
    func duckForTrailer() {
        guard enabled, !pausedForGame, !menuDucked, let player, player.isPlaying else { return }
        menuDucked = true
        player.setVolume(0, fadeDuration: 0.6)
    }

    /// The trailer or theme stopped — bring the menu music back to its target volume.
    func unduckFromTrailer(fadeDuration: TimeInterval = 0.8) {
        guard menuDucked else { return }
        menuDucked = false
        // Don't fight a game-launch fade, a disabled toggle, or a paused-for-game state.
        guard enabled, !pausedForGame, pauseAfterFade == nil, gameLaunchFade == nil,
              let player else { return }
        if !player.isPlaying { player.play() }
        player.setVolume(volume, fadeDuration: fadeDuration)
    }

    /// Self-heal: if the music should be playing but the player has stopped on us (system audio
    /// reconfig, UI-sound contention, etc.), quietly bring it back. Cheap enough to call on every
    /// input. Skips while music is off, ducked for a game, or mid-fade — so it never fights those.
    func ensurePlaying() {
        guard enabled, !pausedForGame, !menuDucked,
              pauseAfterFade == nil, gameLaunchFade == nil else { return }
        guard let player else { start(); return }
        guard !player.isPlaying else { return }
        player.play()
        player.setVolume(volume, fadeDuration: 0.4)
    }

    /// User came back to Nimbus after a game — bring the music back if we ducked it for them. But
    /// while `mutedForGame` holds (game launched, focus not yet moved), stay silent: audio only
    /// resumes on moving to another item, not merely on tabbing back.
    private func appBecameActive() {
        guard pausedForGame, enabled, !mutedForGame else { return }
        pausedForGame = false
        if player == nil { start() } else { fadeIn() }
    }

    private func scanTracks() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.musicDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
