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
    var branches: [Branch] = []
    var tags: [GitTag] = []
    var isLoading = false
    var errorMessage: String? = nil

    var selectedCommitID: String? = nil

    var selectedCommit: Commit? {
        guard let id = selectedCommitID else { return nil }
        return commits.first { $0.id == id }
    }

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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
