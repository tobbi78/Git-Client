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
    var errorMessage: String? = nil

    // Remote-Sync-Zustand
    var behindCount = 0          // Commits auf dem Server, die lokal fehlen
    var aheadCount = 0           // lokale Commits, die noch nicht gepusht sind
    var hasRemote = false
    var hasUpstream = false
    var isFetching = false
    var isPulling = false
    var remoteStatusMessage: String? = nil

    var selectedCommitID: String? = nil {
        didSet { if let id = selectedCommitID { Task { await loadDiff(for: id) } } }
    }

    var selectedCommit: Commit? {
        guard let id = selectedCommitID else { return nil }
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
        do {
            async let commitsTask = service.loadCommits()
            async let branchesTask = service.loadBranches()
            async let tagsTask = service.loadTags()
            commits = try await commitsTask
            branches = try await branchesTask
            tags = try await tagsTask
            graphRows = CommitGraphBuilder.build(from: commits)
        } catch {
            errorMessage = error.localizedDescription
        }
        hasRemote = await service.hasRemote()
        await refreshAheadBehind()
        isLoading = false
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
        // Exaktes Matching zuerst (voller SHA), dann Präfix-Fallback (Kurz-SHA).
        let commit = commits.first(where: { $0.sha == sha })
                  ?? commits.first(where: { $0.sha.hasPrefix(sha) })
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
