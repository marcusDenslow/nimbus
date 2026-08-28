import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum InputEvent {
    case left, right, up, down
    case confirm  // A / Return
    case back  // B / Esc
    case remove  // X / Delete
    case toggleSearch  // Menu / Cmd-F / "/"
    case sync  // Options / Cmd-S
    case info  // Square / i — open the game detail page
    case folderPrev  // L1 / [
    case folderNext  // R1 / ]
}

/// One button on the game detail page. `toggleFolder` carries the folder id it acts on.
enum DetailAction: Equatable {
    case play
    case toggleLibrary
    case toggleFavorite
    case toggleFolder(String)
    case newFolder
}

/// Which pool the search overlay is looking at: the full GFN catalog (add games) or the
/// user's own library (find + jump to a shelf game).
enum SearchScope { case catalog, library }

/// Which row of the library screen has focus. Pressing Up from the shelf lifts focus into
/// the top bar (folders / sort / profile), PS5-style; Down drops back to the shelf.
enum LibraryZone { case shelf, topBar }

/// A focusable item in the top bar. `.folder(nil)` is the "All Games" tab.
enum TopBarItem: Equatable {
    case folder(String?)
    case sort, profile
}

/// A quick-action in the profile dropdown, top-right of the library. `.surprise` is the
/// random-game picker; the rest mirror existing shortcuts so they're reachable by mouse.
enum ProfileMenuItem: CaseIterable, Equatable {
    case surprise, addGames, sync, stats, account, switchProfile, standby, quit
}

/// The per-game dropdown behind the shelf's ⋯ button: Info / Customize / Favorite / Play Trailer.
enum ShelfMenuItem: CaseIterable, Equatable { case info, customize, favorite, playTrailer }

/// A major section of the customize card, stepped Up/Down. Each is a boxed group the controller
/// highlights as a whole; Cross/Square enters it to edit the controls inside.
enum CustomizeSection: Int, CaseIterable { case image, logo, video, theme, actions }

/// A control inside an entered customize section, stepped Left/Right. `.volume` is special: on it,
/// Left/Right adjust the value instead of moving off it. `.sgdb` opens the SteamGridDB picker;
/// `.clearCard` drops a custom cover set from it.
enum CustomizeControl: Equatable {
    case set, sgdb, clear, clearCard, audio, volume, playTrailer, done
}

/// Which text field the on-screen keyboard is currently feeding.
enum KeyboardTarget: Equatable {
    case search, playerName
    case folderName(String)
    case sgdbKey, sgdbQuery, draftName
}

/// One key on the on-screen keyboard.
enum KeyboardKey: Equatable {
    case char(String)
    case space, backspace, shift, done
}

/// A control on the folder-edit popup, stepped with Up/Down.
enum FolderEditControl: Int, CaseIterable { case name, color, delete, done }

/// A focusable control on the profile/account page, for stick/d-pad navigation.
enum AccountFocus: Equatable, Hashable {
    case name, sort, musicToggle, volume, openMusicFolder, reloadMusic
    case accent, standby, bootBehavior
    case folder(String)
    case newFolder, switchProfile, done
}

@MainActor
final class AppModel: ObservableObject {
    enum Mode: Equatable { case library, search, detail, account, folderEdit, stats }

    /// The pre-library boot flow: the cinematic press-to-enter screen, first-run onboarding,
    /// the PS5-style profile switcher, then the running app.
    enum Stage: Equatable { case boot, onboarding, profileSelect, ready }
    @Published var stage: Stage = .boot

    @Published var mode: Mode = .library
    @Published var library: [Game] = []
    @Published var catalog: [Game] = []
    @Published var focusedIndex = 0 {
        didSet {
            shelfAction = .none
            shelfMenuOpen = false
            prefetchAroundFocus()
        }
    }
    @Published var searchQuery = "" {
        didSet { updateSearchResults() }
    }
    @Published var searchResults: [Game] = []
    @Published var searchFocusedIndex = 0 { didSet { prefetchAroundFocus() } }
    @Published var searchColumns = 6
    /// Sticky across opens: stays on the pool the user last searched.
    @Published var searchScope: SearchScope = .catalog
    /// Full-screen "GeForce NOW isn't installed" overlay, shown when a launch finds no handler
    /// for the geforcenow:// scheme.
    @Published var gfnAlertVisible = false
    @Published var toast: String?
    @Published var controllerConnected = false
    @Published var catalogError: String?
    @Published var catalogLoading = false

    // MARK: - Sorting, folders, detail, profile

    @Published var sortMode: SortMode = .recent
    @Published var folders: [Folder] = []
    @Published var activeFolderID: String?
    @Published var detailGame: Game?
    @Published var detailActionIndex = 0
    @Published var playerName = "Player"
    @Published var musicEnabled = true
    @Published var musicVolume: Float = 0.5

    // MARK: - Profiles & global config

    /// Global, cross-profile state (the profile roster, boot behavior, standby delay). Persisted
    /// in `app.json` beside the shared catalog.
    @Published var config = AppConfig()
    /// The profile whose library/folders/settings are currently loaded.
    @Published var activeProfileID: String?
    var activeProfile: Profile? { config.profiles.first { $0.id == activeProfileID } }

    /// Whole-app accent color, sourced from the active profile's pick.
    var accentIndex: Int { activeProfile?.accentIndex ?? AccentPalette.currentIndex }
    var accent: Color { AccentPalette.color(accentIndex) }
    var accentDeep: Color { AccentPalette.deep(accentIndex) }
    var accentGradient: [Color] { AccentPalette.gradient(accentIndex) }

    /// Profile switcher (PS5-style). Index into `config.profiles`; the trailing slot is "Add".
    @Published var profileSelectIndex = 0

    // MARK: - Onboarding

    enum OnboardingStep: Equatable { case welcome, profile, geforce, artKey, finish }
    @Published var onboardingSteps: [OnboardingStep] = []
    @Published var onboardingIndex = 0
    @Published var onboardingFocus = 0
    /// True when the flow was entered to add another profile (skips welcome/GFN/key steps).
    @Published var onboardingIsAdd = false
    /// Draft profile being built by the onboarding / add-profile flow.
    @Published var draftName = "Player"
    @Published var draftColorIndex = 0
    @Published var draftAccentIndex = 0

    var onboardingStep: OnboardingStep? {
        onboardingSteps.indices.contains(onboardingIndex) ? onboardingSteps[onboardingIndex] : nil
    }

    // MARK: - Stats dashboard

    enum StatsRange: String, CaseIterable, Equatable {
        case week, month, year, all
        var label: String {
            switch self {
            case .week: return "7 Days"
            case .month: return "30 Days"
            case .year: return "This Year"
            case .all: return "All Time"
            }
        }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
    }
    @Published var statsRange: StatsRange = .month
    @Published var statsFocusIndex = 0
    /// Completed play sessions for the active profile — the raw material for the dashboard.
    @Published var history: [PlaySession] = []
    /// Bumps as background Steam enrichment lands, so the dashboard recomputes quality stats.
    @Published var enrichmentRevision = 0

    /// Boot intro gate — the library UI shows only after the user presses to start.
    @Published var booted = false

    /// Standby screensaver — after `standbyDelay` of no input the wave/clock takes over.
    @Published var standby = false
    private var lastActivity = Date()
    private var standbyTimer: Timer?
    /// Idle time before the screensaver, from the user's setting (minutes). Clamped so a stray
    /// value can't disable standby entirely or thrash it on.
    private var standbyDelay: TimeInterval {
        TimeInterval(min(120, max(1, config.standbyMinutes)) * 60)
    }

    @Published var libraryZone: LibraryZone = .shelf
    @Published var topBarIndex = 0

    /// Profile dropdown (top-right): whether it's open and which row is highlighted.
    @Published var profileMenuOpen = false
    @Published var profileMenuIndex = 0

    /// Full-screen trailer preview over the library; `trailerHideUI` toggles the shelf/hero UI
    /// on top of the video so you can watch it clean.
    @Published var trailerMode = false
    @Published var trailerHideUI = false

    func playTrailer() {
        guard focusedGame != nil else { return }
        trailerHideUI = false
        trailerMode = true
    }

    func stopTrailer() {
        trailerMode = false
        trailerHideUI = false
    }

    func toggleTrailerUI() { trailerHideUI.toggle() }

    /// Assign the user's picked audio file as a game's hover theme.
    func setTheme(for game: Game, from url: URL) {
        ThemeStore.setTheme(gameID: game.id, from: url)
        showToast("Theme set for \(game.title)")
    }

    // MARK: - SteamGridDB picker

    /// Artwork search overlay reached from the customize card's image section. Browses heroes
    /// (backgrounds) or grids (shelf-card covers); pick one and it's installed for the game.
    @Published var sgdbOpen = false
    @Published var sgdbKind: SteamGridDB.Kind = .hero
    @Published var sgdbQuery = ""
    /// The SGDB game the search resolved to, shown so a wrong match is obvious.
    @Published var sgdbMatchName: String?
    @Published var sgdbImages: [SteamGridDB.SGDBImage] = []
    @Published var sgdbLoading = false
    @Published var sgdbError: String?
    @Published var sgdbIndex = 0
    /// +1 stepping right, -1 stepping left — the preview slides old art out one way and new art
    /// in from the other. Set before `sgdbIndex` changes so the transition reads it in time.
    @Published var sgdbSlideDirection: CGFloat = 1
    /// Full-screen grid browser over all results — opened with Down from the rail, closed with
    /// Circle/Esc. Shares `sgdbIndex` with the rail, so both views track one selection.
    @Published var sgdbGridOpen = false
    /// Triangle in the picker: hide the picker (and the customize card under it) so the freshly
    /// applied art can be judged in the real main menu. Triangle/Circle/Cross brings the UI back.
    @Published var sgdbHideUI = false

    /// Grid browser columns per pool — wide art gets fewer, portrait covers more.
    var sgdbGridColumns: Int {
        switch sgdbKind {
        case .screenshot, .wallpaper, .logo: return 4
        case .hero: return 3
        case .grid: return 6
        }
    }
    /// Live text of the API-key field (saved on submit, not per keystroke).
    @Published var sgdbKeyDraft = ""
    private var sgdbSearchTask: Task<Void, Never>?

    func openSGDB(_ game: Game, kind: SteamGridDB.Kind? = nil) {
        sgdbQuery = game.title
        sgdbIndex = 0
        sgdbImages = []
        sgdbError = nil
        sgdbMatchName = nil
        sgdbKeyDraft = SteamGridDB.apiKey
        // Caller can land the picker on a specific pool (the Logo section does). Otherwise:
        // true 16:9 backgrounds come from Steam screenshots, so Steam titles start there;
        // everything else opens on SGDB's hero banners.
        sgdbKind = kind ?? (game.steamAppID != nil ? .screenshot : .hero)
        sgdbOpen = true
        Sound.select()
        if SteamGridDB.hasKey { runSGDBSearch() }
    }

    /// Switch the picker's art pool and re-fetch.
    func setSGDBKind(_ kind: SteamGridDB.Kind) {
        guard kind != sgdbKind else { return }
        sgdbKind = kind
        Sound.tick()
        if SteamGridDB.hasKey { runSGDBSearch() }
    }

    /// L1 / R1: step the pool cycle backgrounds ↔ wallpapers ↔ banners ↔ covers ↔ logos.
    func stepSGDBKind(_ delta: Int) {
        let all = SteamGridDB.Kind.allCases
        guard let current = all.firstIndex(of: sgdbKind) else { return }
        setSGDBKind(all[(current + delta + all.count) % all.count])
    }

    /// Controller-friendly key entry: read the key straight off the system clipboard.
    func pasteSGDBKey() {
        guard
            let pasted = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty
        else {
            sgdbError = "Clipboard is empty — copy your API key first"
            Sound.back()
            return
        }
        sgdbError = nil
        sgdbKeyDraft = pasted
        saveSGDBKey()
        Sound.select()
    }

    func closeSGDB() {
        sgdbSearchTask?.cancel()
        sgdbLoading = false
        sgdbGridOpen = false
        sgdbHideUI = false
        sgdbOpen = false
        Sound.back()
    }

    func saveSGDBKey() {
        SteamGridDB.apiKey = sgdbKeyDraft
        sgdbKeyDraft = SteamGridDB.apiKey
        if SteamGridDB.hasKey { runSGDBSearch() }
    }

    func runSGDBSearch() {
        sgdbSearchTask?.cancel()
        let query = sgdbQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        sgdbLoading = true
        sgdbError = nil
        sgdbImages = []
        sgdbIndex = 0
        let kind = sgdbKind

        // Wallpapers ride Wallhaven's keyless search — community art, deepest 4K pool around.
        if kind == .wallpaper {
            sgdbSearchTask = Task { [weak self] in
                do {
                    let images = try await SteamGridDB.wallhavenSearch(query: query)
                    guard !Task.isCancelled else { return }
                    self?.sgdbMatchName = query
                    self?.sgdbImages = images
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.sgdbError = "No wallpapers found for this search — try fewer words"
                }
                self?.sgdbLoading = false
            }
            return
        }

        // Backgrounds ride Steam's screenshot API (16:9), not SGDB. A missing steamUrl doesn't
        // mean the game isn't on Steam (GFN-cache recoveries lack it), so fall back to
        // resolving the title through Steam's own keyless store search.
        if kind == .screenshot {
            let knownAppID = customizeGame?.steamAppID
            let title = customizeGame?.title ?? query
            sgdbSearchTask = Task { [weak self] in
                do {
                    let appID: String
                    if let knownAppID {
                        appID = knownAppID
                    } else {
                        appID = try await SteamGridDB.steamAppID(title: title)
                    }
                    let images = try await SteamGridDB.steamScreenshots(appID: appID)
                    guard !Task.isCancelled else { return }
                    self?.sgdbMatchName = title
                    self?.sgdbImages = images
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.sgdbError =
                        "Couldn't find Steam screenshots for this title — try Banners instead"
                }
                self?.sgdbLoading = false
            }
            return
        }

        sgdbSearchTask = Task { [weak self] in
            do {
                let (match, images) = try await SteamGridDB.imagesForTitle(query, kind: kind)
                guard !Task.isCancelled else { return }
                self?.sgdbMatchName = match
                self?.sgdbImages = images
            } catch {
                guard !Task.isCancelled else { return }
                self?.sgdbError = error.localizedDescription
            }
            self?.sgdbLoading = false
        }
    }

    /// Download the pick full-res and install it — hero → ambient background, grid → card cover.
    func applySGDB(_ image: SteamGridDB.SGDBImage) {
        guard let game = customizeGame, !sgdbLoading else { return }
        let kind = sgdbKind
        sgdbLoading = true
        Task { [weak self] in
            guard let self else { return }
            guard let file = try? await SteamGridDB.download(image) else {
                self.sgdbLoading = false
                self.sgdbError = "Download failed — try another image"
                return
            }
            switch kind {
            case .screenshot, .wallpaper, .hero: CustomStore.setImage(game.id, from: file)
            case .grid: CustomStore.setCard(game.id, from: file)
            case .logo: CustomStore.setLogo(game.id, from: file)
            }
            try? FileManager.default.removeItem(at: file)
            self.sgdbLoading = false
            // Stays open: the change lands live behind the picker (and Triangle hides the UI
            // to judge it in the clean main menu), so you can keep trying picks.
            self.bumpCustomize()
            switch kind {
            case .screenshot: self.showToast("Background set from Steam screenshots")
            case .wallpaper: self.showToast("Background set from Wallhaven")
            case .hero: self.showToast("Background set from SteamGridDB")
            case .grid: self.showToast("Cover art set from SteamGridDB")
            case .logo: self.showToast("Logo set from SteamGridDB")
            }
            Sound.select()
        }
    }

    private func handleSGDB(_ event: InputEvent) {
        // Key entry screen: Cross pastes from the clipboard, Square types via the OSK.
        guard SteamGridDB.hasKey else {
            switch event {
            case .confirm: pasteSGDBKey()
            case .info: beginKeyboard(.sgdbKey, initial: sgdbKeyDraft, title: "SteamGridDB API key")
            case .back: closeSGDB()
            default: break
            }
            return
        }
        // Hidden-UI preview: everything is swallowed except the ways back in.
        if sgdbHideUI {
            switch event {
            case .remove, .back, .confirm:
                sgdbHideUI = false
                Sound.tick()
            default: break
            }
            return
        }
        // Grid browser up: two-axis navigation over every result; Circle drops back to the rail.
        if sgdbGridOpen {
            switch event {
            case .left: moveSGDB(by: -1)
            case .right: moveSGDB(by: 1)
            case .up: moveSGDB(by: -sgdbGridColumns)
            case .down: moveSGDB(by: sgdbGridColumns)
            case .confirm:
                if sgdbImages.indices.contains(sgdbIndex) { applySGDB(sgdbImages[sgdbIndex]) }
            case .remove:
                sgdbHideUI = true  // Triangle → clean look at the main menu
                Sound.tick()
            case .folderPrev: stepSGDBKind(-1)  // L1 / R1 step the art pools
            case .folderNext: stepSGDBKind(1)
            case .info: beginKeyboard(.sgdbQuery, initial: sgdbQuery, title: "Search SteamGridDB")
            case .back:
                sgdbGridOpen = false
                Sound.back()
            case .toggleSearch, .sync: break
            }
            return
        }
        // Hero-focus layout: Left/Right step the rail, Down opens the all-results grid.
        switch event {
        case .left: moveSGDB(by: -1)
        case .right: moveSGDB(by: 1)
        case .down:
            if !sgdbImages.isEmpty {
                sgdbGridOpen = true
                Sound.select()
            }
        case .confirm:
            if sgdbImages.indices.contains(sgdbIndex) { applySGDB(sgdbImages[sgdbIndex]) }
        case .remove:
            sgdbHideUI = true  // Triangle → clean look at the main menu
            Sound.tick()
        case .folderPrev: stepSGDBKind(-1)  // L1 / R1 step the art pools
        case .folderNext: stepSGDBKind(1)
        case .info:
            // Square → re-open the keyboard to edit the search text.
            beginKeyboard(.sgdbQuery, initial: sgdbQuery, title: "Search SteamGridDB")
        case .back: closeSGDB()
        default: break
        }
    }

    private func moveSGDB(by delta: Int) {
        guard !sgdbImages.isEmpty else { return }
        let target = min(max(0, sgdbIndex + delta), sgdbImages.count - 1)
        guard target != sgdbIndex else { return }
        sgdbSlideDirection = delta >= 0 ? 1 : -1
        sgdbIndex = target
        Sound.tick()
    }

    /// Per-game customize sheet (custom background image/video + theme). `customizeRevision`
    /// bumps whenever an asset changes so the ambient background re-resolves it live.
    @Published var customizeGameID: Int?
    @Published var customizeRevision = 0
    /// Controller focus inside the customize card: the highlighted section, whether we've stepped
    /// into it to edit, and which control within it is focused.
    @Published var customizeSection: CustomizeSection = .image
    @Published var customizeEditing = false
    @Published var customizeControl = 0
    /// Live playback volume for the focused game's custom background video, so the slider (mouse or
    /// controller) adjusts it in real time. Mirrors CustomStore.videoVolume for the focused game.
    @Published var bgVideoVolume: Float = CustomStore.defaultVideoVolume
    /// Set the moment a game is launched and cleared when focus moves to another item. While true,
    /// the background-video player mutes (and MusicPlayer holds its own game mute), so no app audio
    /// plays under the running game. See `launch(_:)` and the focus handler in NimbusApp.
    @Published var gameAudioMuted = false
    var customizeGame: Game? { customizeGameID.flatMap { id in library.first { $0.id == id } } }

    func openCustomize(_ game: Game) {
        customizeGameID = game.id
        customizeSection = .image
        customizeEditing = false
        customizeControl = 0
    }
    func closeCustomize() {
        customizeGameID = nil
        customizeEditing = false
    }
    func bumpCustomize() { customizeRevision += 1 }

    /// Controls available in a section, given what the game currently has assigned.
    func customizeControls(_ section: CustomizeSection, game: Game) -> [CustomizeControl] {
        switch section {
        case .image:
            var controls: [CustomizeControl] = [.set, .sgdb]
            if CustomStore.imageURL(game.id) != nil { controls.append(.clear) }
            if CustomStore.cardURL(game.id) != nil { controls.append(.clearCard) }
            return controls
        case .logo:
            return CustomStore.logoURL(game.id) != nil ? [.set, .sgdb, .clear] : [.set, .sgdb]
        case .video:
            return CustomStore.videoURL(game.id) != nil ? [.set, .clear, .audio, .volume] : [.set]
        case .theme:
            return ThemeStore.hasTheme(gameID: game.id) ? [.set, .clear, .volume] : [.set]
        case .actions:
            return [.playTrailer, .done]
        }
    }

    /// The control the customize card is focused on right now, if we're editing a section.
    var focusedCustomizeControl: CustomizeControl? {
        guard customizeEditing, let game = customizeGame else { return nil }
        let controls = customizeControls(customizeSection, game: game)
        return controls.indices.contains(customizeControl) ? controls[customizeControl] : nil
    }

    private func handleCustomize(_ event: InputEvent) {
        guard let game = customizeGame else {
            closeCustomize()
            return
        }
        if customizeEditing {
            let controls = customizeControls(customizeSection, game: game)
            let onVolume =
                controls.indices.contains(customizeControl) && controls[customizeControl] == .volume
            switch event {
            case .up, .down, .back:
                customizeEditing = false
                Sound.back()
            case .left:
                if onVolume {
                    nudgeVolume(game, -0.05)
                } else {
                    customizeControl = max(0, customizeControl - 1)
                    Sound.tick()
                }
            case .right:
                if onVolume {
                    nudgeVolume(game, 0.05)
                } else {
                    customizeControl = min(controls.count - 1, customizeControl + 1)
                    Sound.tick()
                }
            case .confirm, .info:
                activateCustomizeControl(game)
            default:
                break
            }
        } else {
            switch event {
            case .up: moveCustomizeSection(-1)
            case .down: moveCustomizeSection(1)
            case .confirm, .info:
                customizeEditing = true
                customizeControl = 0
                Sound.select()
            case .back:
                closeCustomize()
                Sound.back()
            default:
                break
            }
        }
    }

    private func moveCustomizeSection(_ delta: Int) {
        let all = CustomizeSection.allCases
        guard let i = all.firstIndex(of: customizeSection) else { return }
        let next = all[min(max(0, i + delta), all.count - 1)]
        guard next != customizeSection else { return }
        customizeSection = next
        Sound.tick()
    }

    private func activateCustomizeControl(_ game: Game) {
        let controls = customizeControls(customizeSection, game: game)
        guard controls.indices.contains(customizeControl) else { return }
        switch (customizeSection, controls[customizeControl]) {
        case (.image, .set): pickCustomImage(game)
        case (.image, .sgdb): openSGDB(game)
        case (.image, .clear):
            CustomStore.clearImage(game.id)
            bumpCustomize()
        case (.image, .clearCard):
            CustomStore.clearCard(game.id)
            bumpCustomize()
        case (.logo, .set): pickCustomLogo(game)
        case (.logo, .sgdb): openSGDB(game, kind: .logo)
        case (.logo, .clear):
            CustomStore.clearLogo(game.id)
            bumpCustomize()
        case (.video, .set): pickCustomVideo(game)
        case (.video, .clear):
            CustomStore.clearVideo(game.id)
            bumpCustomize()
        case (.video, .audio):
            CustomStore.setMuted(game.id, !CustomStore.isMuted(game.id))
            bumpCustomize()
        case (.theme, .set): pickCustomTheme(game)
        case (.theme, .clear): clearCustomTheme(game)
        case (.actions, .playTrailer):
            closeCustomize()
            playTrailer()
        case (.actions, .done):
            closeCustomize()
            Sound.back()
        default: break
        }
        // Clearing/setting changes which controls exist — keep the index in range.
        let now = customizeControls(customizeSection, game: game)
        customizeControl = min(customizeControl, max(0, now.count - 1))
    }

    /// Adjust the focused section's volume slider (theme music or custom video) and apply it live.
    private func nudgeVolume(_ game: Game, _ delta: Float) {
        switch customizeSection {
        case .theme:
            let v = min(max(0, ThemeStore.volume(gameID: game.id) + delta), 1)
            ThemeStore.setVolume(gameID: game.id, v)
            MusicPlayer.shared.setThemeVolume(v)
        case .video:
            let v = min(max(0, CustomStore.videoVolume(game.id) + delta), 1)
            CustomStore.setVideoVolume(game.id, v)
            bgVideoVolume = v
        default:
            break
        }
        Sound.tick()
    }

    private func clearCustomTheme(_ game: Game) {
        if let old = ThemeStore.themeURL(gameID: game.id) {
            try? FileManager.default.removeItem(at: old)
        }
        bumpCustomize()
    }

    // Shared pickers — used by both the pointer (CustomizeView) and the controller handler.
    func pickCustomImage(_ game: Game) {
        if let url = openFilePanel([.image]) {
            CustomStore.setImage(game.id, from: url)
            bumpCustomize()
        }
    }
    func pickCustomVideo(_ game: Game) {
        if let url = openFilePanel([.movie, .video, .mpeg4Movie, .quickTimeMovie]) {
            CustomStore.setVideo(game.id, from: url)
            bumpCustomize()
        }
    }
    func pickCustomLogo(_ game: Game) {
        if let url = openFilePanel([.image]) {
            CustomStore.setLogo(game.id, from: url)
            bumpCustomize()
        }
    }
    func pickCustomTheme(_ game: Game) {
        if let url = openFilePanel([.audio]) {
            setTheme(for: game, from: url)
            bumpCustomize()
        }
    }

    private func openFilePanel(_ types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = types
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Trailer overlay input: Triangle toggles the shelf/hero UI, Circle exits. Everything else is
    /// swallowed so the controller can't drive the shelf hidden behind the video.
    private func handleTrailer(_ event: InputEvent) {
        switch event {
        case .remove: toggleTrailerUI()
        case .back: stopTrailer()
        default: break
        }
    }

    /// Live R2 pull (0…1) while a game is launch-ready, for the Play button's draw animation.
    @Published var triggerPull: CGFloat = 0

    /// Set for the duration of the launch burst animation; the overlay keys off it. Non-nil means
    /// "play the ignition sequence for this game right now."
    @Published var launchingGame: Game?
    private var launchFXTask: Task<Void, Never>?

    /// On-screen keyboard: controller-driven text entry (no hardware keyboard needed).
    @Published var keyboardActive = false
    @Published var keyboardText = ""
    @Published var keyboardTitle = ""
    @Published var keyboardRow = 1
    @Published var keyboardCol = 0
    @Published var keyboardShift = false
    private var keyboardTarget: KeyboardTarget?

    /// Folder-edit popup: the folder under edit, the focused control, and its inline name field.
    @Published var folderEditID: String?
    @Published var folderEditIndex = 0
    @Published var folderEditNameEditing = false

    /// Sub-focus on the focused shelf card: the card body, or its Play / Info buttons.
    /// Down from the card drops into Play; Right steps Play → Info. Reset whenever focus moves.
    enum ShelfAction: Equatable { case none, play, info }
    @Published var shelfAction: ShelfAction = .none

    /// Profile-page focus + inline text editing.
    @Published var accountIndex = 0
    @Published var accountEditing = false
    @Published var editingFolderID: String?  // nil while editing means the name field

    /// Raw left-stick vector (x right+, y up+), updated by InputRouter; drives the particle
    /// background drift. Kept non-published so 30 Hz updates don't churn SwiftUI.
    var stickDirection: CGVector = .zero
    var particleDrift: CGVector { CGVector(dx: stickDirection.dx, dy: -stickDirection.dy) }

    /// True when the last focus change came from the pointer. Auto-scroll skips those:
    /// scrolling under a resting cursor re-triggers hover on whatever slides beneath it,
    /// which re-focuses and re-scrolls in an endless loop.
    private(set) var focusChangeFromPointer = false
    /// While the shelf animates after stick/keyboard navigation, cards slide beneath a
    /// stationary cursor and fire onHover. Accepting those steals focus back and makes
    /// navigation stutter and jump, so pointer focus is ignored briefly after each move.
    private var pointerFocusBlockedUntil: TimeInterval = 0

    private var toastTask: Task<Void, Never>?
    private var libraryIDs: Set<Int> = []

    private static let prefetchRadius = 6

    // MARK: - Paths

    static let supportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nimbus", isDirectory: true)

    /// Global config (profile roster + app-wide prefs), shared across profiles.
    private var configFile: URL { Self.supportDir.appendingPathComponent("app.json") }
    private var profilesDir: URL {
        Self.supportDir.appendingPathComponent("profiles", isDirectory: true)
    }
    /// The active profile's private folder. Falls back to a `default` slot before a profile is
    /// chosen, so nothing crashes if a save races the boot flow.
    private var profileDir: URL {
        profilesDir.appendingPathComponent(activeProfileID ?? "default", isDirectory: true)
    }

    // Per-profile files.
    private var libraryFile: URL { profileDir.appendingPathComponent("library.json") }
    private var foldersFile: URL { profileDir.appendingPathComponent("folders.json") }
    private var settingsFile: URL { profileDir.appendingPathComponent("settings.json") }
    private var historyFile: URL { profileDir.appendingPathComponent("history.json") }

    // Global files (shared): the GFN catalog cache lives at the support root.
    private var catalogFile: URL { Self.supportDir.appendingPathComponent("catalog.json") }
    /// Games recovered from the GFN client's cache that NVIDIA's static list doesn't have.
    /// Persisted so search keeps working even after GFN evicts its cache.
    private var extrasFile: URL { Self.supportDir.appendingPathComponent("catalog-extra.json") }

    private static let catalogURL = URL(
        string: "https://static.nvidiagrid.net/supported-public-game-list/locales/gfnpc-en-US.json")!
    private static let catalogMaxAge: TimeInterval = 24 * 60 * 60

    // MARK: - Lifecycle

    func start() {
        try? FileManager.default.createDirectory(
            at: Self.supportDir, withIntermediateDirectories: true)
        loadConfig()
        migrateLegacyIfNeeded()
        MusicPlayer.shared.onTrackChange = { [weak self] name in self?.showToast("♪ \(name)") }
        // Ambient menu music from the very first screen; re-tuned to the profile's prefs on activate.
        MusicPlayer.shared.configure(enabled: true, volume: 0.5)
        startStandbyWatch()
        watchForSessionEnd()
        Task { await loadCatalog() }  // the GFN catalog is shared across profiles
    }

    // MARK: - Playtime

    /// The running play session: which game and when it started. Ends when the GFN app quits,
    /// another game launches, or Nimbus exits.
    private var activeSession: (gameID: Int, start: Date)?
    private nonisolated static let gfnBundleID = "com.nvidia.gfnpc.mall"
    /// Sessions shorter than this don't count — covers launch misfires and instant quits.
    private static let minSessionSeconds: TimeInterval = 30

    private func watchForSessionEnd() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                app.bundleIdentifier == Self.gfnBundleID
            else { return }
            MainActor.assumeIsolated { self?.endPlaySession() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endPlaySession() }
        }
    }

    private func beginPlaySession(_ game: Game) {
        endPlaySession()
        activeSession = (game.id, Date())
    }

    /// Close the running session and bank its duration onto the game.
    private func endPlaySession() {
        guard let session = activeSession else { return }
        activeSession = nil
        let seconds = Date().timeIntervalSince(session.start)
        guard seconds >= Self.minSessionSeconds,
            let index = library.firstIndex(where: { $0.id == session.gameID })
        else { return }
        library[index].playSeconds = (library[index].playSeconds ?? 0) + seconds
        saveLibrary()
        // Log the session for the stats dashboard (trends, streaks, heatmaps).
        history.append(
            PlaySession(
                gameID: session.gameID, title: library[index].title,
                start: session.start, seconds: seconds))
        if history.count > 4000 { history.removeFirst(history.count - 4000) }
        saveHistory()
    }

    /// Total across the library, for the profile stats card.
    var totalPlaySeconds: TimeInterval {
        library.reduce(0) { $0 + ($1.playSeconds ?? 0) }
    }

    // MARK: - Standby

    /// Any input calls this: resets the idle clock so active use never falls into standby.
    /// Does NOT wake the screensaver — that's `wakeFromStandby()`, gated to a designated button,
    /// so a bumped stick or stray press can't yank you out of standby by accident.
    func noteActivity() {
        lastActivity = Date()
        MusicPlayer.shared.ensurePlaying()  // resume if playback stopped out from under us
    }

    /// Drop into standby on demand (profile menu). Same screensaver the idle watcher shows;
    /// ✕ / Return / a click wakes it. No-op if already asleep or before boot.
    func enterStandby() {
        guard booted, stage == .ready, !standby else { return }
        standby = true
        lastActivity = Date()
    }

    /// The one way out of standby: ✕ / Cross on the pad, Return/Space on the keyboard, or a click.
    func wakeFromStandby() {
        guard standby else { return }
        standby = false
        lastActivity = Date()
        Sound.back()
    }

    private func startStandbyWatch() {
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStandby() }
        }
        RunLoop.main.add(timer, forMode: .common)
        standbyTimer = timer
    }

    private func checkStandby() {
        guard booted, stage == .ready, !standby else { return }
        if Date().timeIntervalSince(lastActivity) >= standbyDelay {
            standby = true
        }
    }

    // MARK: - Input

    func handle(_ event: InputEvent) {
        // The on-screen keyboard owns input wherever it's up (onboarding name, search, …).
        if keyboardActive {
            handleKeyboard(event)
            return
        }

        // Pre-library flow is driven by stage, not mode.
        switch stage {
        case .boot: return
        case .onboarding:
            handleOnboarding(event)
            return
        case .profileSelect:
            handleProfileSelect(event)
            return
        case .ready: break
        }

        if gfnAlertVisible {
            if event == .confirm || event == .back { dismissGFNAlert() }
            return
        }
        switch mode {
        case .library: handleLibrary(event)
        case .search: handleSearch(event)
        case .detail: handleDetail(event)
        case .account: handleAccount(event)
        case .folderEdit: handleFolderEdit(event)
        case .stats: handleStats(event)
        }
    }

    private func handleLibrary(_ event: InputEvent) {
        if trailerMode {
            handleTrailer(event)
            return
        }
        if sgdbOpen {
            handleSGDB(event)
            return
        }
        if customizeGameID != nil {
            handleCustomize(event)
            return
        }
        if profileMenuOpen {
            handleProfileMenu(event)
            return
        }
        if shelfMenuOpen {
            handleShelfMenu(event)
            return
        }
        if libraryZone == .topBar {
            switch event {
            case .left: moveTopBar(by: -1)
            case .right: moveTopBar(by: 1)
            case .down, .back: exitTopBar()
            case .confirm: activateTopBar()
            case .toggleSearch: openSearch()
            case .sync: syncFromGFN()
            case .folderPrev: cycleFolder(by: -1)
            case .folderNext: cycleFolder(by: 1)
            case .info: editFocusedTopBarFolder()  // Square on a folder tab → edit it
            case .up, .remove: break
            }
            return
        }
        // Shelf: card body, or the Play / Info buttons beneath the focused card.
        switch shelfAction {
        case .none:
            switch event {
            case .left: moveFocus(by: -1)
            case .right: moveFocus(by: 1)
            case .up: enterTopBar()  // lift focus into the top bar (folders / sort / profile)
            case .down: focusShelfAction(.play)
            case .confirm: launchFocused()
            case .info: openDetail()  // Square / i → open the game page
            case .remove: removeFocused()
            case .toggleSearch: openSearch()
            case .sync: syncFromGFN()
            case .folderPrev: cycleFolder(by: -1)
            case .folderNext: cycleFolder(by: 1)
            case .back: break
            }
        case .play:
            switch event {
            case .right: focusShelfAction(.info)
            case .left: moveFocus(by: -1)  // resets shelfAction via focusedIndex
            case .up, .back: focusShelfAction(.none)
            case .down: break
            case .confirm: launchFocused()
            case .info: openDetail()
            case .remove: removeFocused()
            case .toggleSearch: openSearch()
            case .sync: syncFromGFN()
            case .folderPrev: cycleFolder(by: -1)
            case .folderNext: cycleFolder(by: 1)
            }
        case .info:
            switch event {
            case .left: focusShelfAction(.play)
            case .right: moveFocus(by: 1)  // resets shelfAction via focusedIndex
            case .up, .back: focusShelfAction(.none)
            case .down: break
            case .confirm: openShelfMenu()  // Cross on ⋯ → the per-game dropdown
            case .info: openDetail()
            case .remove: removeFocused()
            case .toggleSearch: openSearch()
            case .sync: syncFromGFN()
            case .folderPrev: cycleFolder(by: -1)
            case .folderNext: cycleFolder(by: 1)
            }
        }
    }

    private func focusShelfAction(_ action: ShelfAction) {
        guard shelfAction != action else { return }
        shelfAction = action
        Sound.tick()
    }

    // MARK: - Boot

    func finishBoot() {
        guard stage == .boot else { return }
        booted = true
        Sound.select()
        routeAfterBoot()
    }

    // MARK: - Top bar

    var topBarItems: [TopBarItem] {
        folderTabs.map { .folder($0.id) } + [.sort, .profile]
    }

    func enterTopBar() {
        let items = topBarItems
        guard !items.isEmpty else { return }
        topBarIndex = items.firstIndex(of: .folder(activeFolderID)) ?? 0
        shelfAction = .none
        libraryZone = .topBar
        Sound.tick()
    }

    func exitTopBar() {
        libraryZone = .shelf
        Sound.back()
    }

    private func moveTopBar(by delta: Int) {
        let items = topBarItems
        guard !items.isEmpty else { return }
        topBarIndex = min(max(0, topBarIndex + delta), items.count - 1)
        Sound.tick()
    }

    func activateTopBar() {
        let items = topBarItems
        guard items.indices.contains(topBarIndex) else { return }
        switch items[topBarIndex] {
        case .folder(let id):
            setActiveFolder(id)
            libraryZone = .shelf
        case .sort: cycleSort(by: 1)
        case .profile: openProfileMenu()
        }
    }

    // MARK: - Profile menu

    var profileMenuItems: [ProfileMenuItem] { ProfileMenuItem.allCases }

    func openProfileMenu() {
        profileMenuIndex = 0
        topBarIndex = max(0, topBarItems.count - 1)  // keep the chip lit while open + after close
        libraryZone = .topBar
        profileMenuOpen = true
        Sound.select()
    }

    func closeProfileMenu() {
        guard profileMenuOpen else { return }
        profileMenuOpen = false
        Sound.back()
    }

    private func handleProfileMenu(_ event: InputEvent) {
        switch event {
        case .up: moveProfileMenu(by: -1)
        case .down: moveProfileMenu(by: 1)
        case .confirm: activateProfileMenu()
        case .back, .left: closeProfileMenu()
        default: break
        }
    }

    // MARK: - Shelf ⋯ menu

    @Published var shelfMenuOpen = false
    @Published var shelfMenuIndex = 0
    var shelfMenuItems: [ShelfMenuItem] { ShelfMenuItem.allCases }

    func openShelfMenu() {
        guard focusedGame != nil else { return }
        shelfMenuIndex = 0
        shelfMenuOpen = true
        Sound.select()
    }

    func closeShelfMenu() {
        guard shelfMenuOpen else { return }
        shelfMenuOpen = false
        Sound.back()
    }

    private func handleShelfMenu(_ event: InputEvent) {
        switch event {
        case .up: moveShelfMenu(by: -1)
        case .down: moveShelfMenu(by: 1)
        case .confirm, .info: activateShelfMenu()
        case .back, .left: closeShelfMenu()
        default: break
        }
    }

    private func moveShelfMenu(by delta: Int) {
        let count = shelfMenuItems.count
        guard count > 0 else { return }
        shelfMenuIndex = min(max(0, shelfMenuIndex + delta), count - 1)
        Sound.tick()
    }

    func activateShelfMenu() {
        guard shelfMenuItems.indices.contains(shelfMenuIndex) else { return }
        selectShelfMenu(shelfMenuItems[shelfMenuIndex])
    }

    /// Run a ⋯-menu action and dismiss. Shared by the pointer and the stick.
    func selectShelfMenu(_ item: ShelfMenuItem) {
        shelfMenuOpen = false
        guard let game = focusedGame else { return }
        switch item {
        case .info: openDetail(game)
        case .customize: openCustomize(game)
        case .favorite: toggleFavorite(game)
        case .playTrailer: playTrailer()
        }
    }

    // MARK: - Favorites

    func isFavorite(_ game: Game) -> Bool {
        library.first { $0.id == game.id }?.favorite == true
    }

    /// Flip a game's favorite flag. Favorites pin to the front of every sort order.
    func toggleFavorite(_ game: Game) {
        guard let index = library.firstIndex(where: { $0.id == game.id }) else { return }
        let now = !(library[index].favorite == true)
        library[index].favorite = now
        sortLibrary(keepFocusOn: game.id)
        saveLibrary()
        Sound.tick()
        showToast(now ? "Added \(game.title) to Favorites" : "Removed \(game.title) from Favorites")
    }

    // MARK: - GFN-missing alert

    func dismissGFNAlert() {
        guard gfnAlertVisible else { return }
        gfnAlertVisible = false
        Sound.back()
    }

    private func moveProfileMenu(by delta: Int) {
        let count = profileMenuItems.count
        guard count > 0 else { return }
        profileMenuIndex = min(max(0, profileMenuIndex + delta), count - 1)
        Sound.tick()
    }

    func activateProfileMenu() {
        guard profileMenuItems.indices.contains(profileMenuIndex) else { return }
        selectProfileMenu(profileMenuItems[profileMenuIndex])
    }

    /// Run a menu action and dismiss the dropdown. Shared by the pointer and the stick.
    func selectProfileMenu(_ item: ProfileMenuItem) {
        profileMenuOpen = false
        switch item {
        case .surprise: surpriseMe()
        case .addGames: openSearch()
        case .sync: syncFromGFN()
        case .stats: openStats()
        case .account: toggleAccount()
        case .switchProfile: openProfileSwitcher()
        case .standby: enterStandby()
        case .quit: NSApp.terminate(nil)
        }
    }

    /// "Surprise Me" — jump the shelf to a random library game (avoiding the current one),
    /// so an undecided player gets picked for. Scrolls into view via the shelf's focus watcher.
    func surpriseMe() {
        let pool = visibleLibrary
        guard !pool.isEmpty else {
            showToast("Add some games first, then I'll pick one")
            Sound.back()
            return
        }
        libraryZone = .shelf
        shelfAction = .none
        let choices = pool.indices.filter { pool.count == 1 || $0 != focusedIndex }
        guard let pick = choices.randomElement() else { return }
        focusChangeFromPointer = false
        pointerFocusBlockedUntil = ProcessInfo.processInfo.systemUptime + 0.5
        focusedIndex = pick
        Sound.select()
        showToast("Surprise — \(pool[pick].title)")
    }

    /// 0…1 fill for the hold-Circle "trip home" hint, driven by InputRouter while Circle is held.
    @Published var backHoldProgress: Double = 0

    /// Whether holding Circle right now would actually snap the shelf home — gates the hint ring.
    var canJumpToShelfStart: Bool {
        stage == .ready && mode == .library && libraryZone == .shelf && !profileMenuOpen
            && customizeGameID == nil && !trailerMode
            && !visibleLibrary.isEmpty && focusedIndex != 0
    }

    /// Hold Circle anywhere on the shelf → glide focus back to the first game. The shelf's
    /// focus watcher animates the scroll, so it reads as a smooth trip home.
    func jumpToShelfStart() {
        guard canJumpToShelfStart else { return }
        shelfAction = .none
        focusChangeFromPointer = false
        pointerFocusBlockedUntil = ProcessInfo.processInfo.systemUptime + 0.5
        focusedIndex = 0
        Sound.select()
    }

    /// The real folder (not "All Games") the top bar is currently sitting on, if any — drives
    /// the "Edit folder" hint and the Square binding.
    var focusedTopBarFolderID: String? {
        guard libraryZone == .topBar else { return nil }
        let items = topBarItems
        guard items.indices.contains(topBarIndex), case .folder(let id?) = items[topBarIndex] else {
            return nil
        }
        return id
    }

    /// Square on a focused folder tab → open the folder-edit popup.
    private func editFocusedTopBarFolder() {
        guard let id = focusedTopBarFolderID else { return }
        openFolderEdit(id)
    }

    // MARK: - Folder-edit popup

    var folderBeingEdited: Folder? { folders.first { $0.id == folderEditID } }
    var folderEditControl: FolderEditControl {
        FolderEditControl(rawValue: folderEditIndex) ?? .name
    }

    func openFolderEdit(_ id: String) {
        profileMenuOpen = false
        folderEditID = id
        folderEditIndex = 0
        folderEditNameEditing = false
        mode = .folderEdit
        Sound.select()
    }

    func closeFolderEdit() {
        // Editing a name? First keystroke-set commits, then Back closes the popup.
        if folderEditNameEditing {
            commitFolderName()
            return
        }
        mode = .library
        libraryZone = .topBar
        folderEditID = nil
        Sound.back()
    }

    private func handleFolderEdit(_ event: InputEvent) {
        if folderEditNameEditing {
            if event == .back || event == .confirm { commitFolderName() }
            return
        }
        switch event {
        case .up: moveFolderEdit(by: -1)
        case .down: moveFolderEdit(by: 1)
        case .left: adjustFolderEdit(by: -1)
        case .right: adjustFolderEdit(by: 1)
        case .confirm: activateFolderEdit()
        case .remove: deleteCurrentFolder()
        case .back: closeFolderEdit()
        case .toggleSearch, .sync, .info, .folderPrev, .folderNext: break
        }
    }

    private func moveFolderEdit(by delta: Int) {
        let count = FolderEditControl.allCases.count
        folderEditIndex = min(max(0, folderEditIndex + delta), count - 1)
        Sound.tick()
    }

    private func adjustFolderEdit(by delta: Int) {
        if folderEditControl == .color, let id = folderEditID {
            cycleFolderColor(id: id, by: delta)
        }
    }

    private func activateFolderEdit() {
        guard let id = folderEditID else { return }
        switch folderEditControl {
        case .name:
            if controllerConnected {
                beginKeyboard(
                    .folderName(id), initial: folderBeingEdited?.name ?? "", title: "Folder name")
            } else {
                folderEditNameEditing = true
            }
        case .color: cycleFolderColor(id: id, by: 1)
        case .delete: deleteCurrentFolder()
        case .done: closeFolderEdit()
        }
    }

    func deleteCurrentFolder() {
        guard let id = folderEditID else { return }
        deleteFolder(id: id)
        mode = .library
        libraryZone = .topBar
        folderEditID = nil
        Sound.back()
    }

    func commitFolderName() {
        if let id = folderEditID {
            renameFolder(id: id, to: folderBeingEdited?.name ?? "")
        }
        folderEditNameEditing = false
        Sound.tick()
    }

    private func handleSearch(_ event: InputEvent) {
        switch event {
        case .left: moveSearchFocus(by: -1)
        case .right: moveSearchFocus(by: 1)
        case .up: moveSearchFocus(by: -searchColumns)
        case .down: moveSearchFocus(by: searchColumns)
        case .confirm: toggleFocusedSearchResult()
        case .back, .toggleSearch: closeSearch()
        case .info: beginKeyboard(.search, initial: searchQuery, title: "Search games")  // reopen the keyboard
        case .remove: toggleSearchScope()  // Triangle flips Catalog ↔ My Library
        case .sync, .folderPrev, .folderNext: break
        }
    }

    // MARK: - On-screen keyboard

    /// Static layout; letters render upper/lower per `keyboardShift`. Rows are ragged, so column
    /// focus clamps to each row's length as you move up and down.
    static let keyboardRows: [[KeyboardKey]] = [
        "1234567890".map { .char(String($0)) },
        "qwertyuiop".map { .char(String($0)) },
        "asdfghjkl".map { .char(String($0)) },
        [.shift] + "zxcvbnm".map { .char(String($0)) } + [.backspace],
        [.space, .done],
    ]

    /// Open the keyboard for a field. Controller-only path; hardware-keyboard users type natively.
    func beginKeyboard(_ target: KeyboardTarget, initial: String, title: String) {
        keyboardTarget = target
        keyboardText = initial
        keyboardTitle = title
        keyboardRow = 1
        keyboardCol = 0
        keyboardShift = initial.isEmpty && target != .search  // capitalize a fresh name
        keyboardActive = true
        Sound.select()
    }

    func endTextEntry(commit: Bool) {
        if commit, let target = keyboardTarget {
            switch target {
            case .search: searchQuery = keyboardText
            case .playerName: setPlayerName(keyboardText)
            case .folderName(let id): renameFolder(id: id, to: keyboardText)
            case .sgdbKey:
                sgdbKeyDraft = keyboardText
                saveSGDBKey()
            case .sgdbQuery:
                sgdbQuery = keyboardText
                runSGDBSearch()
            case .draftName:
                let trimmed = keyboardText.trimmingCharacters(in: .whitespaces)
                draftName = trimmed.isEmpty ? "Player" : trimmed
            }
        }
        keyboardActive = false
        keyboardTarget = nil
        Sound.tick()
    }

    private func handleKeyboard(_ event: InputEvent) {
        switch event {
        case .left: moveKeyboard(dRow: 0, dCol: -1)
        case .right: moveKeyboard(dRow: 0, dCol: 1)
        case .up: moveKeyboard(dRow: -1, dCol: 0)
        case .down: moveKeyboard(dRow: 1, dCol: 0)
        case .confirm: pressKeyboardKey()
        case .back: endTextEntry(commit: keyboardTarget == .search)  // search keeps what you typed
        case .remove, .info: keyboardBackspace()  // Triangle / Square = backspace
        case .toggleSearch, .sync: endTextEntry(commit: true)  // Menu = done
        case .folderPrev, .folderNext: break
        }
    }

    private func moveKeyboard(dRow: Int, dCol: Int) {
        let rows = Self.keyboardRows
        if dRow != 0 {
            keyboardRow = min(max(0, keyboardRow + dRow), rows.count - 1)
        }
        keyboardCol = min(max(0, keyboardCol + dCol), rows[keyboardRow].count - 1)
        Sound.tick()
    }

    /// Type the focused key. Public so the pointer can click keys too.
    func pressKeyboardKey(row: Int? = nil, col: Int? = nil) {
        let rows = Self.keyboardRows
        let r = row ?? keyboardRow
        let c = col ?? keyboardCol
        guard rows.indices.contains(r), rows[r].indices.contains(c) else { return }
        keyboardRow = r
        keyboardCol = c
        switch rows[r][c] {
        case .char(let ch):
            keyboardText.append(keyboardShift ? ch.uppercased() : ch)
            applyLiveText()
            Sound.tick()
        case .space:
            keyboardText.append(" ")
            applyLiveText()
            Sound.tick()
        case .backspace:
            keyboardBackspace()
        case .shift:
            keyboardShift.toggle()
            Sound.tick()
        case .done:
            endTextEntry(commit: true)
        }
    }

    func keyboardBackspace() {
        guard !keyboardText.isEmpty else { return }
        keyboardText.removeLast()
        applyLiveText()
        Sound.tick()
    }

    /// Search filters as you type; name fields only apply on Done.
    private func applyLiveText() {
        if keyboardTarget == .search { searchQuery = keyboardText }
    }

    private func handleDetail(_ event: InputEvent) {
        switch event {
        // Actions read as a list — up/down step it too, since the secondary buttons sit on
        // the row beneath Play and pressing Down there is the natural move.
        case .left, .up: moveDetailAction(by: -1)
        case .right, .down: moveDetailAction(by: 1)
        case .confirm: activateDetailAction()
        case .back: closeDetail()  // Circle / Esc → out
        case .remove: if let game = detailGame { remove(game) }
        case .info, .toggleSearch, .sync, .folderPrev, .folderNext: break
        }
    }

    private func handleAccount(_ event: InputEvent) {
        if accountEditing {
            if event == .back || event == .confirm { commitEditing() }
            return
        }
        switch event {
        case .up: moveAccount(by: -1)
        case .down: moveAccount(by: 1)
        case .left: adjustAccount(by: -1)
        case .right: adjustAccount(by: 1)
        case .confirm: activateAccount()
        case .remove: removeInAccount()
        case .back: closeAccount()
        case .toggleSearch, .sync, .info, .folderPrev, .folderNext: break
        }
    }

    // MARK: - Account navigation

    var accountItems: [AccountFocus] {
        var items: [AccountFocus] = [
            .name, .sort, .musicToggle, .volume, .openMusicFolder, .reloadMusic,
            .accent, .standby, .bootBehavior,
        ]
        items += folders.map { .folder($0.id) }
        items += [.newFolder, .switchProfile, .done]
        return items
    }

    var accountFocus: AccountFocus? {
        accountItems.indices.contains(accountIndex) ? accountItems[accountIndex] : nil
    }

    private func moveAccount(by delta: Int) {
        let count = accountItems.count
        guard count > 0 else { return }
        accountIndex = min(max(0, accountIndex + delta), count - 1)
        Sound.tick()
    }

    /// Left/right on the focused control: sort segment or volume. (Folder color moved to the popup.)
    private func adjustAccount(by delta: Int) {
        switch accountFocus {
        case .sort: cycleSort(by: delta)
        case .volume: setMusicVolume(min(max(0, musicVolume + Float(delta) * 0.05), 1))
        case .accent: cycleAccent(delta)
        case .standby: setStandbyMinutes(config.standbyMinutes + delta * 5)
        case .bootBehavior: setBootBehavior(config.bootBehavior == .select ? .auto : .select)
        default: break
        }
    }

    private func activateAccount() {
        switch accountFocus {
        case .name:
            if controllerConnected {
                beginKeyboard(.playerName, initial: playerName, title: "Your name")
            } else {
                beginEditing(folderID: nil)
            }
        case .sort: cycleSort(by: 1)
        case .musicToggle: setMusicEnabled(!musicEnabled)
        case .volume: break
        case .openMusicFolder: NSWorkspace.shared.open(MusicPlayer.musicDir)
        case .reloadMusic:
            MusicPlayer.shared.start()
            let n = MusicPlayer.shared.trackCount
            showToast(
                n == 0
                    ? "No tracks in music folder"
                    : n == 1
                        ? "1 track loaded"
                        : "\(n) tracks loaded — shuffling")
        case .accent: cycleAccent(1)
        case .standby: setStandbyMinutes(config.standbyMinutes + 5)
        case .bootBehavior: setBootBehavior(config.bootBehavior == .select ? .auto : .select)
        case .switchProfile: openProfileSwitcher()
        case .folder(let id): openFolderEdit(id)  // folder editing now lives in its own popup
        case .newFolder:
            let f = createFolder(named: "New Folder")
            openFolderEdit(f.id)
        case .done, .none: closeAccount()
        }
    }

    /// Triangle in the folder list jumps into that folder's edit popup (delete lives there now).
    private func removeInAccount() {
        if case .folder(let id) = accountFocus { openFolderEdit(id) }
    }

    func beginEditing(folderID: String?) {
        editingFolderID = folderID
        accountEditing = true
    }

    /// Live folder-name edit (no trimming/save until commit).
    func setFolderName(id: String, _ name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
    }

    func commitEditing() {
        if let id = editingFolderID, let i = folders.firstIndex(where: { $0.id == id }) {
            let trimmed = folders[i].name.trimmingCharacters(in: .whitespaces)
            folders[i].name = trimmed.isEmpty ? "Folder" : trimmed
            saveFolders()
        } else {
            setPlayerName(playerName)
        }
        accountEditing = false
        editingFolderID = nil
        Sound.tick()
    }

    /// Keyboard events arrive here before any field sees them. Returns true when consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        if standby {
            // Only Return / Enter / Space wakes standby; every other key is swallowed asleep.
            if [36, 76, 49].contains(Int(event.keyCode)) { wakeFromStandby() }
            return true
        }
        noteActivity()
        if !booted {
            finishBoot()
            return true
        }

        // GFN-missing overlay swallows everything; Esc / Return / Space dismiss it.
        if gfnAlertVisible {
            if [53, 36, 76, 49].contains(Int(event.keyCode)) { dismissGFNAlert() }
            return true
        }

        // On-screen keyboard is up: drive it with the hardware keyboard too (arrows move the
        // highlight, but typing lands directly), and swallow everything else.
        if keyboardActive {
            switch event.keyCode {
            case 123: handle(.left)
            case 124: handle(.right)
            case 125: handle(.down)
            case 126: handle(.up)
            case 36, 76: endTextEntry(commit: true)
            case 53: endTextEntry(commit: keyboardTarget == .search)
            case 51, 117: keyboardBackspace()
            default:
                if let typed = event.charactersIgnoringModifiers, typed.count == 1,
                    let scalar = typed.unicodeScalars.first, scalar.value >= 32, scalar.value != 127
                {
                    keyboardText.append(typed)
                    applyLiveText()
                }
            }
            return true
        }

        // Pre-library flow (onboarding / profile switcher) is stage-driven. Arrows/Return/Esc map
        // to events; printable keys fall through so a focused text field (the name) still types.
        if stage == .onboarding || stage == .profileSelect {
            switch event.keyCode {
            case 123:
                handle(.left)
                return true
            case 124:
                handle(.right)
                return true
            case 125:
                handle(.down)
                return true
            case 126:
                handle(.up)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 51, 117:
                handle(.remove)
                return true
            case 53:
                handle(.back)
                return true
            default: return false
            }
        }

        let cmd = event.modifierFlags.contains(.command)
        let chars = event.charactersIgnoringModifiers
        if cmd && chars == "f" {
            handle(.toggleSearch)
            return true
        }
        if cmd && chars == "l" {
            openLibrarySearch()
            return true
        }
        if cmd && chars == "s" {
            handle(.sync)
            return true
        }
        if cmd && chars == "," {
            toggleAccount()
            return true
        }

        switch mode {
        case .library:
            // SteamGridDB picker up: only Esc is intercepted (close); everything else falls
            // through so the search / API-key text fields can type freely. Pointer applies picks.
            if sgdbOpen {
                if event.keyCode == 53 {
                    handle(.back)
                    return true
                }
                return false
            }
            switch event.keyCode {
            case 123:
                handle(.left)
                return true
            case 124:
                handle(.right)
                return true
            case 125:
                handle(.down)
                return true
            case 126:
                handle(.up)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 51, 117:
                handle(.remove)
                return true
            case 53:
                handle(.back)
                return true  // Esc closes the profile dropdown
            case 115:
                jumpToShelfStart()
                return true  // Home → first game
            default:
                switch chars {
                case "/":
                    handle(.toggleSearch)
                    return true
                case "i":
                    handle(.info)
                    return true
                case "[":
                    handle(.folderPrev)
                    return true
                case "]":
                    handle(.folderNext)
                    return true
                case "1":
                    setSortMode(.recent)
                    return true
                case "2":
                    setSortMode(.mostPlayed)
                    return true
                case "3":
                    setSortMode(.alphabetical)
                    return true
                case "4":
                    setSortMode(.store)
                    return true
                case "m":
                    setMusicEnabled(!musicEnabled)
                    return true
                default: return false
                }
            }
        case .search:
            // Left/right stay with the text field so the caret still works.
            switch event.keyCode {
            case 53:
                handle(.back)
                return true
            case 125:
                handle(.down)
                return true
            case 126:
                handle(.up)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 48:
                toggleSearchScope()
                return true  // Tab flips Catalog ↔ My Library
            default: return false
            }
        case .detail:
            switch event.keyCode {
            case 123:
                handle(.left)
                return true
            case 124:
                handle(.right)
                return true
            case 53:
                handle(.back)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 51, 117:
                handle(.remove)
                return true
            default: return false
            }
        case .account:
            if accountEditing {
                // Let the text field type; only Esc / Return commit the edit.
                if [53, 36, 76].contains(Int(event.keyCode)) {
                    handle(.back)
                    return true
                }
                return false
            }
            switch event.keyCode {
            case 123:
                handle(.left)
                return true
            case 124:
                handle(.right)
                return true
            case 125:
                handle(.down)
                return true
            case 126:
                handle(.up)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 51, 117:
                handle(.remove)
                return true
            case 53:
                handle(.back)
                return true
            default: return false
            }
        case .folderEdit:
            if folderEditNameEditing {
                if [53, 36, 76].contains(Int(event.keyCode)) {
                    handle(.back)
                    return true
                }
                return false
            }
            switch event.keyCode {
            case 123:
                handle(.left)
                return true
            case 124:
                handle(.right)
                return true
            case 125:
                handle(.down)
                return true
            case 126:
                handle(.up)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 51, 117:
                handle(.remove)
                return true
            case 53:
                handle(.back)
                return true
            default: return false
            }
        case .stats:
            switch event.keyCode {
            case 123:
                handle(.left)
                return true  // previous time range
            case 124:
                handle(.right)
                return true  // next time range
            case 125:
                handle(.down)
                return true
            case 126:
                handle(.up)
                return true
            case 36, 76:
                handle(.confirm)
                return true
            case 53:
                handle(.back)
                return true
            default: return false
            }
        }
    }

    // MARK: - Focus movement

    private func moveFocus(by delta: Int) {
        focusChangeFromPointer = false
        pointerFocusBlockedUntil = ProcessInfo.processInfo.systemUptime + 0.4
        let visible = visibleLibrary
        guard !visible.isEmpty else { return }
        let target = focusedIndex + delta
        guard target >= 0, target < visible.count else {
            if delta > 1, focusedIndex < visible.count - 1 {
                focusedIndex = visible.count - 1
            }
            return
        }
        focusedIndex = target
        Sound.tick()
    }

    private func moveSearchFocus(by delta: Int) {
        focusChangeFromPointer = false
        pointerFocusBlockedUntil = ProcessInfo.processInfo.systemUptime + 0.4
        guard !searchResults.isEmpty else { return }
        let target = searchFocusedIndex + delta
        guard target >= 0, target < searchResults.count else {
            if delta > 1, searchFocusedIndex < searchResults.count - 1 {
                searchFocusedIndex = searchResults.count - 1
            }
            return
        }
        searchFocusedIndex = target
        Sound.tick()
    }

    /// The library games actually on the shelf: the active folder's members, or everything.
    /// `library` is kept sorted, so the filtered slice preserves the chosen order.
    var visibleLibrary: [Game] {
        guard let id = activeFolderID,
            let folder = folders.first(where: { $0.id == id })
        else { return library }
        let members = Set(folder.gameIDs)
        return library.filter { members.contains($0.id) }
    }

    var focusedGame: Game? {
        let visible = visibleLibrary
        return visible.indices.contains(focusedIndex) ? visible[focusedIndex] : nil
    }

    private func prefetchAroundFocus() {
        let items: [Game]
        let index: Int
        if mode == .search {
            items = searchResults
            index = searchFocusedIndex
        } else {
            items = visibleLibrary
            index = focusedIndex
        }
        guard !items.isEmpty else { return }
        let lo = max(0, index - Self.prefetchRadius)
        let hi = min(items.count - 1, index + Self.prefetchRadius)
        ImageCache.shared.prefetch(Array(items[lo...hi]))
        // Warm only the immediate neighbours' hero art. A wider radius floods the decoder on
        // fast stepping — the ambient fetch is debounced anyway, so it only needs ±1 warm.
        let hlo = max(0, index - 1)
        let hhi = min(items.count - 1, index + 1)
        ImageCache.shared.prefetchHeroes(Array(items[hlo...hhi]))
    }

    /// Move focus to a game id within the current shelf, clamping if it's gone.
    private func refocus(on id: Int?) {
        let visible = visibleLibrary
        if let id, let index = visible.firstIndex(where: { $0.id == id }) {
            focusedIndex = index
        }
        focusedIndex = min(focusedIndex, max(0, visible.count - 1))
    }

    // MARK: - Library actions

    func launchFocused() {
        guard let game = focusedGame else { return }
        launch(game)
    }

    /// R2 pull-to-launch (DualSense adaptive trigger). Only fires from the shelf.
    func launchFromTrigger() {
        guard booted, stage == .ready, !standby, mode == .library, !profileMenuOpen,
            !keyboardActive,
            libraryZone == .shelf
        else { return }
        launchFocused()
    }

    func launch(_ game: Game) {
        guard let url = game.launchURL else { return }
        // Nothing registered for geforcenow:// → the GFN app isn't there to take the deep link.
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            gfnAlertVisible = true
            Sound.back()
            return
        }
        if let index = library.firstIndex(where: { $0.id == game.id }) {
            library[index].lastPlayed = Date()
            sortLibrary(keepFocusOn: game.id)
            saveLibrary()
        }
        Sound.launch()
        // Mute all app audio immediately; it stays muted until the user moves to another item.
        gameAudioMuted = true
        MusicPlayer.shared.muteForGameLaunch()
        showToast("Launching \(game.title)")

        // Pop the Play button, then hand off to GFN a beat later so the animation reads before the
        // GFN window grabs focus and covers Nimbus. `launchingGame` drives CardPlayButton's flash.
        beginPlaySession(game)
        launchFXTask?.cancel()
        launchingGame = game
        triggerPull = 0
        launchFXTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            NSWorkspace.shared.open(url)
            try? await Task.sleep(for: .milliseconds(300))
            launchingGame = nil
        }
    }

    func removeFocused() {
        guard let game = focusedGame else { return }
        remove(game)
    }

    func remove(_ game: Game) {
        library.removeAll { $0.id == game.id }
        libraryIDs.remove(game.id)
        for i in folders.indices { folders[i].gameIDs.removeAll { $0 == game.id } }
        saveFolders()
        refocus(on: nil)
        saveLibrary()
        Sound.back()
        showToast("Removed \(game.title)")
    }

    func add(_ game: Game) {
        guard !libraryIDs.contains(game.id) else { return }
        var copy = game
        copy.lastPlayed = nil
        library.append(copy)
        libraryIDs.insert(game.id)
        sortLibrary(keepFocusOn: focusedGame?.id)
        saveLibrary()
        Sound.select()
        showToast("Added \(game.title)")
    }

    func isInLibrary(_ game: Game) -> Bool {
        libraryIDs.contains(game.id)
    }

    func focusGame(id: Int) {
        guard ProcessInfo.processInfo.systemUptime >= pointerFocusBlockedUntil else { return }
        if let index = visibleLibrary.firstIndex(where: { $0.id == id }), index != focusedIndex {
            focusChangeFromPointer = true
            focusedIndex = index
        }
    }

    // MARK: - Detail page

    func openDetail(_ game: Game? = nil) {
        guard let game = game ?? focusedGame else { return }
        profileMenuOpen = false
        detailGame = game
        detailActionIndex = 0
        mode = .detail
        Sound.select()
    }

    func closeDetail() {
        mode = .library
        libraryZone = .shelf
        shelfAction = .none
        Sound.back()
    }

    var detailActions: [DetailAction] {
        var actions: [DetailAction] = [.play, .toggleLibrary]
        if let game = detailGame, isInLibrary(game) { actions.append(.toggleFavorite) }
        actions += folders.map { .toggleFolder($0.id) }
        actions.append(.newFolder)
        return actions
    }

    private func moveDetailAction(by delta: Int) {
        let count = detailActions.count
        guard count > 0 else { return }
        detailActionIndex = min(max(0, detailActionIndex + delta), count - 1)
        Sound.tick()
    }

    func activateDetailAction() {
        guard let game = detailGame else { return }
        let actions = detailActions
        guard actions.indices.contains(detailActionIndex) else { return }
        switch actions[detailActionIndex] {
        case .play:
            launch(game)
        case .toggleLibrary:
            if isInLibrary(game) { remove(game) } else { add(game) }
        case .toggleFavorite:
            toggleFavorite(game)
        case .toggleFolder(let id):
            toggleFolderMembership(folderID: id, game: game)
        case .newFolder:
            let folder = createFolder(named: "New Folder", initialGame: game)
            detailActionIndex =
                detailActions.firstIndex(of: .toggleFolder(folder.id)) ?? detailActionIndex
            showToast("Added to a new folder — rename it in Account (⌘,)")
            Sound.select()
        }
    }

    // MARK: - Folders

    var folderTabs: [(id: String?, name: String)] {
        [(nil, "All Games")] + folders.map { ($0.id, $0.name) }
    }

    func setActiveFolder(_ id: String?) {
        guard id != activeFolderID else { return }
        let keep = focusedGame?.id
        activeFolderID = id
        refocus(on: keep)
        saveSettings()
        Sound.tick()
    }

    func cycleFolder(by delta: Int) {
        let tabs = folderTabs.map(\.id)
        guard tabs.count > 1, let current = tabs.firstIndex(where: { $0 == activeFolderID }) else {
            return
        }
        let next = (current + delta + tabs.count) % tabs.count
        setActiveFolder(tabs[next])
    }

    @discardableResult
    func createFolder(named name: String, initialGame: Game? = nil) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var folder = Folder(name: trimmed.isEmpty ? "New Folder" : trimmed)
        if let game = initialGame { folder.gameIDs = [game.id] }
        folders.append(folder)
        saveFolders()
        return folder
    }

    func renameFolder(id: String, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        folders[i].name = trimmed.isEmpty ? folders[i].name : trimmed
        saveFolders()
    }

    func cycleFolderColor(id: String, by delta: Int) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].colorIndex = (folders[i].colorIndex ?? 0) + delta
        saveFolders()
        Sound.tick()
    }

    /// Set a folder's color directly (swatch click in the edit popup).
    func setFolderColor(id: String, index: Int) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].colorIndex = index
        saveFolders()
        Sound.tick()
    }

    func deleteFolder(id: String) {
        folders.removeAll { $0.id == id }
        if activeFolderID == id {
            activeFolderID = nil
            saveSettings()
        }
        saveFolders()
        refocus(on: focusedGame?.id)
    }

    func toggleFolderMembership(folderID: String, game: Game) {
        guard let i = folders.firstIndex(where: { $0.id == folderID }) else { return }
        if let j = folders[i].gameIDs.firstIndex(of: game.id) {
            folders[i].gameIDs.remove(at: j)
        } else {
            folders[i].gameIDs.append(game.id)
            if !libraryIDs.contains(game.id) { add(game) }  // a folder only holds library games
        }
        saveFolders()
        Sound.tick()
    }

    func isInFolder(_ folderID: String, game: Game) -> Bool {
        folders.first(where: { $0.id == folderID })?.gameIDs.contains(game.id) ?? false
    }

    // MARK: - Search

    func openSearch() {
        profileMenuOpen = false
        searchQuery = ""
        searchFocusedIndex = 0
        updateSearchResults()
        mode = .search
        if catalog.isEmpty {
            Task { await loadCatalog() }
        }
        if controllerConnected { beginKeyboard(.search, initial: "", title: "Search games") }
    }

    func closeSearch() {
        mode = .library
        libraryZone = .shelf
        shelfAction = .none
        refocus(on: focusedGame?.id)
        Sound.back()
    }

    /// Open the search overlay pre-scoped to the user's own library — L2 on the pad, ⌘L on
    /// the keyboard.
    func openLibrarySearch() {
        searchScope = .library
        openSearch()
    }

    /// L2 pull from the pad. Same gating as R2's launch: only from the settled shelf.
    func openLibrarySearchFromTrigger() {
        guard booted, stage == .ready, !standby, mode == .library, !profileMenuOpen,
            !keyboardActive,
            !trailerMode, customizeGameID == nil, !sgdbOpen, !gfnAlertVisible
        else { return }
        openLibrarySearch()
    }

    func toggleFocusedSearchResult() {
        guard searchResults.indices.contains(searchFocusedIndex) else { return }
        let game = searchResults[searchFocusedIndex]
        if searchScope == .library {
            jumpToLibraryGame(game)
            return
        }
        if isInLibrary(game) {
            remove(game)
        } else {
            add(game)
        }
    }

    /// Flip the search pool between the GFN catalog and the user's own library.
    func toggleSearchScope() {
        searchScope = searchScope == .catalog ? .library : .catalog
        updateSearchResults()
        Sound.tick()
    }

    /// Library-scope search pick: close the overlay and land the shelf on that game.
    func jumpToLibraryGame(_ game: Game) {
        keyboardActive = false
        keyboardTarget = nil
        if !visibleLibrary.contains(where: { $0.id == game.id }) {
            // Outside the active folder — fall back to All Games so it can take focus.
            activeFolderID = nil
            saveSettings()
        }
        mode = .library
        libraryZone = .shelf
        shelfAction = .none
        refocus(on: game.id)
        Sound.select()
    }

    func focusSearchResult(id: Int) {
        guard ProcessInfo.processInfo.systemUptime >= pointerFocusBlockedUntil else { return }
        if let index = searchResults.firstIndex(where: { $0.id == id }), index != searchFocusedIndex
        {
            focusChangeFromPointer = true
            searchFocusedIndex = index
        }
    }

    private func updateSearchResults() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let source = searchScope == .library ? library : catalog
        if query.isEmpty {
            searchResults = source
        } else {
            let q = GFNLocal.normalize(query)
            var scored: [(game: Game, rank: Int)] = []
            for game in source {
                if let rank = Self.matchScore(game.title, query: q) {
                    scored.append((game, rank))
                }
            }
            scored.sort { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.game.title.localizedCaseInsensitiveCompare(b.game.title)
                    == .orderedAscending
            }
            searchResults = scored.map { $0.game }
        }
        searchFocusedIndex = 0
    }

    /// Relevance of a title to an already-normalized query. `nil` means no match (dropped).
    /// Lower ranks first: exact (0) < title-prefix (1) < word-prefix (2) < substring (3), then
    /// alphabetical within a tier. Both sides run through `GFNLocal.normalize`, so case,
    /// punctuation, and accents don't matter ("counter-strike" == "Counter-Strike").
    private static func matchScore(_ title: String, query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let t = GFNLocal.normalize(title)
        if t == query { return 0 }
        if t.hasPrefix(query) { return 1 }
        if t.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 2 }
        if t.contains(query) { return 3 }
        return nil
    }

    // MARK: - Account / settings

    func toggleAccount() {
        if mode == .account {
            closeAccount()
            return
        }
        profileMenuOpen = false
        accountIndex = 0
        accountEditing = false
        editingFolderID = nil
        mode = .account
        Sound.select()
    }

    func closeAccount() {
        mode = .library
        libraryZone = .shelf
        shelfAction = .none
        Sound.back()
    }

    func setSortMode(_ mode: SortMode) {
        guard mode != sortMode else { return }
        sortMode = mode
        sortLibrary(keepFocusOn: focusedGame?.id)
        saveSettings()
        Sound.tick()
        showToast("Sorted by \(mode.label)")
    }

    func cycleSort(by delta: Int) {
        let all = SortMode.allCases
        guard let i = all.firstIndex(of: sortMode) else { return }
        setSortMode(all[(i + delta + all.count) % all.count])
    }

    func setPlayerName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        playerName = trimmed.isEmpty ? "Player" : trimmed
        // The name lives on the profile now — persist it there.
        if let i = config.profiles.firstIndex(where: { $0.id == activeProfileID }) {
            config.profiles[i].name = playerName
            saveConfig()
        }
    }

    func setMusicEnabled(_ enabled: Bool) {
        musicEnabled = enabled
        MusicPlayer.shared.setEnabled(enabled)
        saveSettings()
        showToast(enabled ? "Music on" : "Music off")
    }

    func setMusicVolume(_ volume: Float) {
        musicVolume = volume
        MusicPlayer.shared.setVolume(volume)
        saveSettings()
    }

    /// Count of library games per store, for the account page breakdown.
    var storeBreakdown: [(store: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in library {
            let key = (game.store?.isEmpty == false ? game.store! : "Other")
            counts[key, default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (store: $0.key, count: $0.value) }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    // MARK: - Persistence

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: libraryFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let games = try? decoder.decode([Game].self, from: data) {
            library = games
            libraryIDs = Set(games.map(\.id))
            sortLibrary(keepFocusOn: nil)
        }
    }

    private func saveLibrary() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(library) {
            try? data.write(to: libraryFile, options: .atomic)
        }
    }

    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersFile),
            let saved = try? JSONDecoder().decode([Folder].self, from: data)
        else { return }
        folders = saved
    }

    private func saveFolders() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(folders) {
            try? data.write(to: foldersFile, options: .atomic)
        }
    }

    private struct Settings: Codable {
        var sortMode: SortMode = .recent
        var musicEnabled: Bool = true
        var musicVolume: Float = 0.5
        var activeFolderID: String?
        /// GFN library titles (normalized) the auto-sync has already considered, so a game the
        /// user deliberately removed isn't quietly re-added at every boot.
        var gfnSeenTitles: [String]?
    }

    /// See `Settings.gfnSeenTitles`.
    private var gfnSeenTitles: Set<String> = []

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsFile),
            let saved = try? JSONDecoder().decode(Settings.self, from: data)
        else { return }
        sortMode = saved.sortMode
        musicEnabled = saved.musicEnabled
        musicVolume = saved.musicVolume
        activeFolderID = saved.activeFolderID
        gfnSeenTitles = Set(saved.gfnSeenTitles ?? [])
    }

    private func saveSettings() {
        let settings = Settings(
            sortMode: sortMode,
            musicEnabled: musicEnabled,
            musicVolume: musicVolume,
            activeFolderID: activeFolderID,
            gfnSeenTitles: gfnSeenTitles.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsFile, options: .atomic)
        }
    }

    private func sortLibrary(keepFocusOn id: Int?) {
        let base: (Game, Game) -> Bool
        switch sortMode {
        case .recent:
            base = Self.recentBefore
        case .mostPlayed:
            base = { a, b in
                let pa = a.playSeconds ?? 0
                let pb = b.playSeconds ?? 0
                if pa != pb { return pa > pb }
                return Self.recentBefore(a, b)  // unplayed fall back to recent/alphabetical
            }
        case .alphabetical:
            base = { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .store:
            base = { a, b in
                let sa = a.store ?? ""
                let sb = b.store ?? ""
                if sa.caseInsensitiveCompare(sb) != .orderedSame {
                    return sa.localizedCaseInsensitiveCompare(sb) == .orderedAscending
                }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        // Favorites pin to the front of whatever order is active.
        library.sort { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            return base(a, b)
        }
        refocus(on: id)
    }

    /// Most-recently-played first; unplayed games trail, alphabetically.
    private static func recentBefore(_ a: Game, _ b: Game) -> Bool {
        switch (a.lastPlayed, b.lastPlayed) {
        case (let x?, let y?): return x > y
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none):
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    // MARK: - Catalog

    private func loadCatalog() async {
        if !catalog.isEmpty { return }

        // Fresh-enough disk cache wins; otherwise hit the network and fall back to any cache we have.
        if let cached = readCatalogCache(maxAge: Self.catalogMaxAge) {
            applyCatalog(await mergeWithGFNData(cached))
            return
        }

        catalogLoading = true
        defer { catalogLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.catalogURL)
            let games = try JSONDecoder().decode([Game].self, from: data)
            try? data.write(to: catalogFile, options: .atomic)
            applyCatalog(await mergeWithGFNData(games))
            catalogError = nil
        } catch {
            if let stale = readCatalogCache(maxAge: nil) {
                applyCatalog(await mergeWithGFNData(stale))
            } else {
                let extras = await mergeWithGFNData([])
                if extras.isEmpty {
                    catalogError =
                        "Couldn't load the GeForce NOW catalog. Check your connection and reopen search."
                } else {
                    applyCatalog(extras)
                }
            }
        }
    }

    /// NVIDIA's static list is years stale (no Crimson Desert, CS2, Hogwarts Legacy…).
    /// Supplement it with games recovered from the local GFN client cache, and remember
    /// those extras on disk. The cache scan reads tens of MB, so it runs off the main actor.
    private func mergeWithGFNData(_ base: [Game]) async -> [Game] {
        let extrasFile = self.extrasFile
        return await Task.detached(priority: .userInitiated) {
            var known = Set(base.map(\.id))
            var knownTitles = Set(base.map { GFNLocal.normalize($0.title) })
            var merged = base

            var extras: [Game] = []
            if let data = try? Data(contentsOf: extrasFile),
                let saved = try? JSONDecoder().decode([Game].self, from: data)
            {
                extras = saved
            }
            let savedIDs = Set(extras.map(\.id))
            extras.append(contentsOf: GFNLocal.cachedGames().filter { !savedIDs.contains($0.id) })

            for game in extras
            where !known.contains(game.id) && !knownTitles.contains(GFNLocal.normalize(game.title))
            {
                known.insert(game.id)
                knownTitles.insert(GFNLocal.normalize(game.title))
                merged.append(game)
            }

            if let data = try? JSONEncoder().encode(extras) {
                try? data.write(to: extrasFile, options: .atomic)
            }
            return merged
        }.value
    }

    // MARK: - GFN library sync

    /// Import the user's actual GeForce NOW library, read from the GFN client's local
    /// logs, matching titles against the merged catalog for launchable cmsIds.
    func syncFromGFN() { syncFromGFN(quiet: false) }

    /// `quiet` is the automatic boot-time pass: silent unless it actually adds something, and it
    /// only considers titles never seen before — so a game the user deliberately removed stays
    /// removed until they run a manual sync.
    func syncFromGFN(quiet: Bool) {
        guard GFNLocal.isInstalled else {
            if !quiet { showToast("GeForce NOW isn't installed") }
            return
        }
        guard !catalog.isEmpty else {
            if !quiet { showToast("Catalog still loading — try again in a moment") }
            return
        }

        guard !gfnSyncing else { return }
        gfnSyncing = true
        Task { [quiet] in
            let titles = await Task.detached(priority: .userInitiated) { GFNLocal.libraryTitles() }
                .value
            gfnSyncing = false
            applyGFNSync(titles: titles, quiet: quiet)
        }
    }

    private var gfnSyncing = false

    private func applyGFNSync(titles: [String], quiet: Bool) {
        guard !titles.isEmpty else {
            if !quiet { showToast("No library found, open GeForce NOW once, then sync again") }
            return
        }

        let normalizedAll = Set(titles.map { GFNLocal.normalize($0) })
        var candidates = titles
        if quiet {
            // First quiet pass over an existing library: assume it was synced by hand before.
            // Mark everything as seen without adding, so earlier removals stand.
            if gfnSeenTitles.isEmpty && !library.isEmpty {
                gfnSeenTitles = normalizedAll
                saveSettings()
                return
            }
            candidates = titles.filter { !gfnSeenTitles.contains(GFNLocal.normalize($0)) }
        }

        var byTitle: [String: Game] = [:]
        for game in catalog {
            byTitle[GFNLocal.normalize(game.title)] =
                byTitle[GFNLocal.normalize(game.title)] ?? game
        }

        var added = 0
        var unresolved: [String] = []
        for title in candidates {
            guard let game = byTitle[GFNLocal.normalize(title)] else {
                unresolved.append(title)
                continue
            }
            if !libraryIDs.contains(game.id) {
                var copy = game
                copy.lastPlayed = nil
                library.append(copy)
                libraryIDs.insert(game.id)
                added += 1
            }
        }
        if added > 0 {
            sortLibrary(keepFocusOn: focusedGame?.id)
            saveLibrary()
        }
        if gfnSeenTitles != gfnSeenTitles.union(normalizedAll) {
            gfnSeenTitles.formUnion(normalizedAll)
            saveSettings()
        }

        if quiet {
            if added > 0 {
                showToast(
                    "Synced — added \(added) new game\(added == 1 ? "" : "s") from GeForce NOW")
            }
            return
        }
        switch (added, unresolved.count) {
        case (0, 0): showToast("Library already in sync")
        case (_, 0): showToast("Added \(added) games from GeForce NOW")
        case (0, _): showToast("Nothing new — \(unresolved.count) titles couldn't be matched")
        default: showToast("Added \(added) games (\(unresolved.count) couldn't be matched)")
        }
    }

    private func readCatalogCache(maxAge: TimeInterval?) -> [Game]? {
        guard let data = try? Data(contentsOf: catalogFile) else { return nil }
        if let maxAge {
            let attrs = try? FileManager.default.attributesOfItem(atPath: catalogFile.path)
            guard let modified = attrs?[.modificationDate] as? Date,
                Date().timeIntervalSince(modified) < maxAge
            else { return nil }
        }
        return try? JSONDecoder().decode([Game].self, from: data)
    }

    private func applyCatalog(_ games: [Game]) {
        var seen = Set<Int>()
        catalog =
            games
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if mode == .search {
            updateSearchResults()
        }
    }

    // MARK: - Global config

    private func loadConfig() {
        guard let data = try? Data(contentsOf: configFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode(AppConfig.self, from: data) { config = saved }
    }

    func saveConfig() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? FileManager.default.createDirectory(
                at: Self.supportDir, withIntermediateDirectories: true)
            try? data.write(to: configFile, options: .atomic)
        }
    }

    /// Fold a pre-profiles install (a bare `library.json` at the support root) into a first
    /// profile, so an updating user keeps their library and boots straight into it as before.
    private func migrateLegacyIfNeeded() {
        guard config.profiles.isEmpty else { return }
        let root = Self.supportDir
        let legacyLibrary = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: legacyLibrary.path) else { return }

        var name = "Player"
        let legacySettings = root.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: legacySettings),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let saved = obj["playerName"] as? String,
            !saved.trimmingCharacters(in: .whitespaces).isEmpty
        {
            name = saved
        }

        let profile = Profile(name: name)
        let dir = profilesDir.appendingPathComponent(profile.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in ["library.json", "folders.json", "settings.json"] {
            let src = root.appendingPathComponent(file)
            let dst = dir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.moveItem(at: src, to: dst)
            }
        }
        config.profiles = [profile]
        config.lastProfileID = profile.id
        config.onboardingComplete = true  // don't drag an existing user through onboarding
        config.bootBehavior = .select  // but do show them the new switcher once
        saveConfig()
    }

    // MARK: - Boot routing

    private func routeAfterBoot() {
        if !config.onboardingComplete || config.profiles.isEmpty {
            startOnboarding(add: false)
        } else if config.bootBehavior == .auto,
            let last = config.lastProfileID,
            config.profiles.contains(where: { $0.id == last })
        {
            activateProfile(last)
            enterReady()
        } else {
            prepareProfileSelect()
            stage = .profileSelect
        }
    }

    /// Load a profile's world (library / folders / settings / history / look) into the model.
    func activateProfile(_ id: String) {
        guard config.profiles.contains(where: { $0.id == id }) else { return }
        endPlaySession()  // bank anything in flight before swapping libraries out

        activeProfileID = id
        config.lastProfileID = id
        saveConfig()
        if let p = activeProfile {
            playerName = p.name
            AccentPalette.currentIndex = p.accentIndex
            AccentPalette.current = AccentPalette.color(p.accentIndex)
        }
        try? FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        // Clear the previous profile's state so a missing file can't leak stale data across.
        library = []
        libraryIDs = []
        folders = []
        history = []
        sortMode = .recent
        musicEnabled = true
        musicVolume = 0.5
        activeFolderID = nil
        gfnSeenTitles = []
        focusedIndex = 0
        libraryZone = .shelf
        shelfAction = .none

        loadSettings()
        loadFolders()
        loadLibrary()
        loadHistory()

        MusicPlayer.shared.setEnabled(musicEnabled)
        MusicPlayer.shared.setVolume(musicVolume)
        prefetchAroundFocus()
    }

    func enterReady() {
        stage = .ready
        mode = .library
        libraryZone = .shelf
        standby = false
        lastActivity = Date()
        Task { syncFromGFN(quiet: true) }
    }

    // MARK: - Profiles

    @discardableResult
    func createProfile(name: String, colorIndex: Int, accentIndex: Int) -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let profile = Profile(
            name: trimmed.isEmpty ? "Player" : trimmed,
            colorIndex: colorIndex, accentIndex: accentIndex)
        config.profiles.append(profile)
        saveConfig()
        try? FileManager.default.createDirectory(
            at: profilesDir.appendingPathComponent(profile.id, isDirectory: true),
            withIntermediateDirectories: true)
        return profile
    }

    func deleteProfile(_ id: String) {
        guard config.profiles.count > 1 else {
            showToast("Can't delete your only profile")
            return
        }
        let wasActive = activeProfileID == id
        config.profiles.removeAll { $0.id == id }
        if config.lastProfileID == id { config.lastProfileID = config.profiles.first?.id }
        saveConfig()
        try? FileManager.default.removeItem(
            at: profilesDir.appendingPathComponent(id, isDirectory: true))
        if wasActive, let next = config.profiles.first?.id { activateProfile(next) }
        Sound.back()
    }

    func setAccentIndex(_ index: Int) {
        guard let i = config.profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        let n = AccentPalette.options.count
        let clamped = ((index % n) + n) % n
        config.profiles[i].accentIndex = clamped
        AccentPalette.currentIndex = clamped
        AccentPalette.current = AccentPalette.color(clamped)
        saveConfig()
        Sound.tick()
    }

    func cycleAccent(_ delta: Int) { setAccentIndex(accentIndex + delta) }

    func setProfileColor(_ index: Int) {
        guard let i = config.profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        let n = AvatarPalette.count
        config.profiles[i].colorIndex = ((index % n) + n) % n
        saveConfig()
        Sound.tick()
    }

    func setBootBehavior(_ behavior: BootBehavior) {
        config.bootBehavior = behavior
        saveConfig()
        Sound.tick()
    }

    func setStandbyMinutes(_ minutes: Int) {
        config.standbyMinutes = min(120, max(1, minutes))
        saveConfig()
        Sound.tick()
    }

    // MARK: - Profile switcher

    /// profiles + a trailing "Add profile" tile.
    var profileSelectCount: Int { config.profiles.count + 1 }

    func openProfileSwitcher() {
        profileMenuOpen = false
        MusicPlayer.shared.stopTheme()
        stopTrailer()
        prepareProfileSelect()
        stage = .profileSelect
        Sound.select()
    }

    private func prepareProfileSelect() {
        if let target = activeProfileID ?? config.lastProfileID,
            let i = config.profiles.firstIndex(where: { $0.id == target })
        {
            profileSelectIndex = i
        } else {
            profileSelectIndex = 0
        }
    }

    private func handleProfileSelect(_ event: InputEvent) {
        switch event {
        case .left: moveProfileSelect(-1)
        case .right: moveProfileSelect(1)
        case .up, .down: break
        case .confirm: commitProfileSelect()
        case .back:
            // Bail back into the running profile only if there's one to return to.
            if activeProfileID != nil, config.onboardingComplete { enterReady() }
        default: break
        }
    }

    private func moveProfileSelect(_ delta: Int) {
        let next = min(max(0, profileSelectIndex + delta), profileSelectCount - 1)
        guard next != profileSelectIndex else { return }
        profileSelectIndex = next
        Sound.tick()
    }

    func commitProfileSelect() {
        if profileSelectIndex < config.profiles.count {
            activateProfile(config.profiles[profileSelectIndex].id)
            enterReady()
        } else {
            startOnboarding(add: true)
        }
    }

    /// Pointer entry point for the switcher tiles.
    func selectProfile(at index: Int) {
        profileSelectIndex = max(0, min(profileSelectCount - 1, index))
        commitProfileSelect()
    }

    // MARK: - Onboarding

    private var onboardingDraftProfileID: String?

    func startOnboarding(add: Bool) {
        onboardingIsAdd = add
        onboardingSteps = add ? [.profile] : [.welcome, .profile, .geforce, .artKey, .finish]
        onboardingIndex = 0
        onboardingFocus = 0
        onboardingDraftProfileID = nil
        draftName = add ? "Player \(config.profiles.count + 1)" : "Player"
        draftColorIndex = config.profiles.count % AvatarPalette.count
        draftAccentIndex = 0
        stage = .onboarding
        Sound.select()
    }

    func onboardingControlCount(_ step: OnboardingStep) -> Int {
        switch step {
        case .welcome: return 1
        case .profile: return 4
        case .geforce: return 2
        case .artKey: return 3
        case .finish: return 1
        }
    }

    private func handleOnboarding(_ event: InputEvent) {
        guard let step = onboardingStep else { return }
        switch event {
        case .up: moveOnboardingFocus(-1, step: step)
        case .down: moveOnboardingFocus(1, step: step)
        case .left: onboardingHorizontal(-1, step: step)
        case .right: onboardingHorizontal(1, step: step)
        case .confirm: activateOnboardingControl(step)
        case .back: backOnboarding()
        default: break
        }
    }

    private func moveOnboardingFocus(_ delta: Int, step: OnboardingStep) {
        let n = onboardingControlCount(step)
        let next = min(max(0, onboardingFocus + delta), n - 1)
        guard next != onboardingFocus else { return }
        onboardingFocus = next
        Sound.tick()
    }

    private func onboardingHorizontal(_ delta: Int, step: OnboardingStep) {
        guard step == .profile else {
            moveOnboardingFocus(delta, step: step)
            return
        }
        switch onboardingFocus {
        case 1:
            let n = AvatarPalette.count
            draftColorIndex = ((draftColorIndex + delta) % n + n) % n
            Sound.tick()
        case 2:
            let n = AccentPalette.options.count
            draftAccentIndex = ((draftAccentIndex + delta) % n + n) % n
            AccentPalette.current = AccentPalette.color(draftAccentIndex)  // live preview
            Sound.tick()
        default:
            moveOnboardingFocus(delta, step: step)
        }
    }

    private func activateOnboardingControl(_ step: OnboardingStep) {
        switch step {
        case .welcome:
            advanceOnboarding()
        case .profile:
            switch onboardingFocus {
            case 0: beginKeyboard(.draftName, initial: draftName, title: "Your name")
            case 1: onboardingHorizontal(1, step: step)
            case 2: onboardingHorizontal(1, step: step)
            default: advanceOnboarding()
            }
        case .geforce:
            if onboardingFocus == 0 {
                ensureDraftProfileActivated()
                syncFromGFN(quiet: false)
            }
            advanceOnboarding()
        case .artKey:
            switch onboardingFocus {
            case 0: pasteSGDBKey()
            case 1:
                beginKeyboard(.sgdbKey, initial: SteamGridDB.apiKey, title: "SteamGridDB API key")
            default: advanceOnboarding()
            }
        case .finish:
            advanceOnboarding()
        }
    }

    /// Create (or update) and activate the profile the flow is building, so later steps —
    /// GFN sync, the art key — act on the real profile.
    private func ensureDraftProfileActivated() {
        let cleaned = draftName.trimmingCharacters(in: .whitespaces)
        let finalName = cleaned.isEmpty ? "Player" : cleaned
        if let id = onboardingDraftProfileID,
            let i = config.profiles.firstIndex(where: { $0.id == id })
        {
            config.profiles[i].name = finalName
            config.profiles[i].colorIndex = draftColorIndex
            config.profiles[i].accentIndex = draftAccentIndex
            saveConfig()
            activateProfile(id)
        } else {
            let profile = createProfile(
                name: finalName, colorIndex: draftColorIndex, accentIndex: draftAccentIndex)
            onboardingDraftProfileID = profile.id
            activateProfile(profile.id)
        }
    }

    /// Pointer entry point: focus a control and fire it (used by onboarding buttons/swatches).
    func onboardingActivate(_ focus: Int) {
        guard let step = onboardingStep else { return }
        onboardingFocus = focus
        activateOnboardingControl(step)
    }

    func advanceOnboarding() {
        guard let step = onboardingStep else { return }
        if step == .profile { ensureDraftProfileActivated() }
        if onboardingIndex + 1 < onboardingSteps.count {
            onboardingIndex += 1
            onboardingFocus = 0
            Sound.select()
        } else {
            finishOnboarding()
        }
    }

    func backOnboarding() {
        if onboardingIndex > 0 {
            onboardingIndex -= 1
            onboardingFocus = 0
            Sound.back()
        } else if onboardingIsAdd {
            prepareProfileSelect()
            stage = .profileSelect
            Sound.back()
        }
    }

    private func finishOnboarding() {
        if !onboardingIsAdd {
            config.onboardingComplete = true
            saveConfig()
        }
        if activeProfileID == nil { ensureDraftProfileActivated() }
        enterReady()
    }

    // MARK: - Stats dashboard

    /// Scroll anchors StatsView exposes to the controller (up/down step through them).
    var statsSectionCount: Int { 7 }

    func openStats() {
        profileMenuOpen = false
        statsFocusIndex = 0
        mode = .stats
        Sound.select()
        Task { await enrichLibraryForStats() }
    }

    func closeStats() {
        mode = .library
        libraryZone = .shelf
        shelfAction = .none
        Sound.back()
    }

    private func handleStats(_ event: InputEvent) {
        switch event {
        case .left, .folderPrev: cycleStatsRange(-1)
        case .right, .folderNext: cycleStatsRange(1)
        case .up: stepStatsFocus(-1)
        case .down: stepStatsFocus(1)
        case .back: closeStats()
        default: break
        }
    }

    func cycleStatsRange(_ delta: Int) {
        let all = StatsRange.allCases
        guard let i = all.firstIndex(of: statsRange) else { return }
        statsRange = all[(i + delta + all.count) % all.count]
        Sound.tick()
    }

    private func stepStatsFocus(_ delta: Int) {
        let next = max(0, min(statsSectionCount - 1, statsFocusIndex + delta))
        guard next != statsFocusIndex else { return }
        statsFocusIndex = next
        Sound.tick()
    }

    /// Warm Steam detail (Metacritic, review counts, release year) for the library in the
    /// background so the dashboard's quality stats fill in. Cached on disk, so it's cheap after
    /// the first pass; capped and bumps `enrichmentRevision` as data lands.
    func enrichLibraryForStats() async {
        let games = library.filter { $0.steamAppID != nil }.prefix(80)
        var done = 0
        for game in games {
            _ = await StoreInfo.shared.details(for: game)
            done += 1
            if done % 6 == 0 { enrichmentRevision += 1 }
        }
        enrichmentRevision += 1
    }

    // MARK: - Play history

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyFile) else {
            history = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        history = (try? decoder.decode([PlaySession].self, from: data)) ?? []
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(history) {
            try? FileManager.default.createDirectory(
                at: profileDir, withIntermediateDirectories: true)
            try? data.write(to: historyFile, options: .atomic)
        }
    }
}
