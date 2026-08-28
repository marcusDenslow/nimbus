import SwiftUI

@main
struct NimbusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var router = ViewState<InputRouter?>(nil)

    var body: some View {
        GeometryReader { geo in
            let scale = Self.uiScale(for: geo.size)
            ZStack {
                // Opaque base behind everything, in every stage. The interactive layer is scaled
                // from a fixed design size, which can leave a hairline gap at the window's right/
                // bottom edge; this guarantees that gap reads as black, not the window's gray.
                Color.black.ignoresSafeArea()

                // Full-resolution backdrop, deliberately OUTSIDE the UI scale: 4K art and video
                // render pixel-true on big displays. Only the running app uses the ambient game
                // art; boot / onboarding / the switcher draw their own silk field.
                if model.stage == .ready {
                    ZStack {
                        AmbientBackground()
                        if model.mode == .library && model.visibleLibrary.isEmpty {
                            CinematicBackground()
                                .transition(.opacity)
                        }
                    }
                    .transition(.opacity)
                }

                // Everything interactive lives in a fixed design space (~1680×1050) and is
                // scaled up to fill larger displays, so a 4K TV shows the same-sized UI as a
                // laptop instead of a zoomed-out miniature.
                ZStack {
                    switch model.stage {
                    case .boot:
                        BootView().transition(.opacity)
                    case .onboarding:
                        OnboardingView().transition(.opacity)
                    case .profileSelect:
                        ProfileSelectView().transition(.opacity)
                    case .ready:
                        content.transition(.opacity)
                    }

                    if model.standby {
                        StandbyView()
                            .transition(.opacity)
                    }

                    // On-screen keyboard sits above every stage; self-gates on keyboardActive.
                    OnScreenKeyboard()
                }
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .center)
            }
            .animation(.easeInOut(duration: 0.6), value: model.stage)
            .animation(.easeInOut(duration: 0.8), value: model.standby)
        }
        .ignoresSafeArea()
        .onAppear {
            model.start()
            if router.value == nil {
                router.value = InputRouter(model: model)
            }
        }
    }

    /// How much to blow the UI up for the current window. 1× through the reference size
    /// (a laptop-class ~1680×1050 points), growing on bigger canvases — a 4K TV driven at
    /// native points lands around 2×. Capped so absurd walls of pixels don't go billboard.
    private static func uiScale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let scale = min(size.width / 1680, size.height / 1050)
        return min(max(1, scale), 2.5)
    }

    private var content: some View {
        ZStack {
            LibraryView()
                .opacity(model.mode == .search ? 0.25 : (model.trailerHideUI ? 0 : 1))
                .blur(radius: model.mode == .search ? 18 : 0)
                .animation(.easeInOut(duration: 0.3), value: model.trailerHideUI)

            if model.mode == .search {
                SearchOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }

            if model.mode == .detail, let game = model.detailGame {
                GameDetailView(game: game)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if model.mode == .account {
                AccountView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            if model.mode == .stats {
                StatsView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if model.mode == .folderEdit {
                FolderEditView()
                    .transition(.opacity)
            }

            // Profile dropdown floats over the library; it self-gates on model.profileMenuOpen,
            // which is only ever set in library mode.
            ProfileMenu()

            VStack {
                Spacer()
                if let toast = model.toast {
                    ToastView(message: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 76)
                }
            }

            // Trailer controls: always on top while a trailer plays, even with the UI hidden, so
            // you can toggle the shelf back or close the trailer.
            if model.trailerMode {
                TrailerControls()
            }

            // Both hide while the picker's preview mode is judging applied art in the clean
            // main menu (Triangle in the picker).
            if model.customizeGameID != nil && !model.sgdbHideUI {
                CustomizeView()
                    .transition(.opacity)
            }

            if model.sgdbOpen {
                SGDBPickerView()
                    .transition(.opacity)
            }

            if model.gfnAlertVisible {
                GFNMissingView()
                    .transition(.opacity)
            }
            // (The on-screen keyboard is mounted at the root so it also covers onboarding /
            // the profile switcher, not just the ready-stage UI.)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.mode)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.toast)
        .animation(.easeInOut(duration: 0.25), value: model.gfnAlertVisible)
        .animation(.easeInOut(duration: 0.25), value: model.sgdbOpen)
        .animation(.easeInOut(duration: 0.25), value: model.sgdbHideUI)
    }
}

/// One game's ambient art, tagged with its game id and a revision token so a custom-image swap
/// on the *same* game still counts as a distinct layer (new `.id`) and crossfades cleanly.
private struct HeroArt: Equatable {
    let id: Int
    let token: Int
    let image: NSImage
    var key: String { "\(id)-\(token)" }
    static func == (a: HeroArt, b: HeroArt) -> Bool { a.id == b.id && a.token == b.token }
}

/// Darkened hero art of the focused game bleeding through the whole window, so the library takes
/// on the color of whatever you're pointing at. Dwell on a game and its Steam trailer fades in
/// over the art with sound (PS5-style), ducking the menu music while it plays.
struct AmbientBackground: View {
    @EnvironmentObject private var model: AppModel
    /// The art currently on top, fading/shifting in. `previous` holds the outgoing art beneath it
    /// during the swap so the crossfade never dips through the dark base — no flash to black.
    @StateObject private var current = ViewState<HeroArt?>(nil)
    @StateObject private var previous = ViewState<HeroArt?>(nil)
    @StateObject private var trailerURL = ViewState<URL?>(nil)
    /// A game's custom background video, played persistently (with audio unless muted).
    @StateObject private var bgVideoURL = ViewState<URL?>(nil)
    @StateObject private var bgMuted = ViewState(false)
    /// Drives the video's fade: mounted hidden, ramped up only once the player has a first
    /// frame (fading a still-black layer looks like no animation at all), ramped down before
    /// unmounting so the exit is a real fade too.
    @StateObject private var bgVideoVisible = ViewState(false)
    /// Invalidates a pending delayed unmount when focus returns to a video game mid-fade.
    @StateObject private var bgVideoGen = ViewState(0)

    /// How long to sit on one game before its theme music starts on hover.
    private static let dwell: Duration = .seconds(1.5)

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.055)

            // Outgoing art, static, underneath — cleared once the incoming fade completes.
            if let prev = previous.value {
                HeroLayer(image: prev.image).id(prev.key)
            }

            // Incoming art. Keyed by game id so a switch is insert+remove, not an in-place pixel
            // swap: that let `.fill` re-solve to the new aspect ratio and tweened the frame,
            // stretching one background into the next. `.heroShift` fades + drifts it in instead.
            if let cur = current.value {
                HeroLayer(image: cur.image)
                    .id(cur.key)
                    .transition(.heroShift)
            }


            // Custom background video, played persistently over the art (with audio unless
            // muted). Mounted invisible; onReady fades it in over the art once frames exist.
            if !model.trailerMode, let url = bgVideoURL.value {
                TrailerPlayer(url: url,
                              isActive: model.booted && model.mode == .library && !model.standby,
                              muted: bgMuted.value || model.gameAudioMuted,
                              volume: model.bgVideoVolume,
                              onReady: {
                                  withAnimation(.easeOut(duration: 0.35)) { bgVideoVisible.value = true }
                              })
                    .id(url)
                    .opacity(bgVideoVisible.value ? 1 : 0)
            }

            // Full-screen trailer video, shown when the user taps Play Trailer. Streams over the
            // art; the scrim is dropped in trailer mode so the video reads clean. Plays once — when
            // it ends we drop back to the ambient background and menu music instead of replaying.
            if model.trailerMode, let url = trailerURL.value {
                TrailerPlayer(url: url, isActive: true, loops: false, onEnded: { model.stopTrailer() })
                    .id(url)
                    .transition(.opacity)
            }

            // PS5-style scrim: the art shows untouched from the top through the middle; only
            // the bottom band darkens, just enough to carry the title, buttons, and hints.
            if !model.trailerMode {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.12), location: 0.65),
                        .init(color: .black.opacity(0.62), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .animation(.easeInOut(duration: 0.5), value: model.trailerMode)
        .task(id: model.focusedGame?.id) {
            // Focus moved to another item → lift the post-launch audio mute and resume.
            if model.gameAudioMuted {
                model.gameAudioMuted = false
                MusicPlayer.shared.resumeAfterGame()
            }
            await focusChanged(force: false)
        }
        .onChange(of: model.customizeRevision) { _, _ in Task { await focusChanged(force: true) } }
        .onChange(of: model.trailerMode) { _, on in trailerModeChanged(on) }
        .onChange(of: model.mode) { _, _ in model.stopTrailer(); MusicPlayer.shared.stopTheme() }
        .onChange(of: model.standby) { _, s in
            if s {
                model.stopTrailer()
                MusicPlayer.shared.stopTheme()
            } else {
                // Waking up: bring the focused game's theme back (it was stopped on entry).
                Task { await focusChanged(force: false) }
            }
        }
        .onChange(of: model.booted) { _, on in if on { Task { await focusChanged(force: false) } } }
    }

    /// Focus landed on a new game (or its customization changed): resolve the background — custom
    /// image / video first, else Steam hero — swap the art, then dwell and play its theme (if set).
    private func focusChanged(force: Bool) async {
        guard let game = model.focusedGame else {
            MusicPlayer.shared.stopTheme()
            fadeOutVideo(duration: 0.35)
            return
        }

        // The moment focus actually moves to another game (not a same-game revision bump), start
        // fading the outgoing theme out — don't let it linger through the dwell. The menu stays
        // ducked so it can't blip back in before the next game's theme (or `stopTheme` below brings
        // it back if the new game has none).
        if !force { MusicPlayer.shared.fadeOutTheme() }

        // Debounce: while the user steps fast the id keeps changing and cancels this task before
        // the sleep returns, so only the game they land on loads its background and swaps the art.
        // A theme already playing keeps sounding through this window, so stepping between two themed
        // games never dips back to the menu music — it lands straight on the next theme.
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        let videoURL = CustomStore.videoURL(game.id)
        bgMuted.value = CustomStore.isMuted(game.id)
        model.bgVideoVolume = CustomStore.videoVolume(game.id)

        // A game with a custom background video: mount the player right now (invisible) so it
        // spins up immediately; its onReady fades it in over whatever art is showing — and the
        // static art layers stay completely alone. Swapping the art too was the flash bug.
        if let videoURL {
            bgVideoGen.value += 1   // cancel any pending unmount from a fade-out in flight
            if bgVideoURL.value != videoURL {
                bgVideoVisible.value = false
                bgVideoURL.value = videoURL
            }
            // (Theme handling continues below; the art layers keep the previous game's art
            // underneath, invisible below the running video.)
        } else {
            // Static game. If we're arriving from a video game, the video keeps playing until
            // the incoming art has actually loaded — clearing it early flashed the *old* game's
            // still background through the gap. The video then fades out over the fresh art,
            // and only unmounts once its fade has finished.
            let art: NSImage?
            if let imgURL = CustomStore.imageURL(game.id) {
                art = NSImage(contentsOf: imgURL)
            } else {
                art = await ImageCache.shared.hero(for: game)
            }
            guard !Task.isCancelled else { return }
            if let art, force || current.value?.id != game.id {
                let outgoing = current.value
                let token = model.customizeRevision
                // The outgoing art moves into the holding layer with animations OFF — it must
                // stay fully opaque underneath. Letting it animate gave it a default fade-in
                // from zero, and for a beat both layers were translucent over the dark base:
                // the brightness dip. With it pinned solid, only the incoming art fades, which
                // is exactly how the video layers move.
                var pin = Transaction()
                pin.disablesAnimations = true
                withTransaction(pin) { previous.value = outgoing }
                withAnimation(.easeOut(duration: 0.35)) {
                    current.value = HeroArt(id: game.id, token: token, image: art)
                }
                fadeOutVideo(duration: 0.35)
                // Drop the outgoing layer once the fade is done so layers don't pile up.
                let goneKey = outgoing?.key
                Task {
                    try? await Task.sleep(for: .milliseconds(430))
                    if previous.value?.key == goneKey { previous.value = nil }
                }
            } else {
                fadeOutVideo(duration: 0.35)
            }
        }

        // Hover-to-play theme music — library only, past the boot screen, not over a trailer.
        // Plays alongside a custom background video's own audio (both layer together by design).
        guard model.booted, model.mode == .library, !model.standby, !model.trailerMode else {
            MusicPlayer.shared.stopTheme()
            return
        }
        guard let theme = ThemeStore.themeURL(gameID: game.id) else {
            // No theme here — fade any playing one out and let the menu music swell back.
            MusicPlayer.shared.stopTheme()
            return
        }
        // Dwell before starting a theme, so a quick pass-through stays quiet. The dwell applies even
        // when switching between two themed games — but the outgoing theme keeps sounding through it,
        // so the transition never dips back to the menu music; it just waits, then crossfades.
        try? await Task.sleep(for: Self.dwell)
        guard !Task.isCancelled, model.focusedGame?.id == game.id, !model.trailerMode else { return }
        MusicPlayer.shared.playTheme(url: theme, volume: ThemeStore.volume(gameID: game.id))
    }

    /// Fade the background video down, then unmount it once the fade has finished. A generation
    /// token guards the delayed unmount: focus landing back on a video game mid-fade bumps it,
    /// so the pending removal can't yank the fresh player out.
    private func fadeOutVideo(duration: TimeInterval) {
        guard bgVideoURL.value != nil else { return }
        bgVideoGen.value += 1
        let gen = bgVideoGen.value
        withAnimation(.easeOut(duration: duration)) { bgVideoVisible.value = false }
        Task {
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 80))
            guard bgVideoGen.value == gen else { return }
            bgVideoURL.value = nil
        }
    }

    /// Trailer mode toggled from the hero panel: stream the focused game's trailer in, or tear it
    /// down and restore audio when it closes.
    private func trailerModeChanged(_ on: Bool) {
        if on {
            MusicPlayer.shared.stopTheme()
            Task { await loadTrailerVideo() }
        } else {
            trailerURL.value = nil
            MusicPlayer.shared.unduckFromTrailer()
        }
    }

    private func loadTrailerVideo() async {
        guard let game = model.focusedGame else { model.stopTrailer(); return }
        MusicPlayer.shared.duckForTrailer()
        guard let url = await TrailerCache.shared.trailer(for: game) else {
            model.stopTrailer(); return
        }
        guard model.trailerMode else { return }
        trailerURL.value = url
    }
}

/// One game's ambient art. `image` is a stored `let`, so when `AmbientBackground` swaps in a
/// new HeroLayer (new `.id`) the outgoing instance keeps rendering its own art through the fade
/// — a true crossfade between the two pictures, not a flash of the new one over itself.
private struct HeroLayer: View {
    let image: NSImage

    var body: some View {
        // Overlay on Color.clear so the fill-mode image can't inflate the layout — reported at
        // its natural fill size it forces the whole window's ZStack to the art's aspect ratio
        // and pushes every sibling offscreen. Full opacity — the art shows as-is; only the
        // bottom scrim gradient sits over it. Layers stay opaque so a crossfade can't
        // over-brighten or dip.
        Color.clear
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}

/// Bottom-right controls floating over a playing trailer: toggle the shelf/hero UI, and close.
/// Kept clear of the top-right account chip and the bottom hint bar. Controller-driven too —
/// Triangle toggles the UI, Circle exits (shown as glyph hints under each button).
private struct TrailerControls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Spacer()
                button(model.trailerHideUI ? "eye" : "eye.slash",
                       glyph: "triangle.circle.fill",
                       label: model.trailerHideUI ? "Show UI" : "Hide UI") { model.toggleTrailerUI() }
                button("xmark", glyph: "circle.circle.fill", label: "Exit") { model.stopTrailer() }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 84)
    }

    private func button(_ symbol: String, glyph: String, label: String,
                        action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                if model.controllerConnected {
                    Image(systemName: glyph).font(.system(size: 12, weight: .semibold))
                }
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
        }
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}
