import SwiftUI
import AppKit

/// Profile + settings page. Fully navigable with the stick / d-pad: Up/Down move the
/// highlight, Left/Right adjust the focused control (sort, volume, folder color), Cross
/// activates, Triangle deletes a folder. Text fields (name, folder names) edit inline.
struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focus: EditTarget?

    private enum EditTarget: Hashable { case name, folder(String) }

    var body: some View {
        ZStack {
            CinematicBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        statsCard
                        HStack(alignment: .top, spacing: 22) {
                            sortCard
                            musicCard
                        }
                        personalizationCard
                        profileCard
                        foldersCard
                    }
                    .padding(.horizontal, 72)
                    .padding(.vertical, 56)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.accountIndex) { _, _ in
                    guard let f = model.accountFocus else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(f, anchor: .center) }
                }
            }
        }
        .onChange(of: model.accountEditing) { _, editing in focus = editing ? editTarget : nil }
        .onChange(of: model.editingFolderID) { _, _ in if model.accountEditing { focus = editTarget } }
        .onChange(of: focus) { _, new in
            if let new {
                guard !model.accountEditing else { return }
                switch new {
                case .name: model.beginEditing(folderID: nil)
                case .folder(let id): model.beginEditing(folderID: id)
                }
            } else if model.accountEditing {
                model.commitEditing()
            }
        }
    }

    private var editTarget: EditTarget? {
        guard model.accountEditing else { return nil }
        if let id = model.editingFolderID { return .folder(id) }
        return .name
    }

    private func ring(_ item: AccountFocus, radius: CGFloat = 12) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.95), lineWidth: 2.5)
            .opacity(model.accountFocus == item ? 1 : 0)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            ProfileAvatar(name: model.playerName,
                          colorIndex: model.activeProfile?.colorIndex ?? 0,
                          symbol: model.activeProfile?.symbol, size: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text("PROFILE")
                    .font(.system(size: 11, weight: .bold)).tracking(3)
                    .foregroundStyle(.secondary)
                TextField("Player", text: Binding(
                    get: { model.playerName },
                    set: { model.playerName = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .focused($focus, equals: .name)
                .onSubmit { model.commitEditing() }
                .frame(maxWidth: 380)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(ring(.name, radius: 8))
                .id(AccountFocus.name)
            }
            Spacer()
            Button { model.closeAccount() } label: {
                Label("Done", systemImage: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .overlay(ring(.done, radius: 20))
            .id(AccountFocus.done)
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        Card(title: "Library") {
            HStack(spacing: 40) {
                stat("\(model.library.count)", "Games")
                stat("\(model.folders.count)", "Folders")
                stat("\(model.library.filter { $0.lastPlayed != nil }.count)", "Played")
                stat(model.totalPlaySeconds > 0 ? Game.playtimeLabel(model.totalPlaySeconds) : "—",
                     "Time Played")
                stat(GFNLocal.isInstalled ? "Linked" : "—", "GeForce NOW")
            }
            if !model.storeBreakdown.isEmpty {
                Divider().overlay(.white.opacity(0.08)).padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.storeBreakdown, id: \.store) { row in
                        storeBar(row.store, count: row.count)
                    }
                }
            }
            Button { model.openStats() } label: {
                Label("Open Stats Dashboard", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func storeBar(_ store: String, count: Int) -> some View {
        let maxCount = max(1, model.storeBreakdown.map(\.count).max() ?? 1)
        return HStack(spacing: 12) {
            Text(store).font(.system(size: 13, weight: .medium))
                .frame(width: 140, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.1)).overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [model.accent, model.accentDeep], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
                }
            }
            .frame(height: 8)
            Text("\(count)").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Personalization (accent / standby / boot)

    private var personalizationCard: some View {
        Card(title: "Personalization") {
            // Accent
            VStack(alignment: .leading, spacing: 10) {
                Text("ACCENT COLOR").font(.system(size: 10.5, weight: .bold)).tracking(2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(AccentPalette.options) { opt in
                        Circle()
                            .fill(AccentPalette.color(opt.id))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white, lineWidth: model.accentIndex == opt.id ? 3 : 0))
                            .scaleEffect(model.accentIndex == opt.id ? 1.14 : 1)
                            .onTapGesture { model.setAccentIndex(opt.id) }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(ring(.accent, radius: 12))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.accentIndex)
                .id(AccountFocus.accent)
            }

            // Standby delay
            HStack {
                Text("Standby after").font(.system(size: 14, weight: .medium))
                Spacer()
                stepButton("minus") { model.setStandbyMinutes(model.config.standbyMinutes - 5) }
                Text("\(model.config.standbyMinutes) min")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(width: 74)
                stepButton("plus") { model.setStandbyMinutes(model.config.standbyMinutes + 5) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(ring(.standby, radius: 12))
            .id(AccountFocus.standby)

            // Boot behavior
            VStack(alignment: .leading, spacing: 8) {
                Text("ON STARTUP").font(.system(size: 10.5, weight: .bold)).tracking(2)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { model.config.bootBehavior },
                                              set: { model.setBootBehavior($0) })) {
                    ForEach(BootBehavior.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .overlay(ring(.bootBehavior, radius: 8).padding(-3))
                .id(AccountFocus.bootBehavior)
                Text("Choose Profile shows the switcher at launch; Last Profile jumps straight in.")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Profile

    private var profileCard: some View {
        Card(title: "Profile") {
            HStack(spacing: 14) {
                ProfileAvatar(name: model.playerName,
                              colorIndex: model.activeProfile?.colorIndex ?? 0,
                              symbol: model.activeProfile?.symbol, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.playerName).font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("\(model.config.profiles.count) profile\(model.config.profiles.count == 1 ? "" : "s") on this Mac")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.openProfileSwitcher() } label: {
                    Label("Switch Profile", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .overlay(ring(.switchProfile, radius: 20))
                .id(AccountFocus.switchProfile)
            }
            Text("Each profile keeps its own library, folders, favorites, and stats.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Sort

    private var sortCard: some View {
        Card(title: "Default Sort") {
            Picker("", selection: Binding(get: { model.sortMode }, set: { model.setSortMode($0) })) {
                ForEach(SortMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .overlay(ring(.sort, radius: 8).padding(-3))
            .id(AccountFocus.sort)
            Text("Left / Right change it here, or 1 / 2 / 3 in the library.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Music

    private var musicCard: some View {
        Card(title: "Menu Music") {
            Toggle(isOn: Binding(get: { model.musicEnabled }, set: { model.setMusicEnabled($0) })) {
                Text("Play music").font(.system(size: 14, weight: .medium))
            }
            .toggleStyle(.switch)
            .overlay(ring(.musicToggle, radius: 8).padding(-4))
            .id(AccountFocus.musicToggle)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.musicVolume) },
                                      set: { model.setMusicVolume(Float($0)) }), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            .disabled(!model.musicEnabled)
            .overlay(ring(.volume, radius: 8).padding(-4))
            .id(AccountFocus.volume)

            HStack(spacing: 8) {
                let count = MusicPlayer.shared.trackCount
                Circle().fill(count > 0 ? .green : .orange).frame(width: 7, height: 7)
                Text(count == 0 ? "No tracks — drop audio files in the music folder"
                     : count == 1 ? "1 track loaded — loops forever"
                     : "\(count) tracks — shuffled playlist")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Open Music Folder") { NSWorkspace.shared.open(MusicPlayer.musicDir) }
                    .overlay(ring(.openMusicFolder, radius: 7).padding(-3))
                    .id(AccountFocus.openMusicFolder)
                Button("Reload") { MusicPlayer.shared.start() }
                    .overlay(ring(.reloadMusic, radius: 7).padding(-3))
                    .id(AccountFocus.reloadMusic)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Folders

    private var foldersCard: some View {
        Card(title: "Folders") {
            if model.folders.isEmpty {
                Text("No folders yet. Open a game (Square / i) and choose New Folder, or add one here.")
                    .font(.system(size: 13)).foregroundStyle(.tertiary)
            }
            ForEach(model.folders) { folder in
                folderRow(folder)
            }
            Button {
                let folder = model.createFolder(named: "New Folder")
                model.openFolderEdit(folder.id)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .overlay(ring(.newFolder, radius: 7).padding(-3))
            .id(AccountFocus.newFolder)
            .padding(.top, 4)
        }
    }

    /// A launcher into the folder-edit popup — rename / recolor / delete all live there now.
    private func folderRow(_ folder: Folder) -> some View {
        Button { model.openFolderEdit(folder.id) } label: {
            HStack(spacing: 12) {
                Circle().fill(folderAccent(folder.colorIndex)).frame(width: 14, height: 14)
                Text(folder.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Text("\(folder.gameIDs.count) games").font(.system(size: 12)).foregroundStyle(.tertiary)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(ring(.folder(folder.id), radius: 10))
        }
        .buttonStyle(.plain)
        .id(AccountFocus.folder(folder.id))
    }
}

/// Rounded translucent section container used across the account page.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(2.5)
                .foregroundStyle(.secondary)
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}
