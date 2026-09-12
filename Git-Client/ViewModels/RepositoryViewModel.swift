//
//  RepositoryViewModel.swift
//  Git-Client
//
//  Hält den Ladezustand und die geladenen Daten (Commits, Branches, Tags)
//  für das aktuell geöffnete Repository.
//

import Foundation
import Observation

@Observable
@MainActor
final class RepositoryViewModel {
    let repository: RepositoryBookmark
    private let service: GitService

    var commits: [Commit] = []
    var graphRows: [GraphRow] = []
    var branches: [Branch] = []
    var tags: [GitTag] = []
    var isLoading = false
    var isLoadingMore = false   // Nachlade-Vorgang läuft
    var canLoadMore = true      // false sobald git log < pageSize zurückgibt
    var errorMessage: String? = nil

    /// Anzahl der per git-log-Paginierung geladenen Commits (Basis für --skip).
    /// Nicht identisch mit commits.count, da loadMissingBranchTips weitere Commits injiziert.
    private var pagedCount = 0
    private var pageSize: Int { AppSettings.commitBatchSize }

    // Remote-Sync-Zustand
    var behindCount = 0          // Commits auf dem Server, die lokal fehlen
    var aheadCount = 0           // lokale Commits, die noch nicht gepusht sind
    var hasRemote = false
    var hasUpstream = false
    var isFetching = false
    var isPulling = false
    var remoteStatusMessage: String? = nil

    // MARK: - Suche / Filter

    var searchCriteria = CommitSearchCriteria()
    private(set) var searchResults: [Commit] = []
    private(set) var searchGraphRows: [GraphRow] = []
    var isSearching = false
    private var searchPagedCount = 0
    private var searchCanLoadMore = true
    private var searchTask: Task<Void, Never>?

    /// true wenn mindestens ein Suchkriterium aktiv ist.
    var isSearchActive: Bool { searchCriteria.isActive }

    /// Die aktuell sichtbaren Graph-Zeilen (Suchtreffer oder normale Liste).
    var visibleGraphRows: [GraphRow] { isSearchActive ? searchGraphRows : graphRows }

    /// Ob weitere Einträge nachgeladen werden können (je nach Modus).
    var visibleCanLoadMore: Bool { isSearchActive ? searchCanLoadMore : canLoadMore }

    var selectedCommitID: String? = nil {
        didSet { if let id = selectedCommitID { Task { await loadDiff(for: id) } } }
    }

    var selectedCommit: Commit? {
        guard let id = selectedCommitID else { return nil }
        if isSearchActive {
            return searchResults.first { $0.id == id } ?? commits.first { $0.id == id }
        }
        return commits.first { $0.id == id }
    }

    var currentDiff: CommitDiff? = nil
    var isDiffLoading = false

    // Expliziter Scroll-Trigger: erhöht sich bei jedem Branch-/Tag-Klick,
    // auch wenn der Commit bereits ausgewählt war (gleiche ID).
    private(set) var scrollRequestToken = 0
    var scrollTargetID: String? = nil

    // Dezente Rückmeldung, wenn der Tip-Commit nicht in der geladenen Liste ist.
    var branchJumpMessage: String? = nil

    init(repository: RepositoryBookmark) {
        self.repository = repository
        self.service = GitService(repositoryPath: repository.path)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        // Paging-State zurücksetzen
        pagedCount = 0
        canLoadMore = true
        do {
            // Commits, Branches und Tags parallel laden
            async let commitsTask = service.loadCommits(limit: pageSize, skip: 0)
            async let branchesTask = service.loadBranches()
            async let tagsTask = service.loadTags()
            let firstPage = try await commitsTask
            commits = firstPage
            branches = try await branchesTask
            tags = try await tagsTask
            pagedCount = firstPage.count
            // Weniger als pageSize zurück → keine weitere Seite vorhanden
            canLoadMore = (firstPage.count == pageSize)
            // Branch-Tips, die außerhalb des geladenen Fensters liegen, einzeln nachladen.
            await loadMissingBranchTips()
            graphRows = CommitGraphBuilder.build(from: commits)
        } catch {
            errorMessage = error.localizedDescription
        }
        hasRemote = await service.hasRemote()
        await refreshAheadBehind()
        isLoading = false
    }

    /// Lädt die nächste Seite nach — normale Liste oder Suchtreffer, je nach Modus.
    func loadMore() async {
        if isSearchActive {
            guard searchCanLoadMore, !isSearching else { return }
            await performSearch(reset: false)
            return
        }
        guard canLoadMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await service.loadCommits(limit: pageSize, skip: pagedCount)
            pagedCount += next.count
            if next.count < pageSize { canLoadMore = false }
            // Deduplizieren: Branch-Tips, die bereits per loadMissingBranchTips injiziert wurden
            let existing = Set(commits.map(\.sha))
            let unique = next.filter { !existing.contains($0.sha) }
            guard !unique.isEmpty else {
                if next.count < pageSize { canLoadMore = false }
                return
            }
            commits.append(contentsOf: unique)
            commits.sort { $0.date > $1.date }
            graphRows = CommitGraphBuilder.build(from: commits)
        } catch {
            // Fehler still ignorieren — canLoadMore bleibt true für erneuten Versuch beim nächsten Scroll
        }
    }

    /// Lädt Branch-Tip-Commits nach, die noch nicht in `commits` enthalten sind.
    private func loadMissingBranchTips() async {
        let loadedSHAs = Set(commits.map(\.sha))
        let missingTips = branches
            .map(\.tipSha)
            .filter { !loadedSHAs.contains($0) }
        guard !missingTips.isEmpty else { return }

        var additional: [Commit] = []
        // Parallel nachladen — jeder Aufruf ist ein schnelles lokales `git log -1`
        await withTaskGroup(of: Commit?.self) { group in
            for sha in missingTips {
                group.addTask { await self.service.loadSingleCommit(sha: sha) }
            }
            for await commit in group {
                if let c = commit { additional.append(c) }
            }
        }
        guard !additional.isEmpty else { return }
        // Deduplizieren, nach Datum einordnen, damit der Graph-Algorithmus korrekte Reihenfolge hat
        let existing = Set(commits.map(\.sha))
        let unique = additional.filter { !existing.contains($0.sha) }
        commits.append(contentsOf: unique)
        commits.sort { $0.date > $1.date }
    }

    // MARK: - Remote-Sync

    /// Holt den aktuellen Stand vom Server und aktualisiert die Anzeige,
    /// damit neu geholte Remote-Commits im Graph erscheinen.
    func fetch() async {
        guard !isFetching, !isPulling else { return }
        isFetching = true
        remoteStatusMessage = nil
        do {
            let creds = credentials()
            try await service.fetch(remoteURL: creds.remoteURL, username: creds.username, password: creds.password)
            await load()
        } catch {
            remoteStatusMessage = error.localizedDescription
        }
        isFetching = false
    }

    /// Übernimmt die Remote-Commits per Fast-Forward in den aktuellen Branch.
    func pull() async {
        guard !isFetching, !isPulling else { return }
        isPulling = true
        remoteStatusMessage = nil
        do {
            try await service.fastForward()
            await load()
        } catch {
            remoteStatusMessage = error.localizedDescription
        }
        isPulling = false
    }

    private func refreshAheadBehind() async {
        do {
            if let counts = try await service.aheadBehind() {
                hasUpstream = true
                aheadCount = counts.ahead
                behindCount = counts.behind
            } else {
                hasUpstream = false
                aheadCount = 0
                behindCount = 0
            }
        } catch {
            hasUpstream = false
            aheadCount = 0
            behindCount = 0
        }
    }

    // MARK: - Suche (Such-State, Debounce, Paging)

    /// Aktualisiert die Suchkriterien und löst (entprellt) eine neue Suche aus.
    /// Bei leeren Kriterien wird der Such-State sofort geleert.
    func updateSearch(_ new: CommitSearchCriteria) {
        searchCriteria = new
        searchTask?.cancel()
        guard new.isActive else {
            searchResults = []
            searchGraphRows = []
            searchCanLoadMore = true
            searchPagedCount = 0
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(reset: true)
        }
    }

    private func performSearch(reset: Bool) async {
        if reset {
            searchPagedCount = 0
            searchCanLoadMore = true
        }
        guard searchCanLoadMore else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let pageSize = AppSettings.commitBatchSize
            let page = try await service.searchCommits(
                criteria: searchCriteria,
                limit: pageSize,
                skip: searchPagedCount
            )
            if reset {
                searchResults = page
            } else {
                let existing = Set(searchResults.map(\.sha))
                let unique = page.filter { !existing.contains($0.sha) }
                searchResults.append(contentsOf: unique)
                searchResults.sort { $0.date > $1.date }
            }
            searchPagedCount += page.count
            if page.count < pageSize { searchCanLoadMore = false }
            searchGraphRows = CommitGraphBuilder.build(from: searchResults)
        } catch {
            // Suchfehler still ignorieren — leeres Ergebnis bleibt sichtbar
        }
    }

    /// Liest die (nicht-geheimen) Remote-Angaben aus dem Bookmark und das Passwort/Token
    /// ausschließlich aus dem Keychain (strikt an `repository.id` gebunden).
    private func credentials() -> (remoteURL: String?, username: String?, password: String?) {
        (
            remoteURL: repository.remoteURL,
            username: repository.username,
            password: KeychainStore.load(for: repository.id)
        )
    }

    /// Wählt den Commit mit dem gegebenen SHA (voll oder kurz) aus und scrollt dorthin.
    /// Scrollt auch dann, wenn der Commit bereits ausgewählt war (wiederholter Klick,
    /// oder Remote-Branch zeigt auf denselben Commit wie der lokale Branch).
    func selectCommit(bySha sha: String) {
        // Bei aktiver Suche zuerst in Suchergebnissen, dann in der normalen Liste.
        let pool = isSearchActive ? searchResults + commits : commits
        // Exaktes Matching zuerst (voller SHA), dann Präfix-Fallback (Kurz-SHA).
        let commit = pool.first(where: { $0.sha == sha })
                  ?? pool.first(where: { $0.sha.hasPrefix(sha) })
        guard let commit else {
            // Während eines Ladevorgangs kann der Stand noch veraltet sein — kein Fehler.
            guard !isLoading else { return }
            branchJumpMessage = "Commit dieses Branches ist nicht in den geladenen Commits."
            Task {
                try? await Task.sleep(for: .seconds(3))
                branchJumpMessage = nil
            }
            return
        }
        selectedCommitID = commit.sha
        scrollTargetID = commit.sha
        scrollRequestToken &+= 1
    }

    private func loadDiff(for sha: String) async {
        isDiffLoading = true
        currentDiff = nil
        do {
            currentDiff = try await service.loadDiff(sha: sha)
        } catch {
            // Diff-Fehler still ignorieren — Commit bleibt auswählbar
        }
        isDiffLoading = false
    }
}
