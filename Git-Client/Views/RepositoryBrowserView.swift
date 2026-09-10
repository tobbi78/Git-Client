//
//  RepositoryBrowserView.swift
//  Git-Client
//
//  Sourcetree-artiger Lesezeichen-Browser.
//
//  Baum-Darstellung via ScrollView + rekursivem BookmarkNodeView (KEIN NSOutlineView).
//  NSOutlineView (List/OutlineGroup auf macOS) fängt Mouse-Events vor SwiftUI ab und
//  verhindert so zuverlässiges Drag & Drop. Der eigene ScrollView-Baum umgeht das komplett.
//

import SwiftUI
import UniformTypeIdentifiers

struct RepositoryBrowserView: View {
    @Environment(AppModel.self) private var appModel

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

    private static let dragType = UTType(exportedAs: "de.tobias.florian.git-client.bookmark-drag")
    private static let indent: CGFloat = 18
    private static let rowPaddingV: CGFloat = 5

    var body: some View {
        switch node {
        case .repository(let repo):
            repoRow(repo)
        case .folder(let folder):
            folderSection(folder)
        }
    }

    // MARK: Repository-Zeile

    private func repoRow(_ repo: RepositoryBookmark) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(repo.path.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.leading, leadingPadding + Self.indent)
        .padding(.trailing, 8)
        .padding(.vertical, Self.rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.35) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { appModel.openRepository(repo) }
        .onDrag { dragProvider(for: node.id) }
        .contextMenu { contextMenuItems(for: node) }
    }

    // MARK: Ordner-Sektion

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
                      : isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.35) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
        .onDrop(
            of: [Self.dragType],
            isTargeted: Binding(
                get: { dragTargetFolderID == folder.id },
                set: { active in dragTargetFolderID = active ? folder.id : nil }
            )
        ) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: Self.dragType.identifier) { data, _ in
                guard let data,
                      let str = String(data: data, encoding: .utf8),
                      let uuid = UUID(uuidString: str) else { return }
                Task { @MainActor in appModel.move(id: uuid, toFolder: folder.id) }
            }
            return true
        }
        .contextMenu { contextMenuItems(for: .folder(folder)) }
    }

    // MARK: Hilfsmethoden

    private var leadingPadding: CGFloat {
        CGFloat(depth) * Self.indent + 8
    }

    private func dragProvider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.dragType.identifier,
            visibility: .all
        ) { completion in
            completion(id.uuidString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    @ViewBuilder
    private func contextMenuItems(for node: BookmarkNode) -> some View {
        Button("Umbenennen") {
            onRequestRename(node.id, node.displayName)
        }

        if case .repository = node {
            let folders = appModel.bookmarkNodes.allFolders()
            Menu("In Ordner verschieben") {
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

        if case .repository(let repo) = node {
            Button("Im Finder zeigen") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path.path)
            }
        }

        Divider()

        Button("Löschen", role: .destructive) {
            appModel.delete(id: node.id)
        }
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
