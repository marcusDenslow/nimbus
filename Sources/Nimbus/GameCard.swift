import SwiftUI

struct GameCard: View {
    @EnvironmentObject private var model: AppModel
    let game: Game
    let focused: Bool
    var showTitle = true
    var showLibraryBadge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoxArt(game: game, revision: model.customizeRevision)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)   // 600×900 capsule shape — Steam and SGDB covers land uncropped
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(focused ? 0.95 : 0.08), lineWidth: focused ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if showLibraryBadge && model.isInLibrary(game) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if game.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.pink)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                            .padding(9)
                    }
                }
                .shadow(
                    color: .black.opacity(focused ? 0.6 : 0.3),
                    radius: focused ? 28 : 10,
                    y: focused ? 16 : 6
                )
                .scaleEffect(focused ? 1.32 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: focused)

            if showTitle {
                Text(game.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(focused ? .primary : .secondary)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Large Play button under the focused card. Always solid white with a black glyph; sub-focus
/// is shown by a subtle scale + a soft white glow rather than a color change.
private let cardButtonHeight: CGFloat = 50

struct CardPlayButton: View {
    let active: Bool
    var launching = false
    let action: () -> Void
    @StateObject private var pop = ViewState(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 18, weight: .heavy))
                Text("Play").font(.system(size: 19, weight: .heavy))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 54)
            .frame(height: cardButtonHeight)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
            .shadow(color: .white.opacity(active ? 0.55 : 0), radius: 14)
        }
        .buttonStyle(.plain)
        .overlay { if launching { PlayButtonFire() } }
        .scaleEffect(pop.value ? 1.18 : (active ? 1.05 : 1))
        .animation(.spring(response: 0.26, dampingFraction: 0.6), value: pop.value)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
        .onChange(of: launching) { _, now in
            guard now else { return }
            pop.value = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                pop.value = false
            }
        }
    }
}

/// The launch payoff on the Play button: a white flash plus a cyan ring punching outward from the
/// capsule. Self-animates on appear (mounted only while `launching`), never takes hit-testing.
private struct PlayButtonFire: View {
    @StateObject private var go = ViewState(false)

    var body: some View {
        ZStack {
            Capsule()
                .fill(.white)
                .opacity(go.value ? 0 : 0.9)
                .blendMode(.screen)
            Capsule()
                .strokeBorder(AccentPalette.current, lineWidth: go.value ? 0 : 3)
                .scaleEffect(go.value ? 1.55 : 1)
                .opacity(go.value ? 0 : 0.95)
        }
        .animation(.easeOut(duration: 0.46), value: go.value)
        .allowsHitTesting(false)
        .onAppear { go.value = true }
    }
}

/// Round "more / info" button beside Play — matches the Play button's height. Fills white
/// (black glyph) when it holds sub-focus.
struct CardInfoButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis").font(.system(size: 21, weight: .heavy))
                .foregroundStyle(active ? .black : .white)
                .frame(width: cardButtonHeight, height: cardButtonHeight)
                .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.4)), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(active ? 0 : 0.9), lineWidth: 2.5))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct BoxArt: View {
    let game: Game
    /// Customize revision — bumped when a custom cover is set/cleared so the tile reloads.
    var revision = 0
    @StateObject private var image = ViewState<NSImage?>(nil)
    @StateObject private var resolved = ViewState(false)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = image.value {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity)
                } else {
                    FallbackTile(game: game, showText: resolved.value)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: image.value != nil)
        }
        .task(id: "\(game.id)-\(revision)") {
            // A custom cover (SteamGridDB pick) beats the Steam capsule.
            if let custom = CustomStore.cardURL(game.id).flatMap({ NSImage(contentsOf: $0) }) {
                image.value = custom
                resolved.value = true
                return
            }
            image.value = await ImageCache.shared.art(for: game)
            resolved.value = true
        }
    }
}

/// Tile for games with no Steam capsule art (Epic, Ubisoft Connect, GOG…).
/// The gradient hue is derived from the title, so every game keeps a stable identity.
struct FallbackTile: View {
    let game: Game
    var showText = true

    var body: some View {
        let hue = game.stableHue
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.55, brightness: 0.32),
                    Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if showText {
                VStack(spacing: 10) {
                    Spacer()
                    Text(game.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 14)
                    Spacer()
                    if let store = game.store, !store.isEmpty {
                        Text(store.uppercased())
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.bottom, 14)
                    }
                }
            }
        }
    }
}
