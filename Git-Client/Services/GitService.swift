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

    /// Lädt bis zu `limit` Commits, optional ab Position `skip` (für Paginierung).
    /// `--date-order` bleibt stabil über aufeinanderfolgende Pages solange sich Refs nicht ändern.
    func loadCommits(limit: Int = 2000, skip: Int = 0) async throws -> [Commit] {
        let format = "--pretty=format:\(GitLogParser.formatString)"
        var args = ["log", "--all", "--date-order", format, "-\(limit)"]
        if skip > 0 { args.append("--skip=\(skip)") }
        let output = try await runner.runOrThrow(args, workingDirectory: repositoryPath)
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
        // Felder: refname, SHA, HEAD-Marker, Upstream-Kurzname, Tracking-Info
        let format = "%(refname)\t%(objectname)\t%(HEAD)\t%(upstream:short)\t%(upstream:track,nobracket)"
        let output = try await runner.runOrThrow(
            ["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"],
            workingDirectory: repositoryPath
        )
        return parseBranches(from: output)
    }

    nonisolated func parseBranches(from output: String) -> [Branch] {
        output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> Branch? in
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 3 else { return nil }
                let refname = fields[0]
                let sha = fields[1]
                let isCurrent = fields[2] == "*"
                // Tracking-Felder defensiv lesen — ältere Zeilen (< 5 Felder) bleiben nil
                let upstreamShort = fields.count >= 4 ? fields[3] : ""
                let trackString   = fields.count >= 5 ? fields[4] : ""

                if refname.hasPrefix("refs/heads/") {
                    let name = String(refname.dropFirst("refs/heads/".count))
                    // Upstream nur setzen, wenn tatsächlich konfiguriert
                    let hasUpstream = !upstreamShort.isEmpty
                    let tracking = hasUpstream ? parseTrack(trackString) : nil
                    return Branch(name: name, shortName: name, isCurrent: isCurrent,
                                  isRemote: false, remoteName: nil, tipSha: sha,
                                  upstreamName: hasUpstream ? upstreamShort : nil,
                                  ahead: tracking?.ahead, behind: tracking?.behind)
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
                                  isRemote: true, remoteName: remoteName, tipSha: sha,
                                  upstreamName: nil, ahead: nil, behind: nil)
                }

                return nil
            }
    }

    /// Parst den `%(upstream:track,nobracket)`-String (z.B. „ahead 2, behind 3")
    /// und extrahiert die Anzahl der vorausgehenden / fehlenden Commits.
    /// Bei `gone`, leerem String oder nicht erkanntem Format wird (0, 0) zurückgegeben.
    nonisolated func parseTrack(_ track: String) -> (ahead: Int, behind: Int) {
        guard !track.isEmpty, track != "gone" else { return (0, 0) }
        var ahead = 0
        var behind = 0
        // Kommaseparierte Segmente: "ahead 2", "behind 3"
        for segment in track.components(separatedBy: ",") {
            let part = segment.trimmingCharacters(in: .whitespaces)
            if part.hasPrefix("ahead "), let n = Int(part.dropFirst("ahead ".count)) {
                ahead = n
            } else if part.hasPrefix("behind "), let n = Int(part.dropFirst("behind ".count)) {
                behind = n
            }
        }
        return (ahead, behind)
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

    // MARK: - Commit-Suche

    /// Durchsucht das gesamte Repository nach Commits, die `criteria` erfüllen.
    /// Unterstützt: Nachricht (--grep), Autor (--author), Datumsbereich (--since/--until),
    /// SHA-Präfix (git rev-parse --disambiguate oder in-memory-Filter).
    ///
    /// Alle Kriterien werden als UND verknüpft (git log verhält sich so standardmäßig).
    func searchCommits(
        criteria: CommitSearchCriteria,
        limit: Int = 2000,
        skip: Int = 0
    ) async throws -> [Commit] {
        let msgTrimmed    = criteria.message.trimmingCharacters(in: .whitespaces)
        let authorTrimmed = criteria.author.trimmingCharacters(in: .whitespaces)
        let shaTrimmed    = criteria.sha.trimmingCharacters(in: .whitespaces)

        // Sonderfall: SHA als einziges Kriterium → git rev-parse --disambiguate
        let shaOnly = !shaTrimmed.isEmpty
            && msgTrimmed.isEmpty && authorTrimmed.isEmpty
            && criteria.since == nil && criteria.until == nil
        if shaOnly {
            return try await searchByShaOnly(prefix: shaTrimmed)
        }

        // Normaler git-log-Pfad
        let format = "--pretty=format:\(GitLogParser.formatString)"
        var args = ["log", "--all", "--date-order", "-i", format, "-\(limit)"]
        if skip > 0 { args.append("--skip=\(skip)") }
        if !msgTrimmed.isEmpty    { args.append("--grep=\(msgTrimmed)") }
        if !authorTrimmed.isEmpty { args.append("--author=\(authorTrimmed)") }
        if let since = criteria.since {
            let iso = ISO8601DateFormatter()
            args.append("--since=\(iso.string(from: since))")
        }
        if let until = criteria.until {
            let iso = ISO8601DateFormatter()
            args.append("--until=\(iso.string(from: until))")
        }

        let output = try await runner.runOrThrow(args, workingDirectory: repositoryPath)
        var results = GitLogParser.parse(output)

        // SHA-Filter: wenn SHA zusammen mit anderen Kriterien angegeben → in-memory
        if !shaTrimmed.isEmpty {
            let lower = shaTrimmed.lowercased()
            results = results.filter {
                $0.sha.hasPrefix(lower) || $0.shortSha.hasPrefix(lower)
            }
        }
        return results
    }

    /// SHA-only-Pfad: nutzt `git rev-parse --disambiguate` um alle passenden vollen
    /// SHAs für einen Präfix zu finden und lädt jeden einzeln.
    private func searchByShaOnly(prefix: String) async throws -> [Commit] {
        let result = try? await runner.run(
            ["rev-parse", "--disambiguate=\(prefix.lowercased())"],
            workingDirectory: repositoryPath
        )
        let shas = (result?.stdout ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if shas.isEmpty { return [] }

        var commits: [Commit] = []
        await withTaskGroup(of: Commit?.self) { group in
            for sha in shas {
                group.addTask { await self.loadSingleCommit(sha: sha) }
            }
            for await commit in group {
                if let c = commit { commits.append(c) }
            }
        }
        return commits.sorted { $0.date > $1.date }
    }

    // MARK: - Diff

    func loadDiff(sha: String) async throws -> CommitDiff {
        let output = try await runner.runOrThrow(
            ["show", "--format=", "--patch", sha],
            workingDirectory: repositoryPath
        )
        return DiffParser.parse(output, sha: sha)
    }

    // MARK: - Blame

    /// Gibt die zeilenweise Autorschaft der Datei `path` im Zustand des Commits `sha` zurück.
    /// Verwendet `git blame --porcelain`, das maschinenlesbare Metadaten pro Zeile liefert.
    func blame(path: String, sha: String) async throws -> [BlameLine] {
        let output = try await runner.runOrThrow(
            ["blame", "--porcelain", sha, "--", path],
            workingDirectory: repositoryPath
        )
        return BlameParser.parse(output)
    }
}
