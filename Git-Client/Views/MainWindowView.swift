//
//  MainWindowView.swift
//  Git-Client
//
//  Sourcetree-Layout:
//  ┌──────────────┬────────────────────────────────┐
//  │              │  Commit-Liste (oben)            │
//  │   Sidebar    ├────────────────────────────────│
//  │  (voll hoch) │  Diff / Detail (unten, breit)  │
//  └──────────────┴────────────────────────────────┘
//

import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppModel.self) private var appModel
    let repository: RepositoryBookmark

    @State private var isBranchesExpanded = false
    @State private var isTagsExpanded = false
    @State private var expandedRemotes: [String: Bool] = [:]

    // Breite der Graph-Spalte in der Commit-Liste; per Drag ziehbar
    @State private var graphColumnWidth: CGFloat = 200
    @State private var graphColumnWidthAtDragStart: CGFloat = 200

    private var vm: RepositoryViewModel? { appModel.repositoryViewModel }

    private var subtitleText: String {
        guard let vm else { return repository.path.path }
        if vm.isLoading { return "Wird geladen…" }
        let count = vm.commits.count
        let branch = vm.branches.first(where: \.isCurrent)?.name ?? ""
        if count == 0 { return repository.path.path }
        let commitLabel = count == 1 ? "1 Commit" : "\(count) Commits"
        return branch.isEmpty ? commitLabel : "\(branch)  ·  \(commitLabel)"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VSplitView {
                commitPane
                    .frame(minHeight: 200)
                commitDetail
                    .frame(minHeight: 180)
            }
            // Mindestbreite erzwingen, damit die Detail-Spalte beim Öffnen
            // sofort breit genug ist — unabhängig davon ob ein Commit ausgewählt ist.
            .frame(minWidth: 640, maxWidth: .infinity)
        }
        .navigationTitle(repository.name)
        .navigationSubtitle(subtitleText)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Repositories", systemImage: "chevron.left") {
                    appModel.closeRepository()
                }
                .help("Zurück zur Repository-Übersicht")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Neu laden", systemImage: "arrow.clockwise") {
                    Task { await vm?.load() }
                }
                .disabled(vm?.isLoading ?? true)
                .help("Commits, Branches und Tags neu laden")
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
        DisclosureGroup(isExpanded: $isBranchesExpanded) {
            if local.isEmpty {
                Text(vm == nil ? "Wird geladen…" : "Keine Branches")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(buildBranchTree(local, nameOf: \.name)) { node in
                    branchNodeRow(node)
                }
            }
        } label: {
            Label("Branches", systemImage: "arrow.triangle.branch")
                .font(.callout.weight(.semibold))
        }
    }

    @ViewBuilder
    private var remoteBranchesSections: some View {
        let remote = vm?.branches.filter { $0.isRemote } ?? []
        let remoteNames = Array(Set(remote.compactMap(\.remoteName))).sorted()
        ForEach(remoteNames, id: \.self) { remoteName in
            let branches = remote.filter { $0.remoteName == remoteName }
            DisclosureGroup(isExpanded: remoteBinding(for: remoteName)) {
                ForEach(buildBranchTree(branches, nameOf: \.shortName)) { node in
                    branchNodeRow(node)
                }
            } label: {
                Label("Remotes / \(remoteName)", systemImage: "network")
                    .font(.callout.weight(.semibold))
            }
        }
    }

    private func remoteBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { expandedRemotes[name] ?? true },
            set: { expandedRemotes[name] = $0 }
        )
    }

    @ViewBuilder
    private func branchNodeRow(_ node: BranchTreeNode) -> some View {
        switch node {
        case .leaf(let leaf):
            BranchRowView(branch: leaf.branch, displayName: leaf.displayName)
                .contentShape(Rectangle())
                .onTapGesture { vm?.selectCommit(bySha: leaf.branch.tipSha) }
        case .folder(let folderName, let children):
            DisclosureGroup {
                ForEach(children) { leaf in
                    BranchRowView(branch: leaf.branch, displayName: leaf.displayName)
                        .contentShape(Rectangle())
                        .onTapGesture { vm?.selectCommit(bySha: leaf.branch.tipSha) }
                }
            } label: {
                Label(folderName, systemImage: "folder")
                    .font(.callout)
            }
        }
    }

    private func buildBranchTree(_ branches: [Branch], nameOf: (Branch) -> String) -> [BranchTreeNode] {
        var folderMap: [String: [BranchLeaf]] = [:]
        var topLevel: [BranchLeaf] = []

        for branch in branches {
            let name = nameOf(branch)
            if let slashIdx = name.firstIndex(of: "/") {
                let folderName = String(name[..<slashIdx])
                let childName = String(name[name.index(after: slashIdx)...])
                folderMap[folderName, default: []].append(BranchLeaf(branch: branch, displayName: childName))
            } else {
                topLevel.append(BranchLeaf(branch: branch, displayName: name))
            }
        }

        var nodes = topLevel.map { BranchTreeNode.leaf($0) }
        for (folderName, children) in folderMap {
            nodes.append(.folder(name: folderName, children: children))
        }
        return nodes.sorted {
            $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        let allTags = vm?.tags ?? []
        if !allTags.isEmpty {
            DisclosureGroup(isExpanded: $isTagsExpanded) {
                ForEach(allTags) { tag in
                    Label(tag.name, systemImage: "tag")
                        .font(.callout)
                        .contentShape(Rectangle())
                        .onTapGesture { vm?.selectCommit(bySha: tag.targetSha) }
                }
            } label: {
                Label("Tags", systemImage: "tag")
                    .font(.callout.weight(.semibold))
            }
        }
    }

    // MARK: - Commit-Bereich (Sync-Leiste + Liste)

    @ViewBuilder
    private var commitPane: some View {
        VStack(spacing: 0) {
            if let vm {
                syncBar(vm: vm)
                Divider()
            }
            commitHistory
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func syncBar(vm: RepositoryViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await vm.fetch() }
            } label: {
                Label("Vom Server prüfen", systemImage: "arrow.down.circle")
            }
            .disabled(!vm.hasRemote || vm.isFetching || vm.isPulling || vm.isLoading)
            .help("Holt den aktuellen Stand vom Server (git fetch)")

            if vm.isFetching || vm.isPulling {
                ProgressView().controlSize(.small)
            }

            syncStatus(vm: vm)

            Spacer()

            Button {
                Task { await vm.pull() }
            } label: {
                Label("Aktualisieren", systemImage: "arrow.triangle.pull")
            }
            .disabled(!vm.hasUpstream || vm.behindCount == 0 || vm.isFetching || vm.isPulling || vm.isLoading)
            .help("Übernimmt die Server-Commits per Fast-Forward (git merge --ff-only)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func syncStatus(vm: RepositoryViewModel) -> some View {
        if let message = vm.remoteStatusMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if !vm.hasRemote {
            Text("Kein Remote")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !vm.hasUpstream {
            Text("Kein Upstream")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if vm.behindCount > 0 {
            HStack(spacing: 6) {
                Text("\(commitCountLabel(vm.behindCount)) auf dem Server")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                if vm.aheadCount > 0 {
                    Text("\(vm.aheadCount) voraus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 6) {
                Label("Aktuell", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vm.aheadCount > 0 {
                    Text("· \(vm.aheadCount) voraus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func commitCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Commit" : "\(count) Commits"
    }

    // MARK: - Commit-Liste

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

    // Höhere Zeilen geben Luft zwischen Commits; spacing: 0 hält die
    // Graph-Linien lückenlos verbunden (kein Gap zwischen Zeilen).
    private static let rowHeight: CGFloat = 56
    private static let rowSpacing: CGFloat = 0

    private func commitList(vm: RepositoryViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    // Hinweis, wenn ein Branch-Tip nicht in der geladenen Liste ist
                    if let msg = vm.branchJumpMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color(nsColor: .controlBackgroundColor))
                    }
                    ForEach(vm.graphRows, id: \.commit.id) { row in
                        let isSelected = vm.selectedCommitID == row.commit.id
                        HStack(spacing: 0) {
                            // GRAPH-SPALTE: feste (ziehbare) Breite, Graph wird rechts
                            // abgeschnitten wenn er breiter als die Spalte ist.
                            // Der Trenner daneben lässt sich ziehen, um mehr Lanes sichtbar
                            // zu machen.
                            CommitGraphView(row: row, rowHeight: Self.rowHeight)
                                .frame(width: graphColumnWidth, height: Self.rowHeight,
                                       alignment: .leading)
                                .clipped()

                            // ZIEHBARER TRENNER
                            graphColumnDivider

                            // BESCHREIBUNGS-SPALTE: füllt den restlichen Platz
                            CommitRowView(commit: row.commit)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                        .frame(height: Self.rowHeight)
                        .background(
                            isSelected
                                ? Color(nsColor: .selectedContentBackgroundColor)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { vm.selectedCommitID = row.commit.id }
                        .id(row.commit.id)
                    }
                }
            }
            // Scroll wird am Token ausgelöst, nicht an der ID — dadurch funktioniert
            // der Sprung auch wenn der Commit bereits ausgewählt war (z.B. origin/main
            // zeigt auf denselben Commit wie main, kein ID-Wechsel nötig).
            .frame(maxWidth: .infinity)
            .onChange(of: vm.scrollRequestToken) { _, _ in
                if let id = vm.scrollTargetID {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Schmaler ziehbarer Balken zwischen Graph- und Beschreibungs-Spalte.
    /// Da er in jeder Zeile erscheint und alle denselben `graphColumnWidth`-State
    /// teilen, wirkt er wie eine einzige durchgehende Trennlinie.
    private var graphColumnDivider: some View {
        Color.clear
            .frame(width: 7, height: Self.rowHeight)
            // Sichtbare 1pt-Linie in der Mitte des 7pt-Trefferbereichs
            .overlay(Color.secondary.opacity(0.25).frame(width: 1))
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = graphColumnWidthAtDragStart + value.translation.width
                        graphColumnWidth = min(max(proposed, 60), 600)
                    }
                    .onEnded { _ in
                        graphColumnWidthAtDragStart = graphColumnWidth
                    }
            )
    }

    // MARK: - Detail / Diff

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
    let displayName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isCurrent ? "arrow.right.circle.fill" : "arrow.triangle.branch")
                .foregroundStyle(branch.isCurrent ? Color.accentColor : Color.secondary)
                .font(.callout)
            Text(displayName)
                .font(.callout)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
            Spacer()
            Text(String(branch.tipSha.prefix(7)))
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
        VStack(alignment: .leading, spacing: 1) {
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
        .padding(.vertical, 1)
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

// MARK: - Branch-Baum-Typen

private struct BranchLeaf: Identifiable {
    let branch: Branch
    let displayName: String
    var id: String { branch.id }
}

private enum BranchTreeNode: Identifiable {
    case leaf(BranchLeaf)
    case folder(name: String, children: [BranchLeaf])

    var id: String {
        switch self {
        case .leaf(let l): return l.id
        case .folder(let name, _): return "folder:\(name)"
        }
    }

    var sortKey: String {
        switch self {
        case .leaf(let l): return l.displayName
        case .folder(let name, _): return name
        }
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
