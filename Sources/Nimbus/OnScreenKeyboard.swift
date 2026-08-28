import SwiftUI

/// Controller-driven on-screen keyboard. Any text field opens this when a controller is the
/// active input; the stick/d-pad moves the highlight, Cross types, Triangle/Square backspaces,
/// Menu or the Done key commits, Circle cancels. The pointer can also hover + click keys.
struct OnScreenKeyboard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if model.keyboardActive {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { model.endTextEntry(commit: true) }
                    .transition(.opacity)

                VStack {
                    Spacer()
                    panel
                        .padding(.bottom, 44)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.keyboardActive)
    }

    private var panel: some View {
        VStack(spacing: 20) {
            preview
            VStack(spacing: 8) {
                ForEach(Array(AppModel.keyboardRows.enumerated()), id: \.offset) { r, rowKeys in
                    HStack(spacing: 8) {
                        ForEach(Array(rowKeys.enumerated()), id: \.offset) { c, key in
                            keyButton(key, row: r, col: c)
                        }
                    }
                }
            }
            hints
        }
        .padding(28)
        .frame(width: 760)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.55), radius: 40, y: 20)
    }

    private var preview: some View {
        VStack(spacing: 8) {
            Text(model.keyboardTitle.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(2.5)
                .foregroundStyle(.secondary)
            HStack(spacing: 1) {
                Text(model.keyboardText.isEmpty ? " " : model.keyboardText)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Rectangle().fill(model.accent).frame(width: 2, height: 26).opacity(0.9)
            }
            .frame(minWidth: 340, minHeight: 34)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)))
        }
    }

    private func keyButton(_ key: KeyboardKey, row: Int, col: Int) -> some View {
        let focused = model.keyboardRow == row && model.keyboardCol == col
        let shiftLit = key == .shift && model.keyboardShift
        return Button { model.pressKeyboardKey(row: row, col: col) } label: {
            keyLabel(key)
                .frame(width: keyWidth(key), height: 50)
                .background((shiftLit ? model.accent.opacity(0.35) : Color.white.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.95 : 0.12), lineWidth: focused ? 2.5 : 1))
                .scaleEffect(focused ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: focused)
        .onHover { if $0 { model.keyboardRow = row; model.keyboardCol = col } }
    }

    @ViewBuilder
    private func keyLabel(_ key: KeyboardKey) -> some View {
        switch key {
        case .char(let ch):
            Text(model.keyboardShift ? ch.uppercased() : ch)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case .space:
            Text("space").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        case .backspace:
            Image(systemName: "delete.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
        case .shift:
            Image(systemName: "shift.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.keyboardShift ? model.accent : .white.opacity(0.85))
        case .done:
            Text("Done").font(.system(size: 15, weight: .bold)).foregroundStyle(model.accent)
        }
    }

    private func keyWidth(_ key: KeyboardKey) -> CGFloat {
        switch key {
        case .char: return 54
        case .space: return 360
        case .backspace, .shift: return 78
        case .done: return 140
        }
    }

    private var hints: some View {
        HStack(spacing: 22) {
            if model.controllerConnected {
                Hint(symbol: "xmark.circle.fill", label: "Type")
                Hint(symbol: "triangle.circle.fill", label: "Backspace")
                Hint(symbol: "arrowtriangle.up.circle.fill", label: "Done")
                Hint(symbol: "circle.circle.fill", label: "Cancel")
            } else {
                Hint(text: "type", label: "Keys work too")
                Hint(text: "↩", label: "Done")
                Hint(text: "esc", label: "Cancel")
            }
        }
        .padding(.top, 2)
    }
}
