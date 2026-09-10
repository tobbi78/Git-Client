//
//  RepositoryBrowserView.swift
//  Git-Client
//
//  Sourcetree-artiger Lesezeichen-Browser.
//
//  Drag & Drop: OutlineGroup innerhalb eines normalen List, weil List(children:) intern
//  NSOutlineView nutzt, der .onDrag auf SwiftUI-Zeilen abfängt. OutlineGroup verwendet
//  DisclosureGroup und gibt uns volle Kontrolle über Drag-Gesten.
//
//  Fallback: Kontextmenü „In Ordner verschieben" funktioniert immer zuverlässig.
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

    private static let dragType = UTType(exportedAs: "de.tobias.florian.git-client.bookmark-drag")

    var body: some View {
        NavigationStack {
            Group {
                if appModel.bookmarkNodes.isEmpty {
                    emptyState
                } else {
                    bookmarkList
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

    // MARK: - Liste via OutlineGroup (kein NSOutlineView-Wrapper → .onDrag funktioniert)

    private var bookmarkList: some View {
        List {
            OutlineGroup(appModel.bookmarkNodes, children: \.children) { node in
                bookmarkRow(for: node)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Zeilen

    @ViewBuilder
    private func bookmarkRow(for node: BookmarkNode) -> some View {
        switch node {
        case .repository(let repo):
            BookmarkRowView(node: node)
                .contentShape(Rectangle())
                .onTapGesture { appModel.openRepository(repo) }
                .onDrag {
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(
                        forTypeIdentifier: Self.dragType.identifier,
                        visibility: .all
                    ) { completion in
                        completion(node.id.uuidString.data(using: .utf8), nil)
                        return nil
                    }
                    return provider
                }
                .contextMenu { contextMenuItems(for: node) }

        case .folder(let folder):
            BookmarkRowView(node: node)
                .background {
                    if dragTargetFolderID == folder.id {
                        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12))
                    }
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
                .contextMenu { contextMenuItems(for: node) }
        }
    }

    // MARK: - Kontextmenü

    @ViewBuilder
    private func contextMenuItems(for node: BookmarkNode) -> some View {
        Button("Umbenennen") {
            renamingID = node.id
            renameText = node.displayName
            isRenaming = true
        }

        // Zuverlässiger Fallback für das Verschieben in einen Ordner
        let folders = appModel.bookmarkNodes.allFolders()
        if case .repository = node, !folders.isEmpty {
            Menu("In Ordner verschieben") {
                Button("Auf Root-Ebene") {
                    appModel.move(id: node.id, toFolder: nil)
                }
                Divider()
                ForEach(folders) { folder in
                    Button(folder.name) {
                        appModel.move(id: node.id, toFolder: folder.id)
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

// MARK: - Zeilen-View

private struct BookmarkRowView: View {
    let node: BookmarkNode

    var body: some View {
        switch node {
        case .folder(let folder):
            Label(folder.name, systemImage: "folder")
        case .repository(let repo):
            VStack(alignment: .leading, spacing: 2) {
                Label(repo.name, systemImage: "externaldrive")
                Text(repo.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
