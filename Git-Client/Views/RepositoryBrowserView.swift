//
//  RepositoryBrowserView.swift
//  Git-Client
//
//  Sourcetree-artiger Lesezeichen-Browser.
//
//  Baum-Darstellung via ScrollView + rekursivem BookmarkNodeView (KEIN NSOutlineView).
//  NSOutlineView (List/OutlineGroup auf macOS) fängt Mouse-Events vor SwiftUI ab.
//
//  Drag & Drop: .draggable/.dropDestination (modernes Transferable-API), kein NSItemProvider.
//

import SwiftUI
import UniformTypeIdentifiers

struct RepositoryBrowserView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isCloning = false
    @State private var isAddingFolder = false
    @State private var newFolderName = ""
    @State private var isRenaming = false
    @State private var renamingID: UUID? = nil
    @State private var renameText = ""
    @State private var dragTargetFolderID: UUID? = nil

    var body: some View {
        NavigationStack {
            Group {
                if appModel.bookmarkNodes.isEmpty {
                    emptyState
                } else {
                    bookmarkTree
                }
            }
            .navigationTitle("Repositories")
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $isCloning) { CloneRepositoryView() }
        .sheet(isPresented: $isAddingFolder) { newFolderSheet }
        .sheet(isPresented: $isRenaming) { renameSheet }
    }

    // MARK: - Leere Ansicht

    private var emptyState: some View {
        ContentUnavailableView(
            "Keine Repositories",
            systemImage: "externaldrive.badge.questionmark",
            description: Text("Klicke auf \"+\" um ein Git-Repository hinzuzufügen.")
        )
    }

    // MARK: - Baumansicht (kein NSOutlineView)

    private var bookmarkTree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(appModel.bookmarkNodes) { node in
                    BookmarkNodeView(
                        node: node,
                        depth: 0,
                        dragTargetFolderID: $dragTargetFolderID,
                        onRequestRename: { id, name in
                            renamingID = id
                            renameText = name
                            isRenaming = true
                        }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Repository hinzufügen", systemImage: "plus") {
                appModel.promptAddRepository()
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Klonen", systemImage: "arrow.down.to.line.circle") {
                isCloning = true
            }
            .help("Remote-Repository klonen")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Neuer Ordner", systemImage: "folder.badge.plus") {
                isAddingFolder = true
            }
        }
    }

    // MARK: - Sheets

    private var newFolderSheet: some View {
        VStack(spacing: 20) {
            Text("Neuer Ordner").font(.headline)
            TextField("Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)
            HStack {
                Button("Abbrechen") { isAddingFolder = false; newFolderName = "" }
                    .keyboardShortcut(.cancelAction)
                Button("Erstellen") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { appModel.addFolder(name: name) }
                    isAddingFolder = false; newFolderName = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }

    private var renameSheet: some View {
        VStack(spacing: 20) {
            Text("Umbenennen").font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)
            HStack {
                Button("Abbrechen") { isRenaming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, let id = renamingID { appModel.rename(id: id, to: name) }
                    isRenaming = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
    }
}

// MARK: - Rekursiver Baumknoten

private struct BookmarkNodeView: View {
    let node: BookmarkNode
    let depth: Int
    @Binding var dragTargetFolderID: UUID?
    let onRequestRename: (UUID, String) -> Void

    @State private var isExpanded = true
    @State private var isHovered = false
    @Environment(AppModel.self) private var appModel

    private static let rowPaddingV: CGFloat = 5
    private static let indentPerLevel: CGFloat = 18

    var body: some View {
        switch node {
        case .repository(let repo):
            repoRow(repo)
        case .folder(let folder):
            folderSection(folder)
        }
    }

    // MARK: - Repository-Zeile

    private func repoRow(_ repo: RepositoryBookmark) -> some View {
        let pathExists = FileManager.default.fileExists(atPath: repo.path.path)
        return HStack(spacing: 8) {
            Image(systemName: pathExists ? "externaldrive" : "externaldrive.badge.exclamationmark")
                .font(.callout)
                .foregroundStyle(pathExists ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(pathExists ? Color.primary : Color.secondary)
                Text(repo.path.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if pathExists, let st = appModel.repoStatus[repo.id] {
                    repoStatusRow(st)
                }
            }
            Spacer()
            // Auto-Refresh-Badge: neue Commits vorhanden
            if pathExists, let news = appModel.newCommitStatus[repo.id], news.hasNews {
                let helpText: String = {
                    var parts: [String] = []
                    if news.hasLocalChanges { parts.append("Neue lokale Commits") }
                    if news.remoteAheadBranches > 0 {
                        let label = news.remoteAheadBranches == 1
                            ? "1 Branch auf dem Server voraus"
                            : "\(news.remoteAheadBranches) Branches auf dem Server voraus"
                        parts.append(label)
                    }
                    return parts.joined(separator: " · ")
                }()
                HStack(spacing: 3) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                    Text("neu")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .help(helpText)
            }
            if !pathExists {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Repository-Ordner nicht gefunden. Pfad im Kontextmenü aktualisieren.")
            }
        }
        .padding(.leading, leadingPadding + Self.indentPerLevel)
        .padding(.trailing, 8)
        .padding(.vertical, Self.rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered && pathExists
                      ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.35)
                      : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { if pathExists { appModel.openRepository(repo) } }
        .draggable(node.id.uuidString)
        .contextMenu { repoContextMenu(node: node, repo: repo, pathExists: pathExists) }
    }

    // MARK: - Repository-Statuszeile

    @ViewBuilder
    private func repoStatusRow(_ st: RepoStatus) -> some View {
        HStack(spacing: 5) {
            if let branch = st.currentBranch {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                Text(branch)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            if st.isBehind {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .medium))
                Text("\(st.behindCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .help("\(st.behindCount) Commits auf dem Server")
            }
            if st.aheadCount > 0 {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9))
                Text("\(st.aheadCount)")
                    .font(.system(size: 10))
                    .help("\(st.aheadCount) lokale Commits noch nicht gepusht")
            }
            if st.hasUncommittedChanges {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 9))
                    .help("Lokale Änderungen")
            }
            if let date = st.lastCommitDate {
                Spacer()
                Text(RepoStatus.relativeLabel(from: date))
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Ordner-Sektion

    private func folderSection(_ folder: BookmarkFolder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            folderHeader(folder)
            if isExpanded {
                ForEach(folder.children) { child in
                    BookmarkNodeView(
                        node: child,
                        depth: depth + 1,
                        dragTargetFolderID: $dragTargetFolderID,
                        onRequestRename: onRequestRename
                    )
                }
            }
        }
    }

    private func folderHeader(_ folder: BookmarkFolder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Image(systemName: "folder")
                .font(.callout)
                .foregroundStyle(dragTargetFolderID == folder.id ? Color.accentColor : Color.secondary)
            Text(folder.name)
                .font(.callout)
                .fontWeight(dragTargetFolderID == folder.id ? .semibold : .regular)
            Spacer()
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, 8)
        .padding(.vertical, Self.rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dragTargetFolderID == folder.id
                      ? Color.accentColor.opacity(0.15)
                      : isHovered
                        ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.35)
                        : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
        // Drop-Ziel: akzeptiert UUID-Strings (von .draggable oben)
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let uuid = UUID(uuidString: uuidString) else { return false }
            appModel.move(id: uuid, toFolder: folder.id)
            return true
        } isTargeted: { targeted in
            dragTargetFolderID = targeted ? folder.id : nil
        }
        .contextMenu { folderContextMenu(node: .folder(folder)) }
    }

    // MARK: - Kontextmenüs (getrennt, kein let in ViewBuilder)

    @ViewBuilder
    private func repoContextMenu(node: BookmarkNode, repo: RepositoryBookmark, pathExists: Bool) -> some View {
        Button("Umbenennen") {
            onRequestRename(node.id, node.displayName)
        }

        moveMenu(for: node)

        if pathExists {
            Button("Im Finder zeigen") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path.path)
            }
        } else {
            Button("Pfad aktualisieren…") {
                appModel.promptUpdateRepositoryPath(id: repo.id)
            }
        }

        Divider()

        Button("Löschen", role: .destructive) {
            appModel.delete(id: node.id)
        }
    }

    @ViewBuilder
    private func folderContextMenu(node: BookmarkNode) -> some View {
        Button("Umbenennen") {
            onRequestRename(node.id, node.displayName)
        }

        Divider()

        Button("Löschen", role: .destructive) {
            appModel.delete(id: node.id)
        }
    }

    // Eigenständige View-func damit kein `let` in @ViewBuilder nötig ist
    private func moveMenu(for node: BookmarkNode) -> some View {
        let folders = appModel.bookmarkNodes.allFolders()
        return Menu("In Ordner verschieben") {
            Button("Auf Root-Ebene") {
                appModel.move(id: node.id, toFolder: nil)
            }
            if !folders.isEmpty {
                Divider()
                ForEach(folders) { folder in
                    Button(folder.name) {
                        appModel.move(id: node.id, toFolder: folder.id)
                    }
                }
            }
        }
    }

    // MARK: - Hilfsmethode

    private var leadingPadding: CGFloat {
        CGFloat(depth) * Self.indentPerLevel + 8
    }
}

#Preview {
    RepositoryBrowserView()
        .environment({
            let m = AppModel()
            m.addFolder(name: "Arbeit")
            m.addRepository(name: "Git-Client", path: URL(fileURLWithPath: "/Users/Tobias.Florian/Documents/Softwareentwicklung/Swift/Git-Client"))
            return m
        }())
}
