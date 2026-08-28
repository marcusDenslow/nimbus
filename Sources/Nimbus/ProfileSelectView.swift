import SwiftUI

/// PS5-style "who's playing?" switcher, shown after the boot press when boot behavior is
/// "Choose Profile" (or on demand from the profile menu). A row of avatars over the shared
/// silk background; the focused one lifts, rings in its own accent, and glows. A trailing
/// dashed tile adds a new profile. Controller: ←/→ move, Cross enter. Pointer: hover + click.
struct ProfileSelectView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var appeared = ViewState(false)

    private let tile: CGFloat = 150

    var body: some View {
        ZStack {
            CinematicBackground()

            VStack(spacing: 0) {
                Spacer()

                Text(greeting)
                    .font(.nimbusLabel(13))
                    .tracking(4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 14)

                Text("Who's playing?")
                    .font(.nimbusDisplay(46, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
                    .padding(.bottom, 54)

                profileRow
                    .padding(.bottom, 20)

                Spacer()
                hints
                    .padding(.bottom, 40)
            }
            .opacity(appeared.value ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: appeared.value)
        }
        .ignoresSafeArea()
        .onAppear { appeared.value = true }
    }

    private var profileRow: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 44) {
                        ForEach(Array(model.config.profiles.enumerated()), id: \.element.id) { index, profile in
                            tileView(for: profile, index: index)
                                .id(index)
                        }
                        addTile(index: model.config.profiles.count)
                            .id(model.config.profiles.count)
                    }
                    .padding(.horizontal, 60)
                    // Fill the viewport and center when the profiles fit; scroll when they don't.
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .center)
                }
                .onChange(of: model.profileSelectIndex) { _, new in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .frame(height: tile + 150)
    }

    private func tileView(for profile: Profile, index: Int) -> some View {
        let focused = model.profileSelectIndex == index
        return VStack(spacing: 18) {
            ProfileAvatar(name: profile.name, colorIndex: profile.colorIndex,
                          symbol: profile.symbol, size: tile)
                .frame(width: tile * 1.25, height: tile)

            Text(profile.name)
                .font(.system(size: 19, weight: focused ? .bold : .semibold, design: .rounded))
                .foregroundStyle(focused ? .white : .white.opacity(0.55))
                .lineLimit(1)
        }
        .scaleEffect(focused ? 1.12 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { model.selectProfile(at: index) }
        .onHover { if $0 { model.profileSelectIndex = index } }
    }

    private func addTile(index: Int) -> some View {
        let focused = model.profileSelectIndex == index
        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [8, 7]))
                    .foregroundStyle(.white.opacity(focused ? 0.9 : 0.35))
                    .frame(width: tile, height: tile)
                Image(systemName: "plus")
                    .font(.system(size: tile * 0.34, weight: .light))
                    .foregroundStyle(.white.opacity(focused ? 0.95 : 0.45))
            }
            .frame(width: tile * 1.25, height: tile)

            Text("Add Profile")
                .font(.system(size: 19, weight: focused ? .bold : .semibold, design: .rounded))
                .foregroundStyle(focused ? .white : .white.opacity(0.55))
        }
        .scaleEffect(focused ? 1.12 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { model.selectProfile(at: index) }
        .onHover { if $0 { model.profileSelectIndex = index } }
    }

    private var hints: some View {
        HStack(spacing: 22) {
            if model.controllerConnected {
                Hint(text: "←→", label: "Choose")
                Hint(symbol: "xmark.circle.fill", label: "Enter")
            } else {
                Hint(text: "←→", label: "Choose")
                Hint(text: "↩", label: "Enter")
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 5, y: 1)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }
}
