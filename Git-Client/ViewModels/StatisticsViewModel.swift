//
//  StatisticsViewModel.swift
//  Git-Client
//

import Foundation
import Observation

@Observable
@MainActor
final class StatisticsViewModel {
    let repository: RepositoryBookmark
    private let service: GitService

    private(set) var statistics: RepositoryStatistics? = nil
    private(set) var isLoading = false
    private(set) var errorMessage: String? = nil

    init(repository: RepositoryBookmark) {
        self.repository = repository
        self.service = GitService(repositoryPath: repository.path)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let authorsTask    = service.authorCommitCounts()
            async let timestampsTask = service.commitTimestamps()
            async let branchesTask   = service.loadBranches()
            async let tagsTask       = service.loadTags()

            let (authors, timestamps, branches, tags) =
                try await (authorsTask, timestampsTask, branchesTask, tagsTask)

            statistics = RepositoryStatistics.aggregate(
                timestampLines: timestamps,
                authors: authors,
                branchCount: branches.filter { !$0.isRemote }.count,
                tagCount: tags.count
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
