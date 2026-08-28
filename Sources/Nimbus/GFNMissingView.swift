import SwiftUI

/// Full-screen stop shown when a launch finds no handler for the geforcenow:// deep link —
/// the GeForce NOW app isn't installed (or is too broken to register its URL scheme).
/// Any confirm/back input, Esc, or a click dismisses it.
struct GFNMissingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { model.dismissGFNAlert() }

            VStack(spacing: 22) {
                Image(systemName: "cloud.slash.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))

                Text("GeForce NOW Not Found")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Nimbus launches games through the GeForce NOW app, but it isn't installed or isn't able to take the launch link right now. Install or open GeForce NOW, then try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 460)

                Button { model.dismissGFNAlert() } label: {
                    Text("OK")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 13)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                if model.controllerConnected {
                    Hint(symbol: "xmark.circle.fill", label: "OK")
                } else {
                    Hint(text: "esc", label: "Dismiss")
                }
            }
            .padding(56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.6), radius: 44, y: 22)
        }
    }
}
