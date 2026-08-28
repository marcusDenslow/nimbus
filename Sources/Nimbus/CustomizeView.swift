import SwiftUI
import AppKit

/// Per-game customize window, design "2b — sidebar + live preview": category nav on the left
/// (Artwork / Background Video / Theme Music / Actions), a live art preview plus the focused
/// section's controls on the right, Done pinned bottom-right.
///
/// Controller model is unchanged: Up/Down step the sidebar sections, Cross/Square enters one,
/// Left/Right move between its controls (and ride the volume sliders), Circle backs out.
struct CustomizeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var previewArt = ViewState<NSImage?>(nil)
    /// The game's current title logo (custom pick or auto-fetched), shown over the preview
    /// while the Logo section is focused.
    @StateObject private var previewLogo = ViewState<NSImage?>(nil)

    static let accent = Color(red: 0.208, green: 0.839, blue: 0.910)   // #35d6e8
    private static let accentInk = Color(red: 0.016, green: 0.125, blue: 0.153) // #042027

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { model.closeCustomize() }

            if let game = model.customizeGame {
                card(game)
                    .frame(width: 940, height: 520)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .task(id: "\(game.id)-\(model.customizeRevision)") { await loadPreview(game) }
            }
        }
    }

    private func card(_ game: Game) -> some View {
        // Read revision so rows re-evaluate their has-asset state after each pick/clear.
        let _ = model.customizeRevision
        return HStack(spacing: 0) {
            sidebar(game)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            pane(game)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Color(red: 0.055, green: 0.067, blue: 0.09).opacity(0.78),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 50, y: 24)
    }

    // MARK: - Sidebar

    private func sidebar(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Text("CUSTOMIZE")
                    .font(.system(size: 12, weight: .bold)).tracking(3)
            }
            .foregroundStyle(Self.accent)
            .padding(.horizontal, 6)

            Text(game.title)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.top, 8)

            VStack(spacing: 6) {
                ForEach(CustomizeSection.allCases, id: \.self) { section in
                    sidebarRow(section, game: game)
                }
            }
            .padding(.top, 22)

            Spacer()

            if model.controllerConnected {
                Text(model.customizeEditing ? "←→ Adjust   ✕ Select   ○ Back" : "↕ Sections   ✕ Enter   ○ Close")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(width: 300)
    }

    private func sidebarRow(_ section: CustomizeSection, game: Game) -> some View {
        let focused = model.customizeSection == section
        return Button {
            model.customizeSection = section
            model.customizeEditing = true
            model.customizeControl = 0
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon(section))
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(focused ? Self.accent : .white.opacity(0.8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(section))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(focused ? Color(red: 0.92, green: 1, blue: 1) : .white)
                    Text(value(section, game: game))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: 0)
                if focused {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Self.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(focused ? Self.accent.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func icon(_ section: CustomizeSection) -> String {
        switch section {
        case .image: return "photo"
        case .logo: return "textformat"
        case .video: return "film"
        case .theme: return "music.note"
        case .actions: return "play.rectangle"
        }
    }

    private func label(_ section: CustomizeSection) -> String {
        switch section {
        case .image: return "Artwork"
        case .logo: return "Name Logo"
        case .video: return "Background Video"
        case .theme: return "Theme Music"
        case .actions: return "Actions"
        }
    }

    private func value(_ section: CustomizeSection, game: Game) -> String {
        switch section {
        case .image:
            let bg = CustomStore.imageURL(game.id) != nil
            let card = CustomStore.cardURL(game.id) != nil
            if bg && card { return "Custom BG + cover" }
            if bg { return "Custom background" }
            if card { return "Custom cover" }
            return "Default"
        case .logo:
            return CustomStore.logoURL(game.id) != nil ? "Custom" : "Automatic"
        case .video:
            guard CustomStore.videoURL(game.id) != nil else { return "None" }
            return CustomStore.isMuted(game.id) ? "Custom · muted"
                : "Custom · \(Int(CustomStore.videoVolume(game.id) * 100))%"
        case .theme:
            guard ThemeStore.hasTheme(gameID: game.id) else { return "None" }
            return "Custom · \(Int(ThemeStore.volume(gameID: game.id) * 100))%"
        case .actions:
            return "Trailer · Done"
        }
    }

    // MARK: - Right pane

    private func pane(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            preview

            Text(label(model.customizeSection))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.top, 22)
            Text(hint(model.customizeSection))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: 440, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            controls(game)
                .padding(.top, 20)

            Spacer(minLength: 12)

            HStack {
                Spacer()
                doneButton
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
    }

    /// Live art block: the game's custom background (or its hero art) under a scrim, tagged
    /// with the focused section's name.
    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.04, green: 0.055, blue: 0.078)
                .overlay {
                    if let art = previewArt.value {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)

            // Logo section focused → float the current logo over the art, sized like the
            // hero panel shows it, so a pick reads in context immediately.
            if model.customizeSection == .logo, let logoImage = previewLogo.value {
                Color.clear.overlay {
                    Image(nsImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 110)
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .bold)).tracking(2.6)
                    .foregroundStyle(Self.accent)
                Text(label(model.customizeSection))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 20)
            .padding(.bottom, 16)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
    }

    private func hint(_ section: CustomizeSection) -> String {
        switch section {
        case .image:
            return "The full-bleed art behind the game when it's focused, plus the shelf-card cover. Upload your own or pull official art from SteamGridDB."
        case .logo:
            return "The wordmark shown in place of the game's plain-text title. Fetched automatically from SteamGridDB — browse for a different one, or upload your own transparent image."
        case .video:
            return "A looping clip that plays behind the game instead of a still image, with its own audio and volume."
        case .theme:
            return "An ambient track that fades in while this game is highlighted, ducking the menu music."
        case .actions:
            return "Preview the trailer, or close this window."
        }
    }

    private func loadPreview(_ game: Game) async {
        if let url = CustomStore.imageURL(game.id), let custom = NSImage(contentsOf: url) {
            previewArt.value = custom
        } else {
            previewArt.value = await ImageCache.shared.hero(for: game)
        }
        previewLogo.value = await LogoCache.shared.displayLogo(for: game)
    }

    // MARK: - Section controls

    @ViewBuilder
    private func controls(_ game: Game) -> some View {
        switch model.customizeSection {
        case .image: imageControls(game)
        case .logo: logoControls(game)
        case .video: videoControls(game)
        case .theme: themeControls(game)
        case .actions: actionControls(game)
        }
    }

    private func logoControls(_ game: Game) -> some View {
        HStack(spacing: 10) {
            controlButton("Upload", "square.and.arrow.up", focused: isFocus(.logo, .set)) {
                model.pickCustomLogo(game)
            }
            controlButton("Browse", "magnifyingglass", style: .accent,
                          focused: isFocus(.logo, .sgdb)) {
                model.openSGDB(game, kind: .logo)
            }
            if CustomStore.logoURL(game.id) != nil {
                controlButton("Clear", "xmark", style: .destructive, focused: isFocus(.logo, .clear)) {
                    CustomStore.clearLogo(game.id); model.bumpCustomize()
                }
            }
        }
    }

    private func isFocus(_ section: CustomizeSection, _ control: CustomizeControl) -> Bool {
        model.customizeSection == section && model.focusedCustomizeControl == control
    }

    private func imageControls(_ game: Game) -> some View {
        HStack(spacing: 10) {
            controlButton("Upload", "square.and.arrow.up", focused: isFocus(.image, .set)) {
                model.pickCustomImage(game)
            }
            controlButton("Browse", "magnifyingglass", style: .accent,
                          focused: isFocus(.image, .sgdb)) {
                model.openSGDB(game)
            }
            if CustomStore.imageURL(game.id) != nil {
                controlButton("Clear BG", "xmark", style: .destructive, focused: isFocus(.image, .clear)) {
                    CustomStore.clearImage(game.id); model.bumpCustomize()
                }
            }
            if CustomStore.cardURL(game.id) != nil {
                controlButton("Clear cover", "xmark", style: .destructive, focused: isFocus(.image, .clearCard)) {
                    CustomStore.clearCard(game.id); model.bumpCustomize()
                }
            }
        }
    }

    private func videoControls(_ game: Game) -> some View {
        let has = CustomStore.videoURL(game.id) != nil
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                controlButton(has ? "Change" : "Choose file", "square.and.arrow.up",
                              focused: isFocus(.video, .set)) {
                    model.pickCustomVideo(game)
                }
                if has {
                    controlButton("Clear", "xmark", style: .destructive, focused: isFocus(.video, .clear)) {
                        CustomStore.clearVideo(game.id); model.bumpCustomize()
                    }
                }
            }
            if has {
                Toggle(isOn: Binding(
                    get: { !CustomStore.isMuted(game.id) },
                    set: { CustomStore.setMuted(game.id, !$0); model.bumpCustomize() }
                )) {
                    Text("Play audio").font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.switch)
                .tint(Self.accent)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white, lineWidth: isFocus(.video, .audio) ? 2 : 0).padding(-5))

                volumeSlider(
                    value: { Double(CustomStore.videoVolume(game.id)) },
                    set: { v in
                        CustomStore.setVideoVolume(game.id, Float(v))
                        model.bgVideoVolume = Float(v)
                    },
                    focused: isFocus(.video, .volume)
                )
            }
        }
    }

    private func themeControls(_ game: Game) -> some View {
        let has = ThemeStore.hasTheme(gameID: game.id)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                controlButton(has ? "Change" : "Choose file", "music.note",
                              focused: isFocus(.theme, .set)) {
                    model.pickCustomTheme(game)
                }
                if has {
                    controlButton("Clear", "xmark", style: .destructive, focused: isFocus(.theme, .clear)) {
                        if let old = ThemeStore.themeURL(gameID: game.id) {
                            try? FileManager.default.removeItem(at: old)
                        }
                        model.bumpCustomize()
                    }
                }
            }
            if has {
                volumeSlider(
                    value: { Double(ThemeStore.volume(gameID: game.id)) },
                    set: { v in
                        ThemeStore.setVolume(gameID: game.id, Float(v))
                        MusicPlayer.shared.setThemeVolume(Float(v))
                    },
                    focused: isFocus(.theme, .volume)
                )
            }
        }
    }

    private func actionControls(_ game: Game) -> some View {
        HStack(spacing: 12) {
            controlButton("Play Trailer", "play.rectangle.fill",
                          focused: isFocus(.actions, .playTrailer)) {
                model.closeCustomize()
                model.playTrailer()
            }
        }
    }

    /// "Volume · 60%" over a slider, ringed when it holds controller focus.
    private func volumeSlider(value: @escaping () -> Double, set: @escaping (Double) -> Void,
                              focused: Bool) -> some View {
        let _ = model.customizeRevision
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Volume")
                Spacer()
                Text("\(Int(value() * 100))%")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            Slider(value: Binding(get: value, set: { set($0); model.bumpCustomize() }), in: 0...1)
                .tint(Self.accent)
        }
        .frame(maxWidth: 420)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Self.accent, lineWidth: focused ? 2 : 0).padding(-8))
    }

    private enum ControlStyle { case plain, accent, destructive }

    /// One geometry for every control button — same height, radius, font, and neutral fill — so
    /// the row reads as a single family. Style only shifts the icon/label tint and a faint border,
    /// never the size. `lineLimit(1)` + `fixedSize` stop long labels from wrapping inside the pill.
    private func controlButton(_ title: String, _ symbol: String?, style: ControlStyle = .plain,
                               focused: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 13.5, weight: .semibold))
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tint(style))
            .frame(height: 44)
            .padding(.horizontal, 18)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(.white)
                              : AnyShapeStyle(tint(style).opacity(style == .plain ? 0.16 : 0.4)),
                              lineWidth: focused ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func tint(_ style: ControlStyle) -> Color {
        switch style {
        case .plain: return .white
        case .accent: return Self.accent                                 // #35d6e8
        case .destructive: return Color(red: 1, green: 0.55, blue: 0.55) // #ff8c8c
        }
    }

    private var doneButton: some View {
        let focused = model.customizeSection == .actions && model.focusedCustomizeControl == .done
        return Button { model.closeCustomize() } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                Text("Done").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Self.accentInk)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Self.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white, lineWidth: focused ? 2.5 : 0))
        }
        .buttonStyle(.plain)
    }
}
