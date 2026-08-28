import SwiftUI

/// Boot intro: the wave background with a single, softly breathing button glyph — no words.
/// Any controller button, key, or click drops the user into the library.
struct BootView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var breathe = ViewState(false)

    var body: some View {
        ZStack {
            CinematicBackground()

            Image(systemName: "xmark.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .opacity(breathe.value ? 0.92 : 0.42)
                .shadow(color: .white.opacity(0.25), radius: 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.finishBoot() }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathe.value = true
            }
        }
    }
}
