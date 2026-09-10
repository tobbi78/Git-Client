//
//  GitService.swift
//  Git-Client
//
//  High-level Git-Operationen für ein einzelnes Repository.
//  Kapselt GitRunner und liefert typisierte Modelle zurück.
//

import Foundation

actor GitService {
    private let runner = GitRunner.shared
    let repositoryPath: URL

    init(repositoryPath: URL) {
        self.repositoryPath = repositoryPath
    }

    // MARK: - Validation

    func validateRepository() async throws {
        let result = try await runner.run(
            ["rev-parse", "--is-inside-work-tree"],
            workingDirectory: repositoryPath
        )
        guard result.exitCode == 0 else {
            throw GitError.notARepository
        }
    }

    // MARK: - Commit-Historie

    func loadCommits(limit: Int = 1000) async throws -> [Commit] {
        let format = "--pretty=format:\(GitLogParser.formatString)"
        let output = try await runner.runOrThrow(
            ["log", "--all", "--date-order", format, "-\(limit)"],
            workingDirectory: repositoryPath
        )
        return GitLogParser.parse(output)
    }
}
