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

    // MARK: - Auto-Refresh

    /// Aktueller Neuigkeiten-Stand pro Repository-ID.
    /// Von RepositoryBrowserView (Badge) und MainWindowView (Banner) beobachtet.
    private(set) var newCommitStatus: [UUID: RepoNewCommits] = [:]

    /// Lokale Kennzahlen pro Repository-ID für die Übersichtsliste.
    private(set) var repoStatus: [UUID: RepoStatus] = [:]

    /// Session-Baseline: Ref-Signatur zum Zeitpunkt der letzten „Gesehen"-Markierung.
    private var localBaseline: [UUID: [String: String]] = [:]

    /// Mappt Repository-ID → GitService für den Monitoring-Pfad.
    private var monitoringServices: [UUID: GitService] = [:]

    private let watcher = GitFolderWatcher()
    private var remotePollTask: Task<Void, Never>?

    init() {
        self.store = BookmarkStore()
        bookmarkNodes = store.load()
        startMonitoring()
    }

    /// Nur für Tests: erlaubt das Injizieren eines benutzerdefinierten BookmarkStore.
    init(store: BookmarkStore) {
        self.store = store
        bookmarkNodes = store.load()
        // Im Test-Init kein Monitoring starten (kein reales .git vorhanden).
    }

    // MARK: - Persistenz

    private func persist() {
        store.save(bookmarkNodes)
        // Monitoring nach jeder Bookmark-Änderung neu aufsetzen
        restartMonitoring()
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
        // Beim Öffnen als „gesehen" markieren, damit kein veralteter Badge erscheint.
        Task {
            await vm.load()
            await markRepositorySeen(bookmark.id)
        }
    }

    func closeRepository() {
        openedRepository = nil
        repositoryViewModel = nil
    }

    // MARK: - Auto-Refresh: öffentliche Schnittstelle

    /// Markiert ein Repository als „gesehen": setzt die lokale Baseline zurück
    /// und löscht den Neuigkeiten-Badge.
    func markRepositorySeen(_ id: UUID) async {
        let service = monitoringServices[id]
        let sig = await service?.localRefSignature() ?? [:]
        localBaseline[id] = sig
        newCommitStatus[id] = RepoNewCommits()
    }

    // MARK: - Auto-Refresh: Monitoring-Aufbau (intern)

    /// Startet das Monitoring neu (z.B. nach Bookmark-Änderungen).
    private func restartMonitoring() {
        remotePollTask?.cancel()
        remotePollTask = nil
        watcher.stop()
        startMonitoring()
    }

    private func startMonitoring() {
        guard AppSettings.autoRefreshEnabled else { return }

        let repos = bookmarkNodes.allRepositories().filter {
            FileManager.default.fileExists(atPath: $0.path.appendingPathComponent(".git").path)
        }
        guard !repos.isEmpty else { return }

        // Services für alle Repos anlegen/aktualisieren
        monitoringServices = [:]
        for repo in repos {
            monitoringServices[repo.id] = GitService(repositoryPath: repo.path)
        }

        // Baselines und lokale Kennzahlen asynchron setzen (beim ersten Start)
        let reposForBaseline = repos
        Task {
            for repo in reposForBaseline {
                guard localBaseline[repo.id] == nil else { continue }
                let sig = await monitoringServices[repo.id]?.localRefSignature() ?? [:]
                localBaseline[repo.id] = sig
                if let service = monitoringServices[repo.id] {
                    await refreshLocalStatus(repoID: repo.id, service: service)
                }
            }
        }

        // FSEvent-Watcher starten
        let dotGitPaths = repos.map { $0.path.appendingPathComponent(".git") }
        // Pfad→ID-Map für den Callback (Wertetyp-Copy für Sendable)
        let pathToID: [String: UUID] = Dictionary(
            uniqueKeysWithValues: repos.map { ($0.path.appendingPathComponent(".git").path, $0.id) }
        )

        watcher.update(paths: dotGitPaths) { [weak self] affectedDotGits in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for dotGit in affectedDotGits {
                    guard let repoID = pathToID[dotGit.path],
                          let service = self.monitoringServices[repoID] else { continue }
                    let newSig = await service.localRefSignature()
                    let baseline = self.localBaseline[repoID] ?? [:]
                    var status = self.newCommitStatus[repoID] ?? RepoNewCommits()
                    status.hasLocalChanges = (newSig != baseline)
                    self.newCommitStatus[repoID] = status
                    await self.refreshLocalStatus(repoID: repoID, service: service)
                }
            }
        }

        // Remote-Poll-Task starten
        let interval = AppSettings.remotePollInterval
        guard interval > 0 else { return }
        let reposForPoll = repos
        remotePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.pollRemotes(repos: reposForPoll)
            }
        }
    }

    private func refreshLocalStatus(repoID: UUID, service: GitService) async {
        var st = repoStatus[repoID] ?? RepoStatus()
        st.currentBranch = await service.currentBranch()
        st.hasUncommittedChanges = await service.hasUncommittedChanges()
        st.lastCommitDate = await service.lastCommitDate()
        if let ab = try? await service.aheadBehind() {
            st.hasUpstream = true
            st.aheadCount = ab.ahead
            st.behindCount = ab.behind
        } else {
            st.hasUpstream = false
        }
        repoStatus[repoID] = st
    }

    // TODO: pollRemotes() überspringt Repositories ohne gespeicherte remoteURL, d.h.
    // über "Repository hinzufügen" eingebundene Repos bekommen nie einen automatischen
    // Remote-Check (nur lokale FSEvents-Erkennung) — der manuelle "Vom Server prüfen"-Button
    // (RepositoryViewModel.fetch) funktioniert für diese Repos aber problemlos über den
    // lokal konfigurierten Remote-Namen. Aktuell bewusst so gelassen (Stand 2026-09-15);
    // falls gewünscht: guard auf GitService.firstRemoteName() statt bookmark.remoteURL
    // umstellen, analog zum manuellen Fetch-Pfad.
    private func pollRemotes(repos: [RepositoryBookmark]) async {
        for repo in repos {
            guard !Task.isCancelled else { break }
            guard let service = monitoringServices[repo.id] else { continue }
            guard let remoteURL = repo.remoteURL, !remoteURL.isEmpty else { continue }

            let password = KeychainStore.load(for: repo.id)
            do {
                try await service.fetch(remoteURL: remoteURL, username: repo.username, password: password)
                if let ab = try? await service.aheadBehind() {
                    var st = repoStatus[repo.id] ?? RepoStatus()
                    st.hasUpstream = true
                    st.aheadCount = ab.ahead
                    st.behindCount = ab.behind
                    repoStatus[repo.id] = st
                    var news = newCommitStatus[repo.id] ?? RepoNewCommits()
                    news.remoteAheadBranches = ab.behind > 0 ? 1 : 0
                    newCommitStatus[repo.id] = news
                }
            } catch {
                // Offline, fehlende Credentials etc. — still ignorieren
            }
        }
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
