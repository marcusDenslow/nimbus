import SwiftUI

struct SearchOverlay: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var fieldFocused: Bool

    private let horizontalPadding: CGFloat = 56
    private let cardSpacing: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, horizontalPadding + 60)
                .padding(.top, 64)

            scopeToggle
                .padding(.horizontal, horizontalPadding + 60)
                .padding(.top, 14)

            statusLine
                .padding(.top, 12)
                .padding(.bottom, 20)

            resultsGrid

            HStack(spacing: 26) {
                if model.controllerConnected {
                    Hint(symbol: "xmark.circle.fill",
                         label: model.searchScope == .library ? "Go to game" : "Add / Remove")
                    Hint(symbol: "triangle.circle.fill", label: "Scope")
                    Hint(symbol: "square.circle.fill", label: "Edit search")
                    Hint(symbol: "circle.circle.fill", label: "Done")
                } else {
                    Hint(text: "↩", label: model.searchScope == .library ? "Go to game" : "Add / Remove")
                    Hint(text: "⇥", label: "Scope")
                    Hint(text: "esc", label: "Done")
                    Hint(text: "↑↓", label: "Browse")
                }
                Spacer()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .background(.black.opacity(0.42))
        .onAppear {
            // On a controller the on-screen keyboard owns text entry, so don't steal focus into
            // the native field (its caret would sit dead with no hardware keyboard to feed it).
            guard !model.controllerConnected else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                fieldFocused = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(model.searchScope == .library ? "Search your library" : "Search all GeForce NOW games",
                      text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .focused($fieldFocused)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
    }

    /// Catalog ↔ My Library segmented chips. Clickable; Tab / Triangle flip them too.
    private var scopeToggle: some View {
        HStack(spacing: 8) {
            scopeChip("GeForce NOW Catalog", .catalog)
            scopeChip("My Library", .library)
            Spacer()
        }
    }

    private func scopeChip(_ label: String, _ scope: SearchScope) -> some View {
        let active = model.searchScope == scope
        return Button {
            if !active { model.toggleSearchScope() }
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.white.opacity(0.05)),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(active ? 0.4 : 0.1)))
                .foregroundStyle(active ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var statusLine: some View {
        Group {
            if model.searchScope == .library {
                Text("\(model.searchResults.count) of \(model.library.count) games in your library")
            } else if model.catalogLoading {
                Text("Loading catalog…")
            } else if let error = model.catalogError {
                Text(error).foregroundStyle(.orange)
            } else {
                Text("\(model.searchResults.count) of \(model.catalog.count) games on GeForce NOW")
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private var resultsGrid: some View {
        GeometryReader { geo in
            let cols = max(4, Int((geo.size.width - horizontalPadding * 2 + cardSpacing) / (170 + cardSpacing)))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: cardSpacing), count: cols),
                        spacing: cardSpacing + 10
                    ) {
                        ForEach(Array(model.searchResults.enumerated()), id: \.element.id) { index, game in
                            GameCard(
                                game: game,
                                focused: index == model.searchFocusedIndex,
                                showTitle: true,
                                showLibraryBadge: model.searchScope == .catalog
                            )
                            .id(game.id)
                            .onTapGesture {
                                model.focusSearchResult(id: game.id)
                                model.toggleFocusedSearchResult()
                            }
                            .onHover { hovering in
                                if hovering { model.focusSearchResult(id: game.id) }
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 32)
                }
                .onChange(of: model.searchFocusedIndex) { _, newValue in
                    guard model.searchResults.indices.contains(newValue), !model.focusChangeFromPointer else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(model.searchResults[newValue].id, anchor: UnitPoint(x: 0.5, y: 0.4))
                    }
                }
                .onAppear { model.searchColumns = cols }
                .onChange(of: cols) { _, newValue in model.searchColumns = newValue }
            }
        }
    }
}
