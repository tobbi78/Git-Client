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
    private let settings: AppSettings

    var bookmarkNodes: [BookmarkNode] = []
    var openedRepository: RepositoryBookmark? = nil
    var repositoryViewModel: RepositoryViewModel? = nil

    /// Sichtbarkeit der Befehlspalette (⌘K) — an/aus, unabhängig davon, ob ein
    /// Repository geöffnet ist. Siehe CommandPaletteView.
    var isCommandPaletteOpen = false

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

    /// Repo-IDs, für die `refreshLocalStatus` aktuell läuft — verhindert, dass ein
    /// FSEvent, das durch den eigenen `git status`-Aufruf (Index-Refresh) ausgelöst
    /// wird, eine zweite, überlappende Status-Abfrage für dasselbe Repo startet.
    /// Ohne diese Sperre können zwei gleichzeitige `git status`-Prozesse auf
    /// `.git/index.lock` kollidieren — beobachtet bei sehr großen Repos, bei denen
    /// der Status-Scan lange genug dauert, dass sich aufeinanderfolgende
    /// FSEvent-Bursts überlappen.
    private var refreshInFlight: Set<UUID> = []

    private let watcher = GitFolderWatcher()
    private var remotePollTask: Task<Void, Never>?

    init(settings: AppSettings = .shared) {
        self.store = BookmarkStore()
        self.settings = settings
        bookmarkNodes = store.load()
        startMonitoring()
    }

    /// Nur für Tests: erlaubt das Injizieren eines benutzerdefinierten BookmarkStore.
    init(store: BookmarkStore, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
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

    func setPinned(id: UUID, _ pinned: Bool) {
        bookmarkNodes.setPinned(id: id, pinned)
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
        let vm = RepositoryViewModel(repository: bookmark, settings: settings)
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
        guard settings.autoRefreshEnabled else { return }

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
        let interval = settings.remotePollInterval
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

    /// Zugriffsebene bewusst nicht `private`: Tests rufen diese Methode direkt auf, um
    /// echte Nebenläufigkeit (zwei gleichzeitige Aufrufe für dasselbe Repo) ohne Warten
    /// auf einen echten FSEvent-Burst zu erzeugen — analog zum Testzugriffspunkt
    /// `pollRemotes`.
    func refreshLocalStatus(repoID: UUID, service: GitService) async {
        // Verhindert überlappende `git status`-Aufrufe für dasselbe Repo (siehe
        // Kommentar an `refreshInFlight`) — ein bereits laufender Refresh deckt den
        // aktuellen Stand ohnehin ab, ein zweiter gleichzeitiger Aufruf wird verworfen.
        guard !refreshInFlight.contains(repoID) else { return }

        // Verhindert eine andere Art von Kollision: Pull/Hard-Reset/Checkout halten
        // `.git/index.lock` über ihre gesamte Laufzeit (bei großen Resets mehrere
        // Sekunden). Die dabei entstehenden FSEvent-Bursts würden ohne diesen Guard
        // wiederholt einen `git status`-Aufruf anstoßen, der auf das noch gehaltene
        // Lock trifft und fehlschlägt. Sobald die Operation fertig ist, greift der
        // nächste (durch denselben Burst bereits angestoßene) Refresh wie gewohnt.
        if repoID == openedRepository?.id, repositoryViewModel?.isPerformingGitWriteOperation == true {
            return
        }

        refreshInFlight.insert(repoID)
        defer { refreshInFlight.remove(repoID) }

        // Branch, Ahead/Behind und unkommittierte Änderungen in einem Subprozess statt
        // drei getrennten (siehe GitService.localStatusSnapshot) — bei Fehler bleibt
        // der zuletzt bekannte Stand erhalten statt eines teilweise geleerten Status.
        var st = await service.localStatusSnapshot() ?? (repoStatus[repoID] ?? RepoStatus())
        st.pathExists = FileManager.default.fileExists(atPath: service.repositoryPath.path)
        st.lastCommitDate = await service.lastCommitDate()
        repoStatus[repoID] = st
    }

    // Geklonte Repos nutzen die im Bookmark gespeicherte remoteURL samt Keychain-Credentials;
    // über "Repository hinzufügen" eingebundene Repos haben keine und fallen in GitService
    // (remoteHeads/fetch) auf den lokal konfigurierten Remote zurück — analog zum manuellen
    // Fetch-Pfad (RepositoryViewModel.fetch). Repos ganz ohne Remote werden über
    // `remoteName()` übersprungen.
    //
    // Zugriffsebene bewusst nicht `private`: Tests rufen diese Methode direkt auf, um nicht
    // auf den remotePollInterval-Timer (Minimum 60s) warten zu müssen — analog zum
    // Testzugriffspunkt `init(store:)`. Kein neuer öffentlicher API-Vertrag, nur ein
    // Testzugriffspunkt innerhalb des App-Targets.
    func pollRemotes(repos: [RepositoryBookmark]) async {
        for repo in repos {
            guard !Task.isCancelled else { break }
            guard let service = monitoringServices[repo.id] else { continue }

            let password = KeychainStore.load(for: repo.id)
            do {
                // Günstige Vorab-Prüfung: nur Server-Refs abfragen (ls-remote), kein
                // Objekt-Download. Nur wenn sich dabei tatsächlich etwas geändert hat,
                // folgt unten der teure echte Fetch.
                guard let remoteName = try await service.remoteName() else { continue }
                let localSig = await service.localRefSignature()
                let heads = try await service.remoteHeads(remoteURL: repo.remoteURL, username: repo.username, password: password)
                let aheadBranches = RepoRefSnapshot.remoteAhead(localSignature: localSig, remoteHeads: heads, remoteName: remoteName)

                var news = newCommitStatus[repo.id] ?? RepoNewCommits()
                news.remoteAheadBranches = aheadBranches
                newCommitStatus[repo.id] = news

                guard aheadBranches > 0 else { continue }

                // Es gibt tatsächlich Neuigkeiten — jetzt lohnt sich der echte Fetch, um
                // die Objekte zu holen und Ahead/Behind exakt zu aktualisieren.
                try await service.fetch(remoteURL: repo.remoteURL, username: repo.username, password: password)
                if let ab = try? await service.aheadBehind() {
                    var st = repoStatus[repo.id] ?? RepoStatus()
                    st.hasUpstream = true
                    st.aheadCount = ab.ahead
                    st.behindCount = ab.behind
                    repoStatus[repo.id] = st
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
