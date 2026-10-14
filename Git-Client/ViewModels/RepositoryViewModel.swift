//
//  RepositoryViewModel.swift
//  Git-Client
//
//  Hält den Ladezustand und die geladenen Daten (Commits, Branches, Tags)
//  für das aktuell geöffnete Repository.
//

import Foundation
import Observation

/// Zustand der ausstehenden Branch-Lösch-Abfrage — vorab (vor dem ersten Dialog)
/// per Merge-Status entschieden, siehe `RepositoryViewModel.requestDeleteBranch`.
nonisolated enum PendingBranchDeletion: Equatable, Sendable {
    case confirmSafe(Branch)    // gemerged → normale "wirklich löschen?"-Abfrage
    case confirmForce(Branch)   // nicht gemerged → Force-Löschen-Abfrage
}

@Observable
@MainActor
final class RepositoryViewModel {
    let repository: RepositoryBookmark
    private let service: GitService
    private let settings: AppSettings

    var commits: [Commit] = []
    var graphRows: [GraphRow] = []
    var branches: [Branch] = [] {
        didSet { rebuildBranchDerived() }
    }
    var tags: [GitTag] = []

    // Von `branches` abgeleitete, vorab gebaute Baum-Struktur für die Sidebar —
    // wird nur bei einer Zuweisung an `branches` neu berechnet (siehe `didSet`
    // oben), nicht bei jedem SwiftUI-Render.
    private(set) var localBranchTree: [BranchTreeNode] = []
    private(set) var remoteNames: [String] = []
    private(set) var remoteBranchTrees: [String: [BranchTreeNode]] = [:]
    var isLoading = false
    var isLoadingMore = false   // Nachlade-Vorgang läuft
    var canLoadMore = true      // false sobald git log < pageSize zurückgibt
    var errorMessage: String? = nil

    /// Anzahl der per git-log-Paginierung geladenen Commits (Basis für --skip).
    /// Nicht identisch mit commits.count, da loadMissingBranchTips weitere Commits injiziert.
    private var pagedCount = 0
    private var pageSize: Int { settings.commitBatchSize }

    // Remote-Sync-Zustand
    var behindCount = 0          // Commits auf dem Server, die lokal fehlen
    var aheadCount = 0           // lokale Commits, die noch nicht gepusht sind
    var hasRemote = false
    var hasUpstream = false
    var isFetching = false
    var isPulling = false
    var remoteStatusMessage: String? = nil
    /// true → Warndialog "lokalen Stand verwerfen und hart synchronisieren?" anzeigen.
    /// Wird gesetzt, wenn der Fast-Forward in `pull()` fehlschlägt (divergierte
    /// Historie oder lokale Änderungen) — abgestimmte Schreib-Policy-Ausnahme, siehe
    /// BACKLOG #10.
    var pendingHardReset = false

    // MARK: - Branch-Checkout
    var isCheckingOutBranch = false
    var pendingCheckoutBranch: Branch? = nil   // != nil → Warndialog anzeigen
    var checkoutErrorMessage: String? = nil

    // MARK: - Branch-Löschen
    var isDeletingBranch = false
    /// != nil → genau eine Lösch-Abfrage anzeigen (Inhalt je nach Merge-Status).
    /// Bewusst EIN Dialog-State statt zwei verketteter: ein zweiter confirmationDialog
    /// direkt im Anschluss an einen gerade geschlossenen wird von SwiftUI nicht
    /// zuverlässig angezeigt, daher wird der Merge-Status schon vor der ersten
    /// Abfrage geprüft (siehe `requestDeleteBranch`).
    var pendingBranchDeletion: PendingBranchDeletion? = nil
    var deleteBranchErrorMessage: String? = nil

    /// true, während ein Git-Befehl läuft, der `.git/index.lock` über die
    /// gesamte Laufzeit hält (Fetch/Pull/Hard-Reset/Checkout). AppModel prüft
    /// dies, um den FSEvent-getriebenen `refreshLocalStatus`-Aufruf (git status)
    /// für dasselbe, gerade geöffnete Repository zu überspringen — sonst
    /// kollidiert er bei großen Resets/Checkouts mit dem bereits bestehenden Lock.
    var isPerformingGitWriteOperation: Bool {
        isFetching || isPulling || isCheckingOutBranch || isDeletingBranch
    }

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

    // MARK: - Blame
    var showBlameSheet = false
    var blameFilePath: String? = nil
    private(set) var blameLines: [BlameLine] = []
    var isBlameLoading = false
    var blameError: String? = nil

    // Expliziter Scroll-Trigger: erhöht sich bei jedem Branch-/Tag-Klick,
    // auch wenn der Commit bereits ausgewählt war (gleiche ID).
    private(set) var scrollRequestToken = 0
    var scrollTargetID: String? = nil

    // Dezente Rückmeldung, wenn der Tip-Commit nicht in der geladenen Liste ist.
    var branchJumpMessage: String? = nil

    init(repository: RepositoryBookmark, settings: AppSettings = .shared) {
        self.repository = repository
        self.service = GitService(repositoryPath: repository.path)
        self.settings = settings
    }

    private func rebuildBranchDerived() {
        let local = branches.filter { !$0.isRemote }
        localBranchTree = BranchTree.build(local, nameOf: \.name)

        let remote = branches.filter { $0.isRemote }
        let names = Array(Set(remote.compactMap(\.remoteName))).sorted()
        remoteNames = names
        remoteBranchTrees = Dictionary(uniqueKeysWithValues: names.map { name in
            (name, BranchTree.build(remote.filter { $0.remoteName == name }, nameOf: \.shortName))
        })
    }

    /// Baut die Graph-Zeilen auf einer Hintergrund-Task, statt den (bei vielen geladenen
    /// Commits durchaus spürbaren) Lane-Assignment-Algorithmus auf dem Main-Thread laufen
    /// zu lassen. `commits` wird als Snapshot übergeben, damit die `@MainActor`-isolierte
    /// Property nicht aus der abgetrennten Task heraus gelesen werden muss.
    private func buildGraphRows(from commits: [Commit]) async -> [GraphRow] {
        await Task.detached { CommitGraphBuilder.build(from: commits) }.value
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
            graphRows = await buildGraphRows(from: commits)
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
            graphRows = await buildGraphRows(from: commits)
        } catch {
            // Fehler still ignorieren — canLoadMore bleibt true für erneuten Versuch beim nächsten Scroll
        }
    }

    /// Lädt Branch-Tip-Commits nach, die noch nicht in `commits` enthalten sind.
    private func loadMissingBranchTips() async {
        let loadedSHAs = Set(commits.map(\.sha))
        // Set-Dedup: mehrere Branches können auf denselben Tip zeigen.
        let missingTips = Array(Set(
            branches.map(\.tipSha).filter { !loadedSHAs.contains($0) }
        ))
        guard !missingTips.isEmpty else { return }

        // Ein Subprozess für alle fehlenden Tips statt einem pro Tip (git log --no-walk).
        guard let additional = try? await service.loadCommits(shas: missingTips),
              !additional.isEmpty else { return }
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

    /// Übernimmt die Remote-Commits per Fast-Forward in den aktuellen Branch. Schlägt
    /// das fehl (divergierte Historie oder lokale Änderungen, die überschrieben würden),
    /// wird statt eines Fehlers ein Warndialog ausgelöst (`pendingHardReset`) — Tobias
    /// hat festgelegt, dass "Aktualisieren" lokal immer auf den Remote-Stand bringen
    /// soll, siehe BACKLOG #10 und die Schreib-Policy-Notiz dazu.
    func pull() async {
        guard !isFetching, !isPulling else { return }
        isPulling = true
        remoteStatusMessage = nil
        do {
            try await service.fastForward()
            await load()
        } catch {
            pendingHardReset = true
        }
        isPulling = false
    }

    /// Vom Warndialog: lokalen Stand verwerfen und hart auf den Upstream zurücksetzen.
    func confirmHardResetToUpstream() async {
        pendingHardReset = false
        isPulling = true
        remoteStatusMessage = nil
        do {
            try await service.hardResetToUpstream()
            await load()
        } catch {
            remoteStatusMessage = error.localizedDescription
        }
        isPulling = false
    }

    func cancelPendingHardReset() {
        pendingHardReset = false
    }

    // MARK: - Branch-Checkout

    /// Prüft auf unkommittete Änderungen; wechselt direkt oder löst den Warndialog aus.
    /// Bei Remote-Branches wird dabei ein neuer, gleichnamiger lokaler Tracking-Branch angelegt.
    func requestCheckout(_ branch: Branch) async {
        guard !branch.isCurrent, !isCheckingOutBranch else { return }
        if await service.hasUncommittedChanges() {
            pendingCheckoutBranch = branch
        } else {
            await performCheckout(branch, force: false)
        }
    }

    /// Vom Warndialog: Änderungen verwerfen und wechseln.
    func confirmCheckoutDiscardingChanges() async {
        guard let branch = pendingCheckoutBranch else { return }
        pendingCheckoutBranch = nil
        await performCheckout(branch, force: true)
    }

    func cancelPendingCheckout() {
        pendingCheckoutBranch = nil
    }

    private func performCheckout(_ branch: Branch, force: Bool) async {
        isCheckingOutBranch = true
        checkoutErrorMessage = nil
        do {
            if branch.isRemote {
                try await service.checkoutNewBranch(localName: branch.shortName, from: branch.name, force: force)
            } else {
                try await service.checkoutBranch(name: branch.name, force: force)
            }
            await load()
        } catch {
            checkoutErrorMessage = error.localizedDescription
        }
        isCheckingOutBranch = false
    }

    // MARK: - Branch-Löschen

    /// Prüft, ob der Branch gelöscht werden darf — nie der aktuelle, nie ein
    /// Remote-Branch (das bleibt reine Anzeige), und nie der letzte verbleibende
    /// lokale Branch (z.B. bei einem einzelnen, nicht ausgecheckten Branch im
    /// Detached-HEAD-Zustand). Prüft den Merge-Status VORAB, damit genau ein
    /// passender Dialog gezeigt wird (siehe Kommentar an `pendingBranchDeletion`).
    func requestDeleteBranch(_ branch: Branch) async {
        guard !branch.isRemote, !branch.isCurrent, !isDeletingBranch else { return }
        guard branches.filter({ !$0.isRemote }).count > 1 else { return }
        let merged = await service.isBranchMerged(name: branch.name)
        pendingBranchDeletion = merged ? .confirmSafe(branch) : .confirmForce(branch)
    }

    /// Von der Lösch-Abfrage: Branch tatsächlich löschen — mit `-d` bei gemergtem,
    /// mit `-D` (force) bei nicht gemergtem Branch. Nimmt den Abfrage-Zustand bewusst
    /// als Parameter entgegen statt ihn erneut aus `pendingBranchDeletion` zu lesen:
    /// beim Antippen EINES BELIEBIGEN Dialog-Buttons setzt SwiftUI die `isPresented`-
    /// Bindung synchron auf `false` (ruft also schon den Dismiss-Handler
    /// `cancelPendingBranchDeletion()` auf), BEVOR der hier aus dem Button-Callback
    /// per `Task { await ... }` gestartete Aufruf überhaupt zur Ausführung kommt. Ein
    /// erneutes Lesen von `pendingBranchDeletion` würde deshalb fast immer bereits
    /// `nil` liefern und den Löschvorgang klammheimlich überspringen (beobachteter
    /// Bug: Force-Löschen-Dialog bestätigt, nichts passiert, keine Fehlermeldung).
    /// Der Wert kommt stattdessen aus der `presenting:`-Variante von
    /// `confirmationDialog` in MainWindowView, die ihn beim Erscheinen des Dialogs
    /// einfriert und unabhängig vom späteren Zurücksetzen an die Action-Closures
    /// weitergibt.
    func performPendingBranchDeletion(_ pending: PendingBranchDeletion) async {
        pendingBranchDeletion = nil
        switch pending {
        case .confirmSafe(let branch):
            await performDelete(branch, force: false)
        case .confirmForce(let branch):
            await performDelete(branch, force: true)
        }
    }

    func cancelPendingBranchDeletion() {
        pendingBranchDeletion = nil
    }

    private func performDelete(_ branch: Branch, force: Bool) async {
        isDeletingBranch = true
        deleteBranchErrorMessage = nil
        do {
            try await service.deleteLocalBranch(name: branch.name, force: force)
            await load()
        } catch {
            // Egal aus welchem Grund das Löschen fehlschlägt (z.B. Merge-Status hat
            // sich seit der Vorab-Prüfung geändert, oder der Branch ist in einem
            // anderen Worktree ausgecheckt) — immer sichtbar melden statt
            // stillschweigend nichts zu tun.
            deleteBranchErrorMessage = error.localizedDescription
        }
        isDeletingBranch = false
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
            let pageSize = settings.commitBatchSize
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
            searchGraphRows = await buildGraphRows(from: searchResults)
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

    // MARK: - Blame

    /// Öffnet das Blame-Sheet für `path` im aktuell ausgewählten Commit.
    func requestBlame(path: String) {
        guard selectedCommitID != nil else { return }
        blameFilePath = path
        blameLines = []
        blameError = nil
        showBlameSheet = true
        Task { await loadBlame() }
    }

    private func loadBlame() async {
        guard let path = blameFilePath,
              let sha = selectedCommitID else { return }
        isBlameLoading = true
        defer { isBlameLoading = false }
        do {
            blameLines = try await service.blame(path: path, sha: sha)
        } catch {
            blameError = error.localizedDescription
        }
    }
}
