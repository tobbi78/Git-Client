//
//  CommandPaletteView.swift
//  Git-Client
//
//  Spotlight-artige Befehlspalette (⌘K): durchsucht Bookmark-Repositories sowie,
//  falls ein Repository geöffnet ist, dessen bereits geladene Branches, Tags und
//  Commits. Reine Navigationshilfe — keine schreibenden Git-Operationen.
//
//  Eigene VStack/ScrollView-Liste statt List — konsistent mit RepositoryBrowserView
//  (dort bewusst kein NSOutlineView/List, um Event-Handling voll selbst zu steuern;
//  hier zusätzlich nötig für eigene Pfeiltasten-Navigation via onMoveCommand).
//

import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var appModel

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var results: [CommandPaletteResult] {
        CommandPaletteResult.search(
            query: query,
            repositories: appModel.bookmarkNodes.allRepositories(),
            branches: appModel.repositoryViewModel?.branches ?? [],
            tags: appModel.repositoryViewModel?.tags ?? [],
            commits: appModel.repositoryViewModel?.commits ?? []
        )
    }

    var body: some View {
        ZStack {
            // Scrim: Klick außerhalb schließt die Palette.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            panel
                .frame(width: 560)
        }
        .onAppear { isSearchFocused = true }
        .onExitCommand { close() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                resultList
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 24, y: 8)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Repository, Branch, Tag oder Commit…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onSubmit { activateSelected() }
        }
        .padding(14)
    }

    private var emptyState: some View {
        Text(query.isEmpty ? "Keine Repositories vorhanden." : "Keine Treffer.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        row(result, isSelected: index == selectedIndex)
                            .id(result.id)
                            .onTapGesture {
                                selectedIndex = index
                                activateSelected()
                            }
                            .onHover { hovering in
                                if hovering { selectedIndex = index }
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 340)
            .onChange(of: selectedIndex) { _, newValue in
                guard results.indices.contains(newValue) else { return }
                proxy.scrollTo(results[newValue].id)
            }
            .onMoveCommand { direction in
                switch direction {
                case .up:   selectedIndex = max(0, selectedIndex - 1)
                case .down: selectedIndex = min(results.count - 1, selectedIndex + 1)
                default: break
                }
            }
        }
    }

    private func row(_ result: CommandPaletteResult, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result.symbolName)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
    }

    // MARK: - Aktionen

    private func activateSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        activate(results[selectedIndex])
    }

    private func activate(_ result: CommandPaletteResult) {
        switch result {
        case .repository(let bookmark):
            if appModel.openedRepository?.id != bookmark.id {
                appModel.openRepository(bookmark)
            }
        case .branch(let branch):
            appModel.repositoryViewModel?.selectCommit(bySha: branch.tipSha)
        case .tag(let tag):
            appModel.repositoryViewModel?.selectCommit(bySha: tag.targetSha)
        case .commit(let commit):
            appModel.repositoryViewModel?.selectCommit(bySha: commit.sha)
        }
        close()
    }

    private func close() {
        appModel.isCommandPaletteOpen = false
    }
}
