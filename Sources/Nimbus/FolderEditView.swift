import SwiftUI

/// Standalone folder-edit popup (its own mode, not buried in Settings). Rename, recolor, or
/// delete one folder. Up/Down step controls; Left/Right recolor; Cross activates; Circle closes;
/// Triangle deletes. Renaming uses the on-screen keyboard on a controller, or types natively.
struct FolderEditView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { model.closeFolderEdit() }

            if let folder = model.folderBeingEdited {
                card(folder)
                    .frame(width: 460)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .onChange(of: model.folderEditNameEditing) { _, editing in nameFocused = editing }
        .onChange(of: nameFocused) { _, focused in
            if !focused && model.folderEditNameEditing { model.commitFolderName() }
        }
    }

    private func card(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Circle().fill(folderAccent(folder.colorIndex)).frame(width: 18, height: 18)
                Text("EDIT FOLDER")
                    .font(.system(size: 12, weight: .bold)).tracking(2.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(folder.gameIDs.count) games")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            }

            nameField(folder)
            colorRow(folder)

            HStack(spacing: 12) {
                actionButton(.delete, label: "Delete", symbol: "trash", tint: .red) {
                    model.deleteCurrentFolder()
                }
                Spacer()
                actionButton(.done, label: "Done", symbol: "checkmark", tint: model.accent) {
                    model.closeFolderEdit()
                }
            }
            .padding(.top, 4)
        }
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }

    private func nameField(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.tertiary)
            TextField("Folder name", text: Binding(
                get: { model.folders.first { $0.id == folder.id }?.name ?? "" },
                set: { model.setFolderName(id: folder.id, $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .focused($nameFocused)
            .onSubmit { model.commitFolderName() }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(ring(.name, radius: 12))
            .onTapGesture { model.folderEditIndex = FolderEditControl.name.rawValue }
        }
    }

    private func colorRow(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COLOR").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.tertiary)
                Spacer()
                Text("◀ ▶").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(model.folderEditControl == .color ? 0.9 : 0.3))
            }
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    let selected = ((folder.colorIndex ?? 0) % 6 + 6) % 6 == i
                    Circle()
                        .fill(folderAccent(i))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 3 : 0))
                        .scaleEffect(selected ? 1.12 : 1)
                        .onTapGesture {
                            model.folderEditIndex = FolderEditControl.color.rawValue
                            model.setFolderColor(id: folder.id, index: i)
                        }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(ring(.color, radius: 12))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: folder.colorIndex)
        }
    }

    private func actionButton(_ control: FolderEditControl, label: String, symbol: String,
                              tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(ring(control, radius: 12))
        }
        .buttonStyle(.plain)
        .onHover { if $0 { model.folderEditIndex = control.rawValue } }
    }

    private func ring(_ control: FolderEditControl, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.95), lineWidth: 2.5)
            .opacity(model.folderEditControl == control ? 1 : 0)
    }
}
