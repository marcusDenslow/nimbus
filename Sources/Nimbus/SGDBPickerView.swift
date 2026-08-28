import SwiftUI
import ImageIO

/// SteamGridDB artwork picker — hero-focus layout, stripped to essentials: a big preview of
/// the highlighted art (framed only by its own shape and shadow), a picker rail along the
/// bottom, tabs + search in the header, nothing else. Hover previews; click (or Cross) applies.
/// Stepping the rail slides the old art out one side and the new art in from the other,
/// following the direction of travel.
///
/// First run asks for the free API key (steamgriddb.com → Profile → Preferences → API) —
/// paste from clipboard (Cross) or type it (Square) — and Nimbus remembers it.
struct SGDBPickerView: View {
    @EnvironmentObject private var model: AppModel
    /// Probed pixel dimensions ("3840 × 2160") per selection key — filled lazily for entries
    /// whose API record didn't carry them (Steam screenshots).
    @StateObject private var resCache = ViewState<[String: String]>([:])

    private static let accent = CustomizeView.accent                     // #35d6e8
    private static let accentInk = Color(red: 0.016, green: 0.125, blue: 0.153)
    private static let heroCurve = Animation.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.38)

    var body: some View {
        ZStack {
            if model.sgdbHideUI {
                // Preview mode: everything out of the way except a quiet corner cue, so the
                // applied art is judged in the real main menu.
                hiddenCue
            } else {
                Color(red: 0.012, green: 0.02, blue: 0.035).opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture { model.closeSGDB() }

                if SteamGridDB.hasKey {
                    if model.sgdbGridOpen {
                        gridBrowser
                    } else {
                        heroFocus
                    }
                } else {
                    keyCard
                        .frame(width: 560)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.sgdbGridOpen)
        .animation(.easeInOut(duration: 0.22), value: model.sgdbHideUI)
    }

    /// The marker that you're previewing from inside the artwork picker: the labeled pill in
    /// the bottom-right, breathing gently — just the right amount of annoying.
    private var hiddenCue: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HiddenCuePill(controller: model.controllerConnected) {
                    model.sgdbHideUI = false
                }
            }
            .padding(.trailing, 28)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Hero-focus layout

    private var selected: SteamGridDB.SGDBImage? {
        model.sgdbImages.indices.contains(model.sgdbIndex) ? model.sgdbImages[model.sgdbIndex] : nil
    }

    /// Identity of the current pick — keys the preview art and caption animations.
    private var selKey: String {
        "\(kindTag)-\(selected?.id ?? -1)"
    }

    private var kindTag: String {
        switch model.sgdbKind {
        case .screenshot: return "s"
        case .wallpaper: return "w"
        case .hero: return "h"
        case .grid: return "g"
        case .logo: return "l"
        }
    }

    /// What the current pool's picks are called and where a pick lands.
    private var kindNoun: String {
        switch model.sgdbKind {
        case .screenshot: return "background"
        case .wallpaper: return "wallpaper"
        case .hero: return "banner"
        case .grid: return "cover"
        case .logo: return "logo"
        }
    }

    /// The selected image's native aspect ratio, for the dynamic preview. Falls back to each
    /// pool's canonical shape when the API omitted dimensions.
    private var selectedAspect: CGFloat {
        if let w = selected?.width, let h = selected?.height, w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        switch model.sgdbKind {
        case .screenshot, .wallpaper: return 16.0 / 9.0
        case .hero: return 1920.0 / 620.0
        case .grid: return 2.0 / 3.0
        case .logo: return 2.5
        }
    }

    private var heroFocus: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.sgdbLoading && model.sgdbImages.isEmpty {
                stateBlock { ProgressView().controlSize(.small); Text("Searching…") }
            } else if let error = model.sgdbError {
                stateBlock {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundStyle(.orange)
                    Text(error)
                    if error.contains("key") {
                        Button("Change API key") { SteamGridDB.apiKey = ""; model.sgdbKeyDraft = "" }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            } else {
                preview
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                rail
                hints
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, 64)
        .padding(.top, 52)
        .padding(.bottom, 40)
        .task(id: selKey) { await probeSelectedResolution() }
    }

    /// Fill the caption's resolution for picks that came without dimensions: pull just the
    /// image header (a Range request) and read the pixel size out of it.
    private func probeSelectedResolution() async {
        guard let selected, selected.width == nil, resCache.value[selKey] == nil else { return }
        let key = selKey
        guard let url = URL(string: selected.urlOriginal ?? selected.url) else { return }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-131071", forHTTPHeaderField: "Range")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return }
        resCache.value[key] = "\(width) × \(height)"
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Self.accent)
            Text("SteamGridDB")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
            Text(model.sgdbMatchName ?? model.customizeGame?.title ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .padding(.top, 5)

            Spacer(minLength: 16)

            searchField
                .frame(width: 260)

            HStack(spacing: 4) {
                tab("Backgrounds", .screenshot)
                tab("Wallpapers", .wallpaper)
                tab("Banners", .hero)
                tab("Covers", .grid)
                tab("Logos", .logo)
            }
            .padding(4)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func tab(_ label: String, _ kind: SteamGridDB.Kind) -> some View {
        let active = model.sgdbKind == kind
        return Button { model.setSGDBKind(kind) } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(active ? Self.accent : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .foregroundStyle(active ? Self.accentInk : .white.opacity(0.65))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            TextField("Search", text: Binding(
                get: { model.sgdbQuery },
                set: { model.sgdbQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .onSubmit { model.runSGDBSearch() }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    /// The big preview: the art alone at its native aspect, framed by nothing but its rounded
    /// corners and shadow. Stepping the rail slides the outgoing image toward where you came
    /// from and the incoming one in from where you're headed — subtle, a slide-and-fade, not a
    /// carousel fling. Click applies. A small resolution line sits under the art's bottom-left.
    private var preview: some View {
        ZStack {
            if let selected {
                framedArt(selected)
                    .id(selKey)
                    .transition(slide)
                    .onTapGesture { model.applySGDB(selected) }
            }

            VStack {
                Spacer()
                HStack {
                    caption
                    Spacer()
                    if model.sgdbLoading { ProgressView().controlSize(.small) }
                }
            }
        }
        .animation(Self.heroCurve, value: selKey)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Directional slide-and-fade, ~44 px of travel: stepping right, the old art exits left and
    /// the new one enters from the right; stepping left mirrors. Direction is set in the model
    /// before the index changes, so both halves read the fresh value.
    private var slide: AnyTransition {
        let dir = model.sgdbSlideDirection
        return .asymmetric(
            insertion: .offset(x: 44 * dir).combined(with: .opacity),
            removal: .offset(x: -44 * dir).combined(with: .opacity))
    }

    private func framedArt(_ image: SteamGridDB.SGDBImage) -> some View {
        AsyncImage(url: URL(string: image.url)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fit)
            case .failure:
                artPlaceholder {
                    Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.tertiary)
                }
            default:
                artPlaceholder { ProgressView().controlSize(.small) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 36, y: 18)
        .contentShape(Rectangle())
    }

    /// Stand-in at the incoming art's shape, so the frame holds size while the file streams in.
    private func artPlaceholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Color(red: 0.04, green: 0.055, blue: 0.078)
            .aspectRatio(selectedAspect, contentMode: .fit)
            .overlay(content())
    }

    /// One quiet line: resolution (from the API, or probed off the file itself), author, position.
    private var caption: some View {
        Text(captionDetail)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            .lineLimit(1)
    }

    private var captionDetail: String {
        var parts: [String] = []
        if let w = selected?.width, let h = selected?.height {
            parts.append("\(w) × \(h)")
        } else if let probed = resCache.value[selKey] {
            parts.append(probed)
        }
        if let author = selected?.author?.name, !author.isEmpty { parts.append("by \(author)") }
        if !model.sgdbImages.isEmpty {
            parts.append("\(model.sgdbIndex + 1) of \(model.sgdbImages.count)")
        }
        return parts.joined(separator: " · ")
    }

    /// Picker rail along the bottom, kept centered on the selection. Exactly the shelf's
    /// proven pattern: `scrollTo` with anchor ids that MATCH the ForEach identity (the image
    /// id). Tagging tiles with their index over an id-keyed ForEach — the previous attempts —
    /// leaves the anchors unresolvable, and every programmatic scroll silently no-ops.
    private var rail: some View {
        let tileSize = railTileSize
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(model.sgdbImages.enumerated()), id: \.element.id) { index, image in
                        railTile(image, focused: index == model.sgdbIndex)
                            .frame(width: tileSize.width, height: tileSize.height)
                            .id(image.id)
                            // First click previews, second click applies — same rhythm as the
                            // shelf. No hover-select: the rail auto-scrolls to follow the
                            // selection, and hover would re-grab whatever slid under the cursor.
                            .onTapGesture { selectOrApply(index, image) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .onAppear {
                guard model.sgdbImages.indices.contains(model.sgdbIndex) else { return }
                proxy.scrollTo(model.sgdbImages[model.sgdbIndex].id, anchor: .center)
            }
            .onChange(of: model.sgdbIndex) { _, new in
                guard model.sgdbImages.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(model.sgdbImages[new].id, anchor: .center)
                }
            }
        }
        .frame(height: tileSize.height + 16)
    }

    /// Pointer path shared by the rail and the grid: tap selects; tap on the already-selected
    /// tile applies it.
    private func selectOrApply(_ index: Int, _ image: SteamGridDB.SGDBImage) {
        if model.sgdbIndex == index {
            model.applySGDB(image)
        } else {
            model.sgdbSlideDirection = index > model.sgdbIndex ? 1 : -1
            model.sgdbIndex = index
            Sound.tick()
        }
    }

    /// Rail tiles keep each pool's native shape at a shared height band.
    private var railTileSize: CGSize {
        switch model.sgdbKind {
        case .screenshot, .wallpaper: return CGSize(width: 199, height: 112)   // 16:9
        case .hero: return CGSize(width: 178, height: 112)                     // wide banner (cropped)
        case .grid: return CGSize(width: 100, height: 150)                     // portrait cover
        case .logo: return CGSize(width: 199, height: 112)                     // wordmark, letterboxed
        }
    }

    /// Transparent logos shouldn't be cropped to fill — letterbox them inside the tile.
    private var tileContentMode: ContentMode {
        model.sgdbKind == .logo ? .fit : .fill
    }

    private func railTile(_ image: SteamGridDB.SGDBImage, focused: Bool) -> some View {
        Color(red: 0.04, green: 0.055, blue: 0.078)
            .overlay {
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: tileContentMode)
                            .padding(model.sgdbKind == .logo ? 10 : 0)
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)),
                              lineWidth: focused ? 3 : 1))
            .shadow(color: .white.opacity(focused ? 0.22 : 0), radius: 15)
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.24), value: focused)
            .contentShape(Rectangle())
    }

    private func stateBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hints: some View {
        HStack(spacing: 20) {
            if model.controllerConnected {
                Hint(symbol: "xmark.circle.fill", label: "Set \(kindNoun)")
                Hint(symbol: "arrowtriangle.down.circle.fill", label: "All results")
                Hint(text: "L1 R1", label: "Art type")
                Hint(symbol: "triangle.circle.fill", label: "Preview")
                Hint(symbol: "square.circle.fill", label: "Edit search")
                Hint(symbol: "circle.circle.fill", label: "Close")
            } else {
                Hint(text: "click ×2", label: "Set \(kindNoun)")
                Hint(text: "esc", label: "Close")
            }
            Spacer()
        }
    }

    // MARK: - Full-screen grid browser (Down from the rail)

    /// Every result at once: a top-to-bottom grid, rounded tiles at the pool's native shape,
    /// driven by the same selection as the rail. Rows are plain HStacks (all tiles share one
    /// aspect, so no column alignment needed); each row's anchor id is its start index, which
    /// is also the row ForEach's identity — matching identity is what makes `scrollTo` resolve.
    private var gridBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        let columns = model.sgdbGridColumns
                        let items = Array(model.sgdbImages.enumerated())
                        ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                            HStack(spacing: 14) {
                                ForEach(items[start..<min(start + columns, items.count)], id: \.element.id) { index, image in
                                    gridTile(image, focused: index == model.sgdbIndex)
                                        .onTapGesture { selectOrApply(index, image) }
                                }
                                // Pad the last partial row so its tiles keep the same width.
                                ForEach(0..<max(0, start + columns - items.count), id: \.self) { _ in
                                    Color.clear.aspectRatio(gridTileAspect, contentMode: .fit)
                                }
                            }
                            .id(start)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 4)
                }
                .onAppear { proxy.scrollTo(gridRowStart(model.sgdbIndex), anchor: .center) }
                .onChange(of: model.sgdbIndex) { _, new in
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(gridRowStart(new), anchor: .center)
                    }
                }
            }

            HStack(spacing: 20) {
                if model.controllerConnected {
                    Hint(symbol: "xmark.circle.fill", label: "Set \(kindNoun)")
                    Hint(text: "L1 R1", label: "Art type")
                    Hint(symbol: "triangle.circle.fill", label: "Preview")
                    Hint(symbol: "circle.circle.fill", label: "Back")
                } else {
                    Hint(text: "click ×2", label: "Set \(kindNoun)")
                    Hint(text: "esc", label: "Back")
                }
                Spacer()
                caption
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 64)
        .padding(.top, 52)
        .padding(.bottom, 40)
    }

    private func gridTile(_ image: SteamGridDB.SGDBImage, focused: Bool) -> some View {
        Color(red: 0.04, green: 0.055, blue: 0.078)
            .aspectRatio(gridTileAspect, contentMode: .fit)
            .overlay {
                AsyncImage(url: URL(string: image.thumb)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: tileContentMode)
                            .padding(model.sgdbKind == .logo ? 12 : 0)
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                    default:
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.08)),
                              lineWidth: focused ? 3 : 1))
            .shadow(color: .white.opacity(focused ? 0.18 : 0), radius: 12)
            .scaleEffect(focused ? 1.02 : 1)
            .animation(.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.2), value: focused)
            .contentShape(Rectangle())
    }

    /// Grid tiles keep each pool's native shape.
    private var gridTileAspect: CGFloat {
        switch model.sgdbKind {
        case .screenshot, .wallpaper: return 16.0 / 9.0
        case .hero: return 1920.0 / 620.0
        case .grid: return 2.0 / 3.0
        case .logo: return 16.0 / 9.0
        }
    }

    /// First index of the grid row containing `index` — the row-level scroll anchor.
    private func gridRowStart(_ index: Int) -> Int {
        let columns = model.sgdbGridColumns
        return (index / columns) * columns
    }

    // MARK: - API key entry (first run)

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").foregroundStyle(Self.accent)
                Text("STEAMGRIDDB")
                    .font(.system(size: 12, weight: .bold)).tracking(2.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.closeSGDB() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Connect SteamGridDB")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Artwork search needs a free personal API key. Grab one at steamgriddb.com → Profile → Preferences → API, copy it, and paste it here once — Nimbus remembers it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.sgdbError {
                Text(error)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                TextField("API key", text: Binding(
                    get: { model.sgdbKeyDraft },
                    set: { model.sgdbKeyDraft = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.14)))
                .onSubmit { model.saveSGDBKey() }

                Button { model.saveSGDBKey() } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Controller-first path: Cross reads the clipboard directly — no typing needed.
            Button { model.pasteSGDBKey() } label: {
                HStack(spacing: 8) {
                    if model.controllerConnected {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14, weight: .semibold))
                    }
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Paste from Clipboard")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Self.accentInk)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Self.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            if model.controllerConnected {
                HStack(spacing: 20) {
                    Hint(symbol: "xmark.circle.fill", label: "Paste key")
                    Hint(symbol: "square.circle.fill", label: "Type key")
                    Hint(symbol: "circle.circle.fill", label: "Close")
                }
                .padding(.top, 4)
            }
        }
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }
}


/// The preview-mode pill: "ARTWORK PREVIEW" eyebrow over the way back in, breathing slowly so
/// the eye finds it without it shouting.
private struct HiddenCuePill: View {
    let controller: Bool
    let restore: () -> Void
    @StateObject private var breathe = ViewState(false)

    var body: some View {
        Button(action: restore) {
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 11, weight: .bold))
                    Text("ARTWORK PREVIEW")
                        .font(.system(size: 10.5, weight: .heavy)).tracking(2)
                }
                .foregroundStyle(CustomizeView.accent)

                HStack(spacing: 7) {
                    if controller {
                        Image(systemName: "triangle.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Show picker")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CustomizeView.accent.opacity(breathe.value ? 0.85 : 0.35), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                breathe.value = true
            }
        }
    }
}
