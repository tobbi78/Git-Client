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

    // MARK: - Clone

    /// Klont `remoteURL` nach `localPath`. Credentials werden als URL-Parameter übergeben
    /// und verlassen die App nie als Klartext auf der Festplatte.
    func clone(remoteURL: String, to localPath: URL, username: String?, password: String?) async throws {
        var urlString = remoteURL
        if let user = username, !user.isEmpty,
           let pass = password, !pass.isEmpty,
           var components = URLComponents(string: remoteURL) {
            components.user = user
            components.password = pass
            urlString = components.string ?? remoteURL
        }
        // Elternverzeichnis muss existieren; git clone erstellt localPath selbst.
        let parent = localPath.deletingLastPathComponent()
        try await runner.runOrThrow(
            ["clone", "--", urlString, localPath.path],
            workingDirectory: parent
        )
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

    /// Lädt einen einzelnen Commit anhand seines vollen SHA.
    /// Wird verwendet, um Branch-Tips nachzuladen, die außerhalb des normalen Fensters liegen.
    func loadSingleCommit(sha: String) async -> Commit? {
        let format = "--pretty=format:\(GitLogParser.formatString)"
        guard let output = try? await runner.runOrThrow(
            ["log", "-1", format, sha],
            workingDirectory: repositoryPath
        ) else { return nil }
        return GitLogParser.parse(output).first
    }

    // MARK: - Branches

    func loadBranches() async throws -> [Branch] {
        let format = "%(refname)\t%(objectname)\t%(HEAD)"  // voller SHA, kein :short
        let output = try await runner.runOrThrow(
            ["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"],
            workingDirectory: repositoryPath
        )
        return parseBranches(from: output)
    }

    func parseBranches(from output: String) -> [Branch] {
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
        // %(*objectname:short) liefert den dereferenzierten Commit-SHA bei annotierten Tags;
        // bei Lightweight-Tags ist es leer → Fallback auf %(objectname:short)
        let format = "%(refname:short)\t%(objectname)\t%(*objectname)"  // volle SHAs, kein :short
        let output = try await runner.runOrThrow(
            ["for-each-ref", "--format=\(format)", "refs/tags"],
            workingDirectory: repositoryPath
        )
        return parseTags(from: output)
    }

    func parseTags(from output: String) -> [GitTag] {
        output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> GitTag? in
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 2 else { return nil }
                let deref = fields.count >= 3 ? fields[2] : ""
                let commitSha = deref.isEmpty ? fields[1] : deref
                return GitTag(name: fields[0], targetSha: commitSha)
            }
    }

    // MARK: - Remote / Sync

    /// Namen des ersten konfigurierten Remotes (Default-Konvention „origin").
    /// Gibt `nil` zurück, wenn kein Remote konfiguriert ist.
    func remoteName() async throws -> String? {
        let output = try await runner.runOrThrow(["remote"], workingDirectory: repositoryPath)
        let names = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        if names.contains("origin") { return "origin" }
        return names.first
    }

    func hasRemote() async -> Bool {
        (try? await remoteName()) ?? nil != nil
    }

    /// Holt den aktuellen Stand vom Server. Aktualisiert die Remote-Tracking-Refs,
    /// damit der ahead/behind-Vergleich korrekt ist.
    ///
    /// Credentials werden – analog zu `clone` – transient in die Fetch-URL injiziert und
    /// verlassen die App nie als Klartext auf der Festplatte.
    func fetch(remoteURL: String?, username: String?, password: String?) async throws {
        guard let remote = try await remoteName() else { return }

        if let remoteURL, !remoteURL.isEmpty,
           let user = username, !user.isEmpty,
           let pass = password, !pass.isEmpty,
           var components = URLComponents(string: remoteURL) {
            components.user = user
            components.password = pass
            let authURL = components.string ?? remoteURL
            try await runner.runOrThrow(
                ["fetch", "--prune", authURL, "+refs/heads/*:refs/remotes/\(remote)/*"],
                workingDirectory: repositoryPath
            )
        } else {
            try await runner.runOrThrow(
                ["fetch", "--prune", remote],
                workingDirectory: repositoryPath
            )
        }
    }

    /// Anzahl der Commits, um die der lokale HEAD dem Upstream voraus (`ahead`) bzw.
    /// hinterher (`behind`) ist. Gibt `nil` zurück, wenn kein Upstream konfiguriert ist.
    func aheadBehind() async throws -> (ahead: Int, behind: Int)? {
        let result = try await runner.run(
            ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            workingDirectory: repositoryPath
        )
        guard result.exitCode == 0 else { return nil }
        let fields = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: " \t"))
            .filter { !$0.isEmpty }
        guard fields.count == 2,
              let behind = Int(fields[0]),
              let ahead = Int(fields[1]) else { return nil }
        return (ahead: ahead, behind: behind)
    }

    /// Übernimmt die Upstream-Commits per Fast-Forward in den aktuellen Branch.
    /// Wirft bei Divergenz (`GitError.nonZeroExit`), da kein Merge-Commit erzeugt wird.
    func fastForward() async throws {
        try await runner.runOrThrow(
            ["merge", "--ff-only", "@{upstream}"],
            workingDirectory: repositoryPath
        )
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
