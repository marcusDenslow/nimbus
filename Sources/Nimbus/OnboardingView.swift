import SwiftUI

/// First-run flow (and the "add profile" flow): welcome → create profile → GeForce NOW →
/// optional SteamGridDB key → done. Over the shared silk background, one step at a time, with a
/// live accent preview so the choices feel immediate. Controller-driven through the model
/// (↑↓ move, ←→ adjust, Cross select, Circle back); pointer clicks the same controls.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    private var accent: Color { AccentPalette.color(model.draftAccentIndex) }

    var body: some View {
        ZStack {
            CinematicBackground()

            VStack(spacing: 0) {
                if model.onboardingSteps.count > 1 {
                    progressDots.padding(.top, 54)
                }
                Spacer()
                stepContent
                    .frame(maxWidth: 720)
                    .id(model.onboardingIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 40)),
                        removal: .opacity.combined(with: .offset(x: -40))))
                Spacer()
                hints.padding(.bottom, 40)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.onboardingIndex)
        }
        .ignoresSafeArea()
    }

    private var progressDots: some View {
        HStack(spacing: 9) {
            ForEach(0..<model.onboardingSteps.count, id: \.self) { i in
                Capsule()
                    .fill(i == model.onboardingIndex ? accent : .white.opacity(0.2))
                    .frame(width: i == model.onboardingIndex ? 26 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.onboardingIndex)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.onboardingStep {
        case .welcome: welcomeStep
        case .profile: profileStep
        case .geforce: geforceStep
        case .artKey: artKeyStep
        case .finish: finishStep
        case .none: EmptyView()
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 70, weight: .light))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.5), radius: 30)
            Text("NIMBUS")
                .font(.nimbusDisplay(60, weight: .heavy))
                .tracking(4)
                .foregroundStyle(.white)
            Text("A controller-first shelf for your GeForce NOW library.\nLet's set up your space.")
                .font(.system(size: 17, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(4)
                .padding(.bottom, 12)
            PillButton(label: "Get Started", systemImage: "arrow.right", focused: true,
                       primary: true, accent: accent) { model.advanceOnboarding() }
        }
    }

    // MARK: - Profile

    private var profileStep: some View {
        VStack(spacing: 30) {
            stepHeader("Create your profile", "Your library, folders, and stats live here.")

            HStack(spacing: 30) {
                ProfileAvatar(name: model.draftName, colorIndex: model.draftColorIndex,
                              size: 108, ringed: true, ringColor: accent)
                    .animation(.easeOut(duration: 0.25), value: model.draftColorIndex)

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME").font(.system(size: 11, weight: .bold)).tracking(2.5)
                        .foregroundStyle(.white.opacity(0.5))
                    nameField
                }
            }

            VStack(spacing: 18) {
                swatchGroup(title: "Avatar Color", focused: model.onboardingFocus == 1) {
                    ForEach(0..<AvatarPalette.count, id: \.self) { i in
                        Circle()
                            .fill(AvatarPalette.gradient(i))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.white,
                                     lineWidth: model.draftColorIndex == i ? 3 : 0))
                            .scaleEffect(model.draftColorIndex == i ? 1.12 : 1)
                            .onTapGesture { model.draftColorIndex = i; model.onboardingFocus = 1 }
                    }
                }
                swatchGroup(title: "Accent", focused: model.onboardingFocus == 2) {
                    ForEach(AccentPalette.options) { opt in
                        Circle()
                            .fill(AccentPalette.color(opt.id))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(.white,
                                     lineWidth: model.draftAccentIndex == opt.id ? 3 : 0))
                            .scaleEffect(model.draftAccentIndex == opt.id ? 1.12 : 1)
                            .onTapGesture {
                                model.draftAccentIndex = opt.id
                                model.onboardingFocus = 2
                                AccentPalette.current = AccentPalette.color(opt.id)
                            }
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.draftColorIndex)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.draftAccentIndex)

            PillButton(label: "Continue", systemImage: "arrow.right",
                       focused: model.onboardingFocus == 3, primary: true, accent: accent) {
                model.onboardingActivate(3)
            }
        }
    }

    private var nameField: some View {
        let focused = model.onboardingFocus == 0
        return HStack {
            TextField("Player", text: Binding(get: { model.draftName },
                                              set: { model.draftName = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if model.controllerConnected {
                Image(systemName: "keyboard")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: 300)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(focused ? accent : .white.opacity(0.12), lineWidth: focused ? 2.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { if model.controllerConnected { model.onboardingActivate(0) } else { model.onboardingFocus = 0 } }
    }

    // MARK: - GeForce NOW

    private var geforceStep: some View {
        VStack(spacing: 28) {
            OnboardBadge(symbol: "bolt.fill", accent: accent)
            stepHeader("Link GeForce NOW",
                       "Nimbus reads your GeForce NOW library from the app's own files — no login. Open GeForce NOW once so the log is fresh, then sync.")

            statusPill(GFNLocal.isInstalled ? "GeForce NOW is installed" : "GeForce NOW not found",
                       ok: GFNLocal.isInstalled)

            HStack(spacing: 14) {
                PillButton(label: "Sync My Library", systemImage: "arrow.triangle.2.circlepath",
                           focused: model.onboardingFocus == 0, primary: true, accent: accent) {
                    model.onboardingActivate(0)
                }
                PillButton(label: "Skip for now", systemImage: nil,
                           focused: model.onboardingFocus == 1, primary: false, accent: accent) {
                    model.onboardingActivate(1)
                }
            }
        }
    }

    // MARK: - SteamGridDB key

    private var artKeyStep: some View {
        VStack(spacing: 28) {
            OnboardBadge(symbol: "photo.artframe", accent: accent)
            stepHeader("Better box art (optional)",
                       "A free SteamGridDB API key unlocks custom covers, heroes, and logos for games without Steam art. You can always add it later in Account.")

            statusPill(SteamGridDB.hasKey ? "Key saved" : "No key yet — this step is optional",
                       ok: SteamGridDB.hasKey)

            HStack(spacing: 14) {
                PillButton(label: "Paste from Clipboard", systemImage: "doc.on.clipboard",
                           focused: model.onboardingFocus == 0, primary: false, accent: accent) {
                    model.onboardingActivate(0)
                }
                PillButton(label: "Type Key", systemImage: "keyboard",
                           focused: model.onboardingFocus == 1, primary: false, accent: accent) {
                    model.onboardingActivate(1)
                }
                PillButton(label: "Continue", systemImage: "arrow.right",
                           focused: model.onboardingFocus == 2, primary: true, accent: accent) {
                    model.onboardingActivate(2)
                }
            }
        }
    }

    // MARK: - Finish

    private var finishStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(accent.opacity(0.25)).frame(width: 130, height: 130).blur(radius: 24)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 88, weight: .light))
                    .foregroundStyle(accent)
            }
            Text("You're all set")
                .font(.nimbusDisplay(44, weight: .heavy))
                .foregroundStyle(.white)
            Text(model.library.isEmpty
                 ? "Add games any time with Search — press \(model.controllerConnected ? "the Menu button" : "⌘F")."
                 : "\(model.library.count) games ready on your shelf.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 10)
            PillButton(label: "Enter Nimbus", systemImage: "arrow.right", focused: true,
                       primary: true, accent: accent) { model.advanceOnboarding() }
        }
    }

    // MARK: - Shared pieces

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.nimbusDisplay(38, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 560)
        }
    }

    private func swatchGroup<Content: View>(title: String, focused: Bool,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold)).tracking(2)
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 12) { content() }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.white.opacity(focused ? 0.06 : 0.0),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(focused ? accent.opacity(0.9) : .white.opacity(0.08),
                          lineWidth: focused ? 2.5 : 1))
    }

    private func statusPill(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? .green : .orange).frame(width: 8, height: 8)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.white.opacity(0.05), in: Capsule())
    }

    @ViewBuilder
    private var hints: some View {
        let controller = model.controllerConnected
        HStack(spacing: 22) {
            switch model.onboardingStep {
            case .welcome, .finish:
                confirmHint(label: "Continue", controller: controller)
            default:
                Hint(text: "↑↓", label: "Move")
                if model.onboardingStep == .profile { Hint(text: "←→", label: "Adjust") }
                confirmHint(label: "Select", controller: controller)
                if controller { Hint(symbol: "circle.circle.fill", label: "Back") }
                else { Hint(text: "esc", label: "Back") }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 5, y: 1)
    }

    @ViewBuilder
    private func confirmHint(label: String, controller: Bool) -> some View {
        if controller { Hint(symbol: "xmark.circle.fill", label: label) }
        else { Hint(text: "↩", label: label) }
    }
}

/// A large circular icon badge used at the top of onboarding steps.
struct OnboardBadge: View {
    let symbol: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.18)).frame(width: 96, height: 96)
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(accent)
        }
        .shadow(color: accent.opacity(0.35), radius: 24)
    }
}

/// Rounded action button used throughout onboarding. Solid (accent) when primary; outlined
/// otherwise. Rings and lifts when focused by the controller.
struct PillButton: View {
    let label: String
    var systemImage: String?
    let focused: Bool
    var primary: Bool = false
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                }
                Text(label).font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(primary ? .black : .white)
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background {
                if primary {
                    Capsule().fill(accent)
                } else {
                    Capsule().fill(.white.opacity(0.1))
                }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(focused ? 0.95 : 0),
                                            lineWidth: focused ? 3 : 0))
            .shadow(color: primary ? accent.opacity(0.4) : .clear, radius: focused ? 16 : 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(focused ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: focused)
    }
}
