import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel

    private let cardSpacing: CGFloat = 22
    /// The library index the strip is currently centred on. Tracks keyboard/controller focus but
    /// NOT pointer hover, so hovering a side card highlights it without yanking the whole shelf.
    /// (`ViewState` box rather than `@State` — see ViewState.swift for the SDK reason.)
    @StateObject private var centered = ViewState(0)

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                TopBar()
                    .padding(.top, 44)

                if model.library.isEmpty {
                    EmptyLibraryView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.visibleLibrary.isEmpty {
                    EmptyFolderView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(model.activeFolderID)
                        .transition(folderSwap)
                } else {
                    Spacer()
                    // Portrait 2:3 tiles (the 600×900 capsule shape); the focused game is named
                    // in the panel below. The row is height-constrained (a horizontal ScrollView
                    // otherwise grabs all vertical space); the group is centered, nudged up a touch.
                    let cardHeight = min(geo.size.height * 0.34, 300)
                    VStack(spacing: 0) {
                        row(cardWidth: cardHeight * 2 / 3)
                            .frame(height: cardHeight + 100)
                        FocusedGamePanel()
                            .padding(.top, 22)
                    }
                    // New shelf per folder: the whole group cross-fades and slides on a switch.
                    .id(model.activeFolderID)
                    .transition(folderSwap)
                    // Slight upward bias only — the taller 2:3 cards leave less headroom, and a
                    // bigger lift ran the focused card into the top bar.
                    .offset(y: -40)
                    Spacer()
                }

                HintBar()
            }
            .animation(.easeInOut(duration: 0.34), value: model.activeFolderID)
        }
    }

    /// Folder switch: the outgoing shelf fades left, the incoming shelf slides in from the right.
    private var folderSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 44)),
            removal: .opacity.combined(with: .offset(x: -44)))
    }

    /// PS5-style single horizontal shelf, ordered by the current sort.
    ///
    /// The strip owns its scroll: every card is placed by an `.offset(x:)` computed from its
    /// distance (in fixed card-steps) from `centeredIndex`, and the move is a plain value
    /// animation on that offset. Unlike `ScrollViewReader.scrollTo` on a `LazyHStack` — whose
    /// animation SwiftUI silently drops whenever the target's lazy geometry isn't settled or the
    /// main thread hitches (e.g. a background video mounting) — an offset we animate ourselves
    /// can never be dropped mid-flight, so every move glides.
    private func row(cardWidth: CGFloat) -> some View {
        let games = model.visibleLibrary
        let step = cardWidth + cardSpacing
        return GeometryReader { geo in
            // Left-aligned shelf that starts at the leading content margin (56, matching the top bar
            // + hero). The strip doesn't scroll on every focus move: the highlight first travels
            // across the cards already on screen, and only once it nears the right edge does the
            // whole strip slide (keeping the focused card pinned there). `scrollIndex` is the number
            // of cards scrolled off the left; it's 0 for the first screenful.
            let leadingMargin: CGFloat = 56
            let fit = max(1, Int((geo.size.width - leadingMargin) / step))   // cards that fit fully
            let anchorSlot = max(0, fit - 2)   // keep one card visible ahead before scrolling kicks in
            let maxScroll = max(0, games.count - fit)
            let scrollIndex = min(maxScroll, max(0, centered.value - anchorSlot))
            // Breathing room for the 1.32× focus zoom: it grows a card by ~0.16·width on each side,
            // so push the focused card's neighbours outward by that much — otherwise the enlarged
            // card overlaps the next one instead of the row making room for it.
            let spread = cardWidth * 0.18
            let focus = model.libraryZone == .shelf ? model.focusedIndex : -1
            let half = windowHalf(width: geo.size.width, step: step)
            ZStack(alignment: .topLeading) {
                ForEach(windowIndices(count: games.count, center: centered.value, half: half), id: \.self) { index in
                    let game = games[index]
                    let isFocused = index == focus
                    let shift: CGFloat = focus < 0 ? 0 : (index > focus ? spread : (index < focus ? -spread : 0))
                    GameCard(game: game, focused: isFocused, showTitle: false)
                        .frame(width: cardWidth)
                        .zIndex(isFocused ? 1 : 0)   // the zoomed card draws over its neighbours
                        .offset(x: leadingMargin + CGFloat(index - scrollIndex) * step + shift, y: 46)
                        .onTapGesture {
                            if index == model.focusedIndex {
                                model.launch(game)
                            } else {
                                model.focusGame(id: game.id)
                            }
                        }
                        .onHover { hovering in
                            if hovering { model.focusGame(id: game.id) }
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()   // cards clip cleanly at the shelf edges as they slide off
            .animation(.easeOut(duration: 0.3), value: centered.value)
            .animation(.easeOut(duration: 0.26), value: model.focusedIndex)   // neighbours make room on hover
        }
        // Recentre on keyboard/controller focus moves only. Hover sets focus (for the zoom
        // highlight) but leaves the centre alone — recentring on hover would slide the card out
        // from under the cursor and spin a focus/scroll jitter loop.
        .onChange(of: model.focusedIndex) { _, new in
            if !model.focusChangeFromPointer { centered.value = new }
        }
        .onChange(of: model.activeFolderID) { _, _ in centered.value = model.focusedIndex }
        .onChange(of: model.visibleLibrary.count) { _, count in
            centered.value = min(centered.value, max(0, count - 1))
        }
        .onAppear { centered.value = model.focusedIndex }
    }

    /// How many cards to render on each side of centre: enough to fill half the strip plus a small
    /// buffer, so cards realise just off-screen and there's no visible pop as they enter.
    private func windowHalf(width: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 12 }
        // Left-anchored now, so the visible cards run the full width to the right of centre (the
        // left side stays off-screen and clipped) — render a full width's worth plus a buffer.
        return Int(width / step) + 2
    }

    /// The clamped range of library indices to render around `center`. Keyed by absolute index —
    /// which maps 1:1 to a game — so a card that stays on-screen keeps its identity and slides,
    /// while cards entering/leaving the window do so off-screen.
    private func windowIndices(count: Int, center: Int, half: Int) -> [Int] {
        guard count > 0 else { return [] }
        let lo = max(0, center - half)
        let hi = min(count - 1, center + half)
        return Array(lo...hi)
    }
}

/// PS5-style hero block under the shelf, over the ambient art: the focused game's name and the
/// Play / Info buttons. Down from the shelf drops focus into Play; Right steps Play → Info.
struct FocusedGamePanel: View {
    @EnvironmentObject private var model: AppModel
    /// SteamGridDB logo wordmark, shown in place of the plain-text title when one exists.
    @StateObject private var logo = ViewState<NSImage?>(nil)

    var body: some View {
        if let game = model.focusedGame {
            VStack(alignment: .leading, spacing: 14) {
                Text(eyebrow(for: game))
                    .font(.nimbusLabel(12.5))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.65))

                if let logoImage = logo.value {
                    Image(nsImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 700, maxHeight: 210, alignment: .leading)
                } else {
                    Text(game.title)
                        .font(.nimbusDisplay(58))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                HStack(spacing: 12) {
                    CardPlayButton(active: model.shelfAction == .play,
                                   launching: model.launchingGame?.id == game.id) { model.launch(game) }
                        .overlay {
                            GeometryReader { g in
                                Capsule().fill(model.accent.opacity(0.35))
                                    .frame(width: g.size.width * min(1, model.triggerPull / 0.9))
                            }
                            .allowsHitTesting(false)
                        }
                        .clipShape(Capsule())
                        .animation(.easeOut(duration: 0.07), value: model.triggerPull)
                    Button { model.shelfAction = .info; model.openShelfMenu() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.14), in: Circle())
                            .overlay(Circle().strokeBorder(
                                .white.opacity(model.shelfAction == .info || model.shelfMenuOpen ? 0.9 : 0),
                                lineWidth: 2.5))
                            .foregroundStyle(.white)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    // Opens upward, above the ⋯ button. The hero sits low on the screen, so a
                    // downward menu ran into the hint bar; growing up keeps it clear and over art.
                    .overlay(alignment: .bottomLeading) {
                        if model.shelfMenuOpen {
                            shelfMenuList(game)
                                .offset(x: 6, y: -62)
                                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomLeading)))
                        }
                    }
                }
                .padding(.top, 2)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: model.shelfMenuOpen)
            }
            .id(game.id)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 56)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: model.shelfAction)
            .task(id: "\(game.id)-\(model.customizeRevision)") {
                logo.value = await LogoCache.shared.displayLogo(for: game)
            }
        }
    }

    private func eyebrow(for game: Game) -> String {
        if let store = game.store, !store.isEmpty { return store }
        return "GeForce NOW"
    }

    /// The per-game ⋯ dropdown. Navigable by stick/d-pad (Up/Down, Cross to pick, Circle to
    /// close) via the model, and clickable/hoverable with the pointer.
    private func shelfMenuList(_ game: Game) -> some View {
        VStack(spacing: 2) {
            shelfRow(.info, "Info", "info.circle")
            shelfRow(.customize, "Customize", "slider.horizontal.3")
            shelfRow(.favorite,
                     model.isFavorite(game) ? "Unfavorite" : "Favorite",
                     model.isFavorite(game) ? "heart.slash" : "heart")
            shelfRow(.playTrailer, "Play Trailer", "play.rectangle")
        }
        .padding(6)
        .frame(width: 232)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    private func shelfRow(_ item: ShelfMenuItem, _ title: String, _ symbol: String) -> some View {
        let index = model.shelfMenuItems.firstIndex(of: item)
        let focused = (index ?? -1) == model.shelfMenuIndex
        return Button { model.selectShelfMenu(item) } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 20)
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(focused ? Color.white.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0, let index { model.shelfMenuIndex = index } }
    }
}

/// PS5-style top navigation: folder tabs and the sort toggle scroll on the left; the profile
/// chip is pinned top-right and opens a quick-actions dropdown. Reached by pressing Up from the
/// shelf; navigate with ←/→, activate with Cross/↩, Down returns to shelf.
struct TopBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            tabs
            ProfileChip()
                .padding(.trailing, 56)
        }
    }

    /// Left group: folder tabs + sort, horizontally scrollable. The profile item is rendered
    /// separately (pinned right), so it's skipped here even though it stays last in the model.
    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.topBarItems.enumerated()), id: \.offset) { index, item in
                        if item != .profile {
                            chip(item, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(.leading, 56)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
            .onChange(of: model.topBarIndex) { _, new in
                guard model.libraryZone == .topBar else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chip(_ item: TopBarItem, index: Int) -> some View {
        let focused = model.libraryZone == .topBar && model.topBarIndex == index
        switch item {
        case .folder(let id):
            let name = model.folderTabs.first { $0.id == id }?.name ?? "Folder"
            let dot = id.flatMap { fid in model.folders.first { $0.id == fid } }
                .map { folderAccent($0.colorIndex) }
            let count = id == nil ? model.library.count
                : (model.folders.first { $0.id == id }?.gameIDs.count ?? 0)
            base(text: name, dot: dot, count: count, active: id == model.activeFolderID, focused: focused) {
                model.setActiveFolder(id)
            }
        case .sort:
            base(text: "Sort · \(model.sortMode.label)", symbol: "arrow.up.arrow.down",
                 active: false, focused: focused) {
                model.cycleSort(by: 1)
            }
        case .profile:
            EmptyView()   // pinned right by ProfileChip
        }
    }

    private func base(text: String, symbol: String? = nil, dot: Color? = nil, count: Int? = nil,
                      active: Bool, focused: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                }
                Text(text).font(.system(size: 13, weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .modifier(ChipShape(active: active, focused: focused))
        }
        .buttonStyle(.plain)
        .foregroundStyle(active || focused ? .primary : .secondary)
        .scaleEffect(focused ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
    }
}

/// Gradient initials bubble shared by the top-bar chip and the profile dropdown header.
struct Avatar: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(hue: 0.58, saturation: 0.7, brightness: 0.9),
                         Color(hue: 0.72, saturation: 0.7, brightness: 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

/// Player chip pinned to the top-right. Cross/click opens the quick-actions dropdown.
struct ProfileChip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let index = model.topBarItems.count - 1
        let focused = model.libraryZone == .topBar && model.topBarIndex == index
        Button { model.openProfileMenu() } label: {
            HStack(spacing: 8) {
                Avatar(name: model.playerName, size: 24)
                Text(model.playerName).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(model.profileMenuOpen ? 180 : 0))
            }
            .modifier(ChipShape(active: model.profileMenuOpen, focused: focused))
        }
        .buttonStyle(.plain)
        .scaleEffect(focused ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
        .animation(.easeOut(duration: 0.2), value: model.profileMenuOpen)
    }
}

/// Quick-actions dropdown anchored under the profile chip. Stick/keyboard drive the highlight
/// (Up/Down, Cross/↩ to pick, Circle/Esc to dismiss); the pointer hovers + clicks the same rows.
struct ProfileMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if model.profileMenuOpen {
                // Scrim over the shelf; a tap outside the panel dismisses.
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { model.closeProfileMenu() }
                    .transition(.opacity)

                panel
                    .padding(.top, 96)
                    .padding(.trailing, 56)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.profileMenuOpen)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.12)).padding(.horizontal, 8)
            VStack(spacing: 2) {
                ForEach(Array(model.profileMenuItems.enumerated()), id: \.offset) { index, item in
                    row(item, index: index)
                }
            }
            .padding(6)
        }
        .frame(width: 300, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(name: model.playerName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.playerName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(model.library.count) games · \(model.folders.count) folders")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func row(_ item: ProfileMenuItem, index: Int) -> some View {
        let focused = model.profileMenuIndex == index
        return Button { model.selectProfileMenu(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(item))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(tint(item))
                Text(label(item))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item == .quit ? Color.red.opacity(0.9) : .primary)
                Spacer(minLength: 8)
                if let hint = shortcut(item) {
                    Text(hint)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(focused ? Color.white.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.5 : 0), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in if hovering { model.profileMenuIndex = index } }
    }

    private func symbol(_ item: ProfileMenuItem) -> String {
        switch item {
        case .surprise: return "dice.fill"
        case .addGames: return "magnifyingglass"
        case .sync: return "arrow.triangle.2.circlepath"
        case .stats: return "chart.bar.xaxis"
        case .account: return "person.crop.circle"
        case .switchProfile: return "arrow.left.arrow.right"
        case .standby: return "moon.zzz.fill"
        case .quit: return "power"
        }
    }

    private func label(_ item: ProfileMenuItem) -> String {
        switch item {
        case .surprise: return "Surprise Me"
        case .addGames: return "Add Games"
        case .sync: return "Sync GeForce NOW"
        case .stats: return "Stats & Insights"
        case .account: return "Account & Settings"
        case .switchProfile: return "Switch Profile"
        case .standby: return "Enter Standby"
        case .quit: return "Quit Nimbus"
        }
    }

    private func shortcut(_ item: ProfileMenuItem) -> String? {
        switch item {
        case .surprise: return nil
        case .addGames: return "⌘F"
        case .sync: return "⌘S"
        case .stats: return nil
        case .account: return "⌘,"
        case .switchProfile: return nil
        case .standby: return nil
        case .quit: return "⌘Q"
        }
    }

    private func tint(_ item: ProfileMenuItem) -> Color {
        switch item {
        case .surprise: return model.accent
        case .stats: return model.accent
        case .quit: return .red.opacity(0.9)
        default: return .white.opacity(0.85)
        }
    }
}

/// Shared capsule background for top-bar chips: filled when active, ringed when focused.
private struct ChipShape: ViewModifier {
    let active: Bool
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(active ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(.white.opacity(0.05)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(
                .white.opacity(focused ? 0.95 : (active ? 0.3 : 0.08)),
                lineWidth: focused ? 2.5 : 1))
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Your library is empty")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(model.controllerConnected
                 ? "Press \(Image(systemName: "arrow.triangle.2.circlepath.circle.fill")) to import your GeForce NOW library, or \(Image(systemName: "line.3.horizontal.circle.fill")) to add games"
                 : "Press ⌘S to import your GeForce NOW library, or ⌘F to add games")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .offset(y: -30)
    }
}

struct EmptyFolderView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No games in this folder")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Open a game (Square / i) and add it to this folder.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .offset(y: -30)
    }
}

struct HintBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 22) {
            if model.libraryZone == .topBar {
                topBarHints
            } else {
                shelfHints
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(model.controllerConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(model.controllerConnected ? "Controller connected" : "No controller")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 5, y: 1)
        .padding(.horizontal, 56)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var shelfHints: some View {
        if model.controllerConnected {
            if model.backHoldProgress > 0 {
                HoldHomeHint(progress: model.backHoldProgress, accent: model.accent)
            }
            Hint(symbol: "xmark.circle.fill", label: "Play")
            Hint(symbol: "square.circle.fill", label: "Info")
            Hint(symbol: "arrowtriangle.up.circle.fill", label: "Menu")
            Hint(symbol: "triangle.circle.fill", label: "Remove")
            Hint(symbol: "line.3.horizontal.circle.fill", label: "Add")
            Hint(text: "L2", label: "Find")
            Hint(text: "R2", label: "Launch")
        } else {
            Hint(text: "↩", label: "Play")
            Hint(text: "i", label: "Info")
            Hint(text: "↑", label: "Menu")
            Hint(text: "⌫", label: "Remove")
            Hint(text: "⌘F", label: "Add")
            Hint(text: "⌘L", label: "Find")
            Hint(text: "⌘,", label: "Account")
        }
    }

    /// Shown while focus sits in the top bar: navigation, plus an Edit-folder cue on real folders.
    @ViewBuilder
    private var topBarHints: some View {
        let editable = model.focusedTopBarFolderID != nil
        if model.controllerConnected {
            Hint(text: "←→", label: "Navigate")
            Hint(symbol: "xmark.circle.fill", label: "Open")
            if editable { Hint(symbol: "square.circle.fill", label: "Edit folder") }
            Hint(symbol: "arrowtriangle.down.circle.fill", label: "Back")
        } else {
            Hint(text: "←→", label: "Navigate")
            Hint(text: "↩", label: "Open")
            if editable { Hint(text: "i", label: "Edit folder") }
            Hint(text: "↓", label: "Back")
        }
    }
}

struct Hint: View {
    var symbol: String?
    var text: String?
    let label: String

    init(symbol: String, label: String) {
        self.symbol = symbol
        self.label = label
    }

    init(text: String, label: String) {
        self.text = text
        self.label = label
    }

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            } else if let text {
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Transient hint shown while Circle is held to trip the shelf home: a ring around the Circle
/// glyph that fills as the hold approaches the threshold.
struct HoldHomeHint: View {
    let progress: Double
    var accent: Color = .cyan

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 25, height: 25)
            }
            Text("Home")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
        }
        .animation(.linear(duration: 0.05), value: progress)
    }
}
