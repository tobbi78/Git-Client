//
//  MainWindowView.swift
//  Git-Client
//
//  Dreispaltiges NavigationSplitView für ein geöffnetes Repository.
//  Sidebar: Branches/Tags (Schritt 6). Mitte: Commit-Liste (jetzt) → Graph (Schritt 7).
//  Detail: Commit + Diff (Schritt 8).
//

import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel
    let repository: RepositoryBookmark

    private var vm: RepositoryViewModel? { appModel.repositoryViewModel }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            commitHistory
                .navigationSplitViewColumnWidth(min: 320, ideal: 560)
        } detail: {
            detailPlaceholder
        }
        .navigationTitle(repository.name)
        .navigationSubtitle(repository.path.path)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Repositories", systemImage: "chevron.left") {
                    appModel.closeRepository()
                }
                .help("Zurück zur Repository-Übersicht")
            }
        }
    }

    // MARK: - Sidebar (Platzhalter — Schritt 6)

    private var sidebar: some View {
        List {
            Section("Branches") {
                Label("wird in Schritt 6 geladen", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section("Tags") {
                Label("wird in Schritt 6 geladen", systemImage: "tag")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Commit-Historie

    @ViewBuilder
    private var commitHistory: some View {
        if let vm {
            if vm.isLoading {
                ProgressView("Commits werden geladen…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                ContentUnavailableView(
                    "Fehler beim Laden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if vm.commits.isEmpty {
                ContentUnavailableView(
                    "Keine Commits",
                    systemImage: "tray",
                    description: Text("Dieses Repository enthält noch keine Commits.")
                )
            } else {
                commitList(vm: vm)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func commitList(vm: RepositoryViewModel) -> some View {
        List(vm.commits, selection: Binding(
            get: { vm.selectedCommitID },
            set: { vm.selectedCommitID = $0 }
        )) { commit in
            CommitRowView(commit: commit)
                .tag(commit.id)
        }
        .listStyle(.plain)
    }

    // MARK: - Detail (Platzhalter — Schritt 8)

    private var detailPlaceholder: some View {
        ContentUnavailableView(
            "Kein Commit ausgewählt",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Wähle einen Commit, um Details und Diff anzuzeigen.")
        )
    }
}

// MARK: - Commit-Zeile

private struct CommitRowView: View {
    let commit: Commit

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Ref-Badges (Branch-/Tag-Namen)
            if !commit.refNames.isEmpty {
                refBadges
            }
            // Commit-Nachricht
            Text(commit.subject)
                .lineLimit(1)
                .font(.body)
            // Meta-Zeile
            HStack(spacing: 8) {
                Text(commit.shortSha)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(commit.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.dateFormatter.string(from: commit.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var refBadges: some View {
        HStack(spacing: 4) {
            ForEach(commit.refNames, id: \.self) { ref in
                Text(ref)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(badgeColor(for: ref).opacity(0.15))
                    .foregroundStyle(badgeColor(for: ref))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func badgeColor(for ref: String) -> Color {
        if ref.hasPrefix("HEAD") { return .orange }
        if ref.hasPrefix("tag:") { return .purple }
        if ref.hasPrefix("origin/") { return .green }
        return .blue
    }
}

#Preview {
    MainWindowView(
        repository: RepositoryBookmark(
            name: "Git-Client",
            path: URL(fileURLWithPath: "/Users/Tobias.Florian/Documents/Softwareentwicklung/Swift/Git-Client")
        )
    )
    .environment(AppModel())
}
