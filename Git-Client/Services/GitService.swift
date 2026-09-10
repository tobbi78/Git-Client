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

    // MARK: - Branches

    func loadBranches() async throws -> [Branch] {
        let format = "%(refname)\t%(objectname:short)\t%(HEAD)"
        let output = try await runner.runOrThrow(
            ["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"],
            workingDirectory: repositoryPath
        )
        return parseBranches(from: output)
    }

    private func parseBranches(from output: String) -> [Branch] {
        output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> Branch? in
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 3 else { return nil }
                let refname = fields[0]
                let sha = fields[1]
                let isCurrent = fields[2] == "*"

                if refname.hasPrefix("refs/heads/") {
                    let name = String(refname.dropFirst("refs/heads/".count))
                    return Branch(name: name, shortName: name, isCurrent: isCurrent,
                                  isRemote: false, remoteName: nil, tipSha: sha)
                }

                if refname.hasPrefix("refs/remotes/") {
                    let remoteRef = String(refname.dropFirst("refs/remotes/".count))
                    // refs/remotes/origin/HEAD überspringen
                    if remoteRef.hasSuffix("/HEAD") { return nil }
                    let slashIdx = remoteRef.firstIndex(of: "/") ?? remoteRef.endIndex
                    let remoteName = String(remoteRef[..<slashIdx])
                    let shortName = slashIdx < remoteRef.endIndex
                        ? String(remoteRef[remoteRef.index(after: slashIdx)...])
                        : remoteRef
                    return Branch(name: remoteRef, shortName: shortName, isCurrent: false,
                                  isRemote: true, remoteName: remoteName, tipSha: sha)
                }

                return nil
            }
    }

    // MARK: - Tags

    func loadTags() async throws -> [GitTag] {
        let format = "%(refname:short)\t%(objectname:short)"
        let output = try await runner.runOrThrow(
            ["for-each-ref", "--format=\(format)", "refs/tags"],
            workingDirectory: repositoryPath
        )
        return parseTags(from: output)
    }

    private func parseTags(from output: String) -> [GitTag] {
        output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> GitTag? in
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 2 else { return nil }
                return GitTag(name: fields[0], targetSha: fields[1])
            }
    }

    // MARK: - Diff

    func loadDiff(sha: String) async throws -> CommitDiff {
        let output = try await runner.runOrThrow(
            ["show", "--format=", "--patch", sha],
            workingDirectory: repositoryPath
        )
        return DiffParser.parse(output, sha: sha)
    }
}
