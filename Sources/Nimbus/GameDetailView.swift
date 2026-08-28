import SwiftUI

/// Steam / PS5-style game page: the landscape hero fills the whole screen behind a scrim,
/// with title, store metadata, a fetched description, and the action row anchored bottom-left.
/// Reached with Square / the on-card Info button.
struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    let game: Game

    @StateObject private var details = ViewState<GameDetails?>(nil)
    @StateObject private var heroImage = ViewState<NSImage?>(nil)
    /// SteamGridDB logo wordmark, shown in place of the plain-text title when one exists.
    @StateObject private var logo = ViewState<NSImage?>(nil)

    var body: some View {
        ZStack {
            Color.black

            // Hero fills the entire screen. Inside Color.clear.overlay so the fill-mode image
            // can't inflate the layout.
            Color.clear
                .overlay {
                    if let image = heroImage.value {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        FallbackTile(game: game, showText: true)
                    }
                }
                .clipped()

            // Scrim: darker toward the bottom-left where the text sits.
            LinearGradient(
                colors: [.black.opacity(0.75), .black.opacity(0.15), .clear],
                startPoint: .bottom, endPoint: .top
            )
            LinearGradient(
                colors: [.black.opacity(0.65), .clear],
                startPoint: .leading, endPoint: .center
            )

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                infoPanel
            }
        }
        .ignoresSafeArea()
        .task(id: game.id) { details.value = await StoreInfo.shared.details(for: game) }
        .task(id: game.id) { heroImage.value = await ImageCache.shared.hero(for: game) }
        .task(id: game.id) { logo.value = await LogoCache.shared.displayLogo(for: game) }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                model.closeDetail()
            } label: {
                Label("Library", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)

            if let logoImage = logo.value {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 700, maxHeight: 240, alignment: .leading)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            } else {
                Text(game.title)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            }

            metaRow

            if let text = details.value?.description, !text.isEmpty {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineSpacing(4)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.isInLibrary(game) ? "In your library." : "Not in your library yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            }

            actions.padding(.top, 8)
            hints.padding(.top, 6)
        }
        .padding(.horizontal, 72)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaRow: some View {
        // Live library copy carries the local stats (playtime, last played) — the `game`
        // parameter may be a catalog copy without them.
        let owned = model.library.first { $0.id == game.id }
        let parts: [String] = [
            game.store?.isEmpty == false ? game.store : nil,
            details.value?.developer,
            details.value?.releaseDate,
            (details.value?.genres ?? game.genres)?.prefix(3).joined(separator: " · "),
            owned?.playSeconds.map { "\(Game.playtimeLabel($0)) played" },
            owned?.lastPlayed.map { "Last played \(Self.lastPlayedFormatter.string(from: $0))" },
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return HStack(spacing: 10) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3)
                }
                Text(part)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }

    /// "Today" / "Yesterday" / "12 Jul 2026" — relative where it reads naturally.
    private static let lastPlayedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    // MARK: - Actions

    private var actions: some View {
        let all = model.detailActions
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, action in
                if case .play = action {
                    actionButton(action, index: index, primary: true)
                }
            }
            FlowRow(spacing: 12) {
                ForEach(Array(all.enumerated()), id: \.offset) { index, action in
                    if case .play = action {} else {
                        actionButton(action, index: index, primary: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: DetailAction, index: Int, primary: Bool) -> some View {
        let focused = index == model.detailActionIndex && model.mode == .detail
        Button {
            model.detailActionIndex = index
            model.activateDetailAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol(for: action))
                    .font(.system(size: primary ? 17 : 13, weight: .semibold))
                Text(title(for: action))
                    .font(.system(size: primary ? 17 : 13, weight: .semibold))
            }
            .padding(.horizontal, primary ? 34 : 16)
            .padding(.vertical, primary ? 15 : 10)
            .background(background(for: action, primary: primary))
            .overlay(
                RoundedRectangle(cornerRadius: primary ? 13 : 10, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.95 : 0.14), lineWidth: focused ? 2.5 : 1)
            )
            .foregroundStyle(primary ? .black : .white)
        }
        .buttonStyle(.plain)
        .scaleEffect(focused ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
    }

    private func background(for action: DetailAction, primary: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: primary ? 13 : 10, style: .continuous)
        let active: Bool = {
            switch action {
            case .toggleLibrary: return model.isInLibrary(game)
            case .toggleFavorite: return model.isFavorite(game)
            case .toggleFolder(let id): return model.isInFolder(id, game: game)
            default: return false
            }
        }()
        return Group {
            if primary {
                shape.fill(.white)
            } else if active, case .toggleFavorite = action {
                shape.fill(.pink.opacity(0.35))
            } else if active {
                shape.fill(.green.opacity(0.35))
            } else {
                shape.fill(.white.opacity(0.12))
            }
        }
    }

    private func symbol(for action: DetailAction) -> String {
        switch action {
        case .play: return "play.fill"
        case .toggleLibrary: return model.isInLibrary(game) ? "checkmark" : "plus"
        case .toggleFavorite: return model.isFavorite(game) ? "heart.fill" : "heart"
        case .toggleFolder(let id): return model.isInFolder(id, game: game) ? "folder.fill" : "folder"
        case .newFolder: return "folder.badge.plus"
        }
    }

    private func title(for action: DetailAction) -> String {
        switch action {
        case .play: return "Play"
        case .toggleLibrary: return model.isInLibrary(game) ? "In Library" : "Add to Library"
        case .toggleFavorite: return model.isFavorite(game) ? "Favorited" : "Favorite"
        case .toggleFolder(let id):
            return model.folders.first(where: { $0.id == id })?.name ?? "Folder"
        case .newFolder: return "New Folder"
        }
    }

    private var hints: some View {
        HStack(spacing: 22) {
            if model.controllerConnected {
                Hint(symbol: "xmark.circle.fill", label: "Select")
                Hint(symbol: "circle.circle.fill", label: "Back")
            } else {
                Hint(text: "↑↓←→", label: "Move")
                Hint(text: "↩", label: "Select")
                Hint(text: "esc", label: "Back")
            }
        }
    }
}

/// Minimal wrapping HStack — lays children left to right and wraps to a new line when the
/// row runs out of width. Used for the detail page's secondary action chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxLineWidth = max(maxLineWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        maxLineWidth = max(maxLineWidth, rowWidth)
        return CGSize(width: min(maxLineWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
