//
//  MainWindowView.swift
//  Git-Client
//
//  Dreispaltiges NavigationSplitView für ein geöffnetes Repository.
//  Sidebar: Branches/Tags. Mitte: Commit-Liste (→ Graph in Schritt 7).
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
            commitDetail
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

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            localBranchesSection
            remoteBranchesSections
            tagsSection
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var localBranchesSection: some View {
        let local = vm?.branches.filter { !$0.isRemote } ?? []
        Section("Branches") {
            if local.isEmpty {
                Text(vm == nil ? "Wird geladen…" : "Keine Branches")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(local) { branch in
                    BranchRowView(branch: branch, isLocal: true)
                }
            }
        }
    }

    @ViewBuilder
    private var remoteBranchesSections: some View {
        let remote = vm?.branches.filter { $0.isRemote } ?? []
        let remoteNames = Array(Set(remote.compactMap(\.remoteName))).sorted()
        ForEach(remoteNames, id: \.self) { remoteName in
            let branches = remote.filter { $0.remoteName == remoteName }
            Section("Remotes / \(remoteName)") {
                ForEach(branches) { branch in
                    BranchRowView(branch: branch, isLocal: false)
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        let allTags = vm?.tags ?? []
        if !allTags.isEmpty {
            Section("Tags") {
                ForEach(allTags) { tag in
                    Label(tag.name, systemImage: "tag")
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - Commit-Historie

    @ViewBuilder
    private var commitHistory: some View {
        if let vm {
            if vm.isLoading {
                ProgressView("Wird geladen…")
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

    private static let rowHeight: CGFloat = 48

    private func commitList(vm: RepositoryViewModel) -> some View {
        List(vm.graphRows, id: \.commit.id, selection: Binding(
            get: { vm.selectedCommitID },
            set: { vm.selectedCommitID = $0 }
        )) { row in
            HStack(spacing: 0) {
                CommitGraphView(row: row, rowHeight: Self.rowHeight)
                CommitRowView(commit: row.commit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.rowHeight)
            .tag(row.commit.id)
        }
        .listStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var commitDetail: some View {
        if let commit = vm?.selectedCommit {
            DiffView(
                commit: commit,
                diff: vm?.currentDiff,
                isLoading: vm?.isDiffLoading ?? false
            )
        } else {
            ContentUnavailableView(
                "Kein Commit ausgewählt",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Wähle einen Commit, um Details und Diff anzuzeigen.")
            )
        }
    }
}

// MARK: - Branch-Zeile

private struct BranchRowView: View {
    let branch: Branch
    let isLocal: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isCurrent ? "arrow.right.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(branch.isCurrent ? Color.accentColor : Color.secondary)
                .font(.callout)
            Text(isLocal ? branch.name : branch.shortName)
                .font(.callout)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
            Spacer()
            Text(branch.tipSha)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
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
            if !commit.refNames.isEmpty {
                refBadges
            }
            Text(commit.subject)
                .lineLimit(1)
                .font(.body)
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
