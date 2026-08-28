import SwiftUI

/// Standby screensaver: the wave field with a large, thin clock. Shown after ~10 minutes of
/// no input; only ✕ / Return / a click wakes it (handled in AppModel / InputRouter). Uses the
/// shared SF Pro Expanded display face (see Typography.swift) so it matches the library title.
struct StandbyView: View {
    @StateObject private var breathe = ViewState(false)

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f
    }()

    var body: some View {
        ZStack {
            CinematicBackground()

            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                clock(now: ctx.date)
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                    Text("to wake")
                        .font(.nimbusLabel(11.5, weight: .regular))
                        .tracking(3.2)
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 34)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathe.value = true
            }
        }
    }

    private func clock(now: Date) -> some View {
        VStack(spacing: 0) {
            Text("Standby")
                .font(.nimbusLabel(11, weight: .bold))
                .tracking(4.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.55))
                .opacity(breathe.value ? 0.85 : 0.35)
                .padding(.bottom, 26)

            Text(Self.timeFmt.string(from: now))
                .font(.nimbusDisplay(116, weight: .ultraLight))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.25), radius: 40)

            Text(Self.dateFmt.string(from: now))
                .font(.nimbusLabel(15, weight: .regular))
                .tracking(3.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 18)
        }
    }
}
