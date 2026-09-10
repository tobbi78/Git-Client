//
//  RepositoryViewModel.swift
//  Git-Client
//
//  Hält den Ladezustand und die geladenen Daten (Commits, später Branches/Tags)
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
    var isLoading = false
    var errorMessage: String? = nil

    // Ausgewählter Commit für die Detail-/Diff-Ansicht
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
            commits = try await service.loadCommits()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
