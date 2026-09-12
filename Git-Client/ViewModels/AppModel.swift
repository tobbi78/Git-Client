//
//  AppModel.swift
//  Git-Client
//

import SwiftUI
import Observation

@Observable
@MainActor
final class AppModel {
    private let store: BookmarkStore

    var bookmarkNodes: [BookmarkNode] = []
    var openedRepository: RepositoryBookmark? = nil
    var repositoryViewModel: RepositoryViewModel? = nil

    init() {
        self.store = BookmarkStore()
        bookmarkNodes = store.load()
    }

    /// Nur für Tests: erlaubt das Injizieren eines benutzerdefinierten BookmarkStore.
    init(store: BookmarkStore) {
        self.store = store
        bookmarkNodes = store.load()
    }

    // MARK: - Persistenz

    private func persist() {
        store.save(bookmarkNodes)
    }

    // MARK: - Lesezeichen-Mutationen

    func addRepository(name: String, path: URL) {
        let bookmark = RepositoryBookmark(name: name, path: path)
        bookmarkNodes.append(.repository(bookmark))
        persist()
    }

    /// Klont ein Remote-Repository und legt ein Bookmark an.
    /// Das Passwort/Token wird NICHT in bookmarks.json gespeichert — ausschließlich im Keychain.
    func cloneRepository(
        remoteURL: String,
        to localPath: URL,
        name: String,
        username: String?,
        password: String?
    ) async throws {
        let service = GitService(repositoryPath: localPath)
        try await service.clone(remoteURL: remoteURL, to: localPath, username: username, password: password)

        let bookmark = RepositoryBookmark(
            name: name,
            path: localPath,
            remoteURL: remoteURL,
            username: username.flatMap { $0.isEmpty ? nil : $0 }
        )
        if let pass = password, !pass.isEmpty {
            KeychainStore.save(pass, for: bookmark.id)
        }
        bookmarkNodes.append(.repository(bookmark))
        persist()
    }

    func addFolder(name: String) {
        bookmarkNodes.append(.folder(BookmarkFolder(name: name)))
        persist()
    }

    func rename(id: UUID, to newName: String) {
        bookmarkNodes.rename(id: id, to: newName)
        persist()
    }

    func move(id: UUID, toFolder folderID: UUID?) {
        bookmarkNodes.move(id: id, toFolder: folderID)
        persist()
    }

    func delete(id: UUID) {
        bookmarkNodes.remove(id: id)
        persist()
    }

    func updateRepositoryPath(id: UUID, newPath: URL) {
        bookmarkNodes.updateRepositoryPath(id: id, newPath: newPath)
        persist()
    }

    func promptUpdateRepositoryPath(id: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Neuen Pfad wählen"
        panel.message = "Wähle den neuen Speicherort des Git-Repositories"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dotGit = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: dotGit.path) else { return }
        updateRepositoryPath(id: id, newPath: url)
    }

    // MARK: - Navigation

    func openRepository(_ bookmark: RepositoryBookmark) {
        guard FileManager.default.fileExists(atPath: bookmark.path.path) else { return }
        openedRepository = bookmark
        let vm = RepositoryViewModel(repository: bookmark)
        repositoryViewModel = vm
        Task { await vm.load() }
    }

    func closeRepository() {
        openedRepository = nil
        repositoryViewModel = nil
    }

    // MARK: - NSOpenPanel

    func promptAddRepository() {
        let panel = NSOpenPanel()
        panel.title = "Repository auswählen"
        panel.message = "Wähle einen Ordner mit einem Git-Repository"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let dotGit = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: dotGit.path) else { return }

        addRepository(name: url.lastPathComponent, path: url)
    }
}
