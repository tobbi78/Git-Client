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

    /// Injiziert Zugangsdaten in `remoteURL`, falls beide angegeben sind — sonst bleibt
    /// die URL unverändert. Zentrale Stelle für den Credential-URL-Aufbau, der zuvor in
    /// clone/fetch/remoteHeads dreifach dupliziert war. Nicht `private`, damit sie direkt
    /// testbar ist (über lokale Pfad-Remotes lassen sich Credentials nicht prüfen).
    nonisolated static func authenticatedURL(
        _ remoteURL: String, username: String?, password: String?
    ) -> String {
        guard let user = username, !user.isEmpty,
              let pass = password, !pass.isEmpty,
              var components = URLComponents(string: remoteURL) else { return remoteURL }
        components.user = user
        components.password = pass
        return components.string ?? remoteURL
    }

    // MARK: - Clone

    /// Klont `remoteURL` nach `localPath`. Credentials werden als URL-Parameter übergeben
    /// und verlassen die App nie als Klartext auf der Festplatte.
    func clone(remoteURL: String, to localPath: URL, username: String?, password: String?) async throws {
        let urlString = Self.authenticatedURL(remoteURL, username: username, password: password)
        // Elternverzeichnis muss existieren; git clone erstellt localPath selbst.
        let parent = localPath.deletingLastPathComponent()
        try await runner.runOrThrow(
            ["clone", "--", urlString, localPath.path],
            workingDirectory: parent
        )
    }

    // MARK: - Commit-Historie

    /// Lädt bis zu `limit` Commits, optional ab Position `skip` (für Paginierung).
    /// `--date-order` bleibt stabil über aufeinanderfolgende Pages solange sich Refs nicht ändern.
    func loadCommits(limit: Int = 2000, skip: Int = 0) async throws -> [Commit] {
        let format = "--pretty=format:\(GitLogParser.formatString)"
        var args = ["log", "--all", "--date-order", format, "-\(limit)"]
        if skip > 0 { args.append("--skip=\(skip)") }
        let output = try await runLogAllTolerant(args)
        return GitLogParser.parse(output)
    }

    /// Führt ein `git log --all …` aus. Scheitert es an einem kaputten Ref (z.B. einer
    /// durch Sync-Tools/Finder angelegten Datei `.git/refs/heads/develop 2` mit Leerzeichen
    /// im Namen → `fatal: bad object …`), wird erneut mit den Namen aller gültigen Refs
    /// statt `--all` gestartet. `for-each-ref` überspringt kaputte Refs nur mit Warnung.
    private func runLogAllTolerant(_ args: [String]) async throws -> String {
        let result = try await runner.run(args, workingDirectory: repositoryPath)
        if result.exitCode == 0 { return result.stdout }

        guard result.stderr.contains("bad object"),
              let allIndex = args.firstIndex(of: "--all") else {
            throw GitError.nonZeroExit(
                code: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let refs = try await runner.runOrThrow(
            ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags"],
            workingDirectory: repositoryPath
        )
        let validRefs = refs.split(separator: "\n").map(String.init)
        var fallbackArgs = args
        fallbackArgs.replaceSubrange(allIndex...allIndex, with: ["HEAD"] + validRefs)
        return try await runner.runOrThrow(fallbackArgs, workingDirectory: repositoryPath)
    }

    /// Namen kaputter Refs (z.B. `refs/heads/develop 2`), die Git beim Auflisten der Refs
    /// mit „ignoring ref with broken name" überspringt. Leer, wenn alles in Ordnung ist.
    func brokenRefs() async -> [String] {
        guard let result = try? await runner.run(
            ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes", "refs/tags"],
            workingDirectory: repositoryPath
        ) else { return [] }
        return Self.parseBrokenRefs(stderr: result.stderr)
    }

    /// Extrahiert die Ref-Namen aus Zeilen der Form
    /// `warning: ignoring ref with broken name <ref>`.
    nonisolated static func parseBrokenRefs(stderr: String) -> [String] {
        let prefix = "warning: ignoring ref with broken name "
        return stderr.split(separator: "\n").compactMap { line in
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
        }
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

    /// Lädt mehrere einzelne Commits per SHA in **einem** Subprozess (`git log --no-walk`)
    /// statt eines Subprozesses pro SHA. Wird verwendet, um mehrere Branch-Tips nachzuladen,
    /// die außerhalb des normalen Fensters liegen. `shas` dürfen doppelt vorkommen und in
    /// beliebiger Reihenfolge sein — die Ausgabe wird unverändert vom bestehenden Parser
    /// verarbeitet, die Aufrufer sortieren/deduplizieren ohnehin nach dem Zusammenführen.
    func loadCommits(shas: [String]) async throws -> [Commit] {
        guard !shas.isEmpty else { return [] }
        let format = "--pretty=format:\(GitLogParser.formatString)"
        let output = try await runner.runOrThrow(
            ["log", "--no-walk", format] + shas,
            workingDirectory: repositoryPath
        )
        return GitLogParser.parse(output)
    }

    // MARK: - Branches

    func loadBranches() async throws -> [Branch] {
        // Felder: refname, SHA, HEAD-Marker, Upstream-Kurzname, Tracking-Info
        let format = "%(refname)\t%(objectname)\t%(HEAD)\t%(upstream:short)\t%(upstream:track,nobracket)\t%(committerdate:unix)"
        let output = try await runner.runOrThrow(
            ["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"],
            workingDirectory: repositoryPath
        )
        return BranchParser.parseBranches(from: output)
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
        return BranchParser.parseTags(from: output)
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

    /// Web-URL des Remotes (z.B. `https://github.com/user/repo`) zum Öffnen im Browser.
    /// `nil`, wenn kein Remote konfiguriert ist oder sich aus dessen URL keine
    /// Webseite ableiten lässt (z.B. lokaler Pfad als Remote).
    func remoteWebURL() async throws -> URL? {
        guard let remote = try await remoteName() else { return nil }
        let output = try await runner.runOrThrow(["remote", "get-url", remote], workingDirectory: repositoryPath)
        return Self.webURL(fromRemoteURL: output)
    }

    /// Leitet aus einer Git-Remote-URL die Browser-URL ab. Unterstützt https/http,
    /// ssh://, git:// und die scp-artige Kurzform `git@host:pfad/repo.git`.
    /// Zugangsdaten, SSH-Ports und die `.git`-Endung werden entfernt.
    nonisolated static func webURL(fromRemoteURL remoteURL: String) -> URL? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var scheme = "https"
        var host: String
        var port: Int? = nil
        var path: String

        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed),
                  let urlScheme = components.scheme?.lowercased(),
                  ["http", "https", "ssh", "git", "git+ssh", "ssh+git"].contains(urlScheme),
                  let urlHost = components.host, !urlHost.isEmpty else { return nil }
            host = urlHost
            path = components.path
            // Nur bei HTTP(S) gehört der Port zur Web-URL; ein SSH-/Git-Port nicht.
            if urlScheme == "http" || urlScheme == "https" {
                scheme = urlScheme
                port = components.port
            }
        } else {
            // scp-artig: [user@]host:pfad — vor dem ':' darf kein '/' stehen,
            // sonst ist es ein lokaler Pfad.
            guard let colon = trimmed.firstIndex(of: ":"),
                  !trimmed[..<colon].contains("/") else { return nil }
            let hostPart = trimmed[..<colon]
            host = String(hostPart.split(separator: "@", omittingEmptySubsequences: false).last ?? hostPart)
            path = String(trimmed[trimmed.index(after: colon)...])
            guard !host.isEmpty else { return nil }
        }

        while path.hasPrefix("/") { path.removeFirst() }
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        guard !path.isEmpty else { return nil }

        var result = URLComponents()
        result.scheme = scheme
        result.host = host
        result.port = port
        result.path = "/" + path
        return result.url
    }

    /// Holt den aktuellen Stand vom Server. Aktualisiert die Remote-Tracking-Refs,
    /// damit der ahead/behind-Vergleich korrekt ist.
    ///
    /// Credentials werden – analog zu `clone` – transient in die Fetch-URL injiziert und
    /// verlassen die App nie als Klartext auf der Festplatte.
    func fetch(remoteURL: String?, username: String?, password: String?) async throws {
        guard let remote = try await remoteName() else { return }

        if let remoteURL, !remoteURL.isEmpty {
            let authURL = Self.authenticatedURL(remoteURL, username: username, password: password)
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

    /// Setzt den aktuellen Branch hart auf den Stand des Upstream-Branches zurück —
    /// verwirft dabei jede lokale Abweichung (unkommittete Änderungen UND lokale
    /// Commits, die nicht auf dem Server sind). Bewusste, mit Tobias abgestimmte
    /// Ausnahme von der sonst rein lesenden Policy der App: wird nur als Fallback
    /// verwendet, wenn `fastForward()` fehlgeschlagen ist, und erst nach expliziter
    /// Nutzerbestätigung (siehe RepositoryViewModel.confirmHardResetToUpstream).
    func hardResetToUpstream() async throws {
        try await runner.runOrThrow(
            ["reset", "--hard", "@{upstream}"],
            workingDirectory: repositoryPath
        )
    }

    /// Entfernt eine verwaiste `.git/index.lock`. Bewusste, vom Nutzer ausgelöste Ausnahme
    /// von der rein lesenden Policy. Hält noch ein Prozess die Datei offen (laufender
    /// git-Befehl), wird nichts gelöscht und `GitError.indexLockInUse` geworfen.
    /// - Returns: false, wenn gar keine Sperrdatei (mehr) existierte.
    func removeStaleIndexLock() async throws -> Bool {
        let gitDir = try await runner.runOrThrow(
            ["rev-parse", "--absolute-git-dir"],
            workingDirectory: repositoryPath
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let lockPath = (gitDir as NSString).appendingPathComponent("index.lock")
        guard FileManager.default.fileExists(atPath: lockPath) else { return false }
        if await Self.isFileOpen(atPath: lockPath) { throw GitError.indexLockInUse }
        try FileManager.default.removeItem(atPath: lockPath)
        return true
    }

    /// Prüft per `lsof`, ob ein Prozess die Datei gerade geöffnet hat (git hält die
    /// index.lock während seiner gesamten Laufzeit offen).
    nonisolated private static func isFileOpen(atPath path: String) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-t", "--", path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return !data.isEmpty
        }.value
    }

    /// Wechselt auf den lokalen Branch `name`. Mit `force: true` werden dabei
    /// unkommittete Änderungen verworfen (git checkout --force) — wird nur nach
    /// expliziter Nutzerbestätigung verwendet.
    func checkoutBranch(name: String, force: Bool = false) async throws {
        var args = ["checkout"]
        if force { args.append("--force") }
        args.append(name)
        try await runner.runOrThrow(args, workingDirectory: repositoryPath)
    }

    /// Erstellt einen neuen lokalen Branch `localName`, der `remoteBranch`
    /// (z.B. "origin/feature") trackt, und wechselt direkt dorthin.
    /// Mit `force: true` werden dabei unkommittete Änderungen verworfen.
    func checkoutNewBranch(localName: String, from remoteBranch: String, force: Bool = false) async throws {
        var args = ["checkout"]
        if force { args.append("--force") }
        args.append(contentsOf: ["-b", localName, remoteBranch])
        try await runner.runOrThrow(args, workingDirectory: repositoryPath)
    }

    /// Löscht den lokalen Branch `name` (nie den aktuellen oder Remote-Branches —
    /// das regelt der Aufrufer). Ohne `force` lehnt git das Löschen ab, falls der
    /// Branch noch nicht vollständig in einen anderen Branch gemerged ist
    /// (`git branch -d`); mit `force: true` wird trotzdem gelöscht (`git branch -D`).
    func deleteLocalBranch(name: String, force: Bool = false) async throws {
        try await runner.runOrThrow(["branch", force ? "-D" : "-d", name], workingDirectory: repositoryPath)
    }

    /// Prüft, ob `name` vollständig in den aktuellen HEAD gemerged ist
    /// (`git merge-base --is-ancestor`). Dient dazu, VOR der Lösch-Abfrage zu
    /// entscheiden, ob der normale oder der Force-Löschen-Dialog angezeigt wird —
    /// so muss nie ein zweiter confirmationDialog direkt im Anschluss an einen
    /// gerade geschlossenen präsentiert werden (SwiftUI zeigt den sonst nicht
    /// zuverlässig an). Schlägt die Prüfung selbst fehl, wird defensiv `false`
    /// angenommen (lieber einmal zu oft nach einem Force-Löschen fragen).
    func isBranchMerged(name: String) async -> Bool {
        guard let result = try? await runner.run(
            ["merge-base", "--is-ancestor", name, "HEAD"],
            workingDirectory: repositoryPath
        ) else { return false }
        return result.exitCode == 0
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

        let output = try await runLogAllTolerant(args)
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

    // MARK: - Datei-Historie

    /// Lädt bis zu `limit` Einträge der Historie von `path` (mit Umbenennungen, `--follow`),
    /// beginnend bei `rev`. `path` ist der Pfad der Datei in `rev`.
    ///
    /// Paginierung: nicht per `--skip` — übersprungene Commits werden von `--follow` nicht
    /// diffed, eine Umbenennung davor würde nie erkannt. Stattdessen startet die nächste
    /// Seite bei `"<letzter Eintrag>^@"` (alle Eltern) mit dem Pfad vor dem letzten Eintrag
    /// (`FileHistoryEntry.pathBefore`).
    func fileHistory(path: String, rev: String, limit: Int) async throws -> [FileHistoryEntry] {
        let args = [
            "log", "--follow", "-M", "--name-status",
            "--pretty=format:\(FileHistoryParser.recordMarker)\(GitLogParser.formatString)",
            "-\(limit)", rev, "--", path
        ]
        let output = try await runner.runOrThrow(args, workingDirectory: repositoryPath)
        return FileHistoryParser.parse(output, startPath: path)
    }

    /// Diff einer einzelnen Datei in Commit `sha`. Bei Merges gegen den ersten Parent.
    func fileDiff(sha: String, path: String, oldPath: String?) async throws -> DiffFile? {
        var args = ["show", "--format=", "--patch", "-M", "--diff-merges=first-parent", sha, "--"]
        if let oldPath, oldPath != path { args.append(oldPath) }
        args.append(path)
        let output = try await runner.runOrThrow(args, workingDirectory: repositoryPath)
        let files = DiffParser.parse(output, sha: sha).files
        return files.first { $0.newPath == path }
            ?? files.first { $0.oldPath == path }
            ?? files.first
    }

    /// Position von `sha` in der Reihenfolge der Hauptliste (`--all --date-order`),
    /// oder `nil`, wenn der Commit von keinem Ref aus erreichbar ist.
    func commitPosition(sha: String) async throws -> Int? {
        let output = try await runLogAllTolerant(["rev-list", "--all", "--date-order"])
        var index = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line == sha[...] || (sha.count < 40 && line.hasPrefix(sha)) { return index }
            index += 1
        }
        return nil
    }

    // MARK: - Auto-Refresh: lokale Ref-Signatur

    /// Liest die aktuelle `refs/heads`- und `refs/remotes`-Struktur des Repositories aus
    /// und liefert ein `[refname: sha]`-Dictionary zurück.
    /// Wird als Baseline für die lokale Änderungserkennung verwendet.
    func localRefSignature() async -> [String: String] {
        guard let output = try? await runner.runOrThrow(
            ["for-each-ref",
             "--format=%(objectname) %(refname)",
             "refs/heads",
             "refs/remotes"],
            workingDirectory: repositoryPath
        ) else { return [:] }
        return RepoRefSnapshot.parseForEachRef(output)
    }

    // MARK: - Auto-Refresh: Remote-Ref-Liste (ls-remote, kein Objekt-Download)

    /// Fragt den Server nach seinen Branch-Refs — **ohne** Commit-Objekte herunterzuladen.
    /// Credentials werden transient in die URL injiziert (analog `fetch`).
    /// Wirft bei Netzwerkfehler oder wenn kein Remote konfiguriert ist.
    func remoteHeads(
        remoteURL: String?,
        username: String?,
        password: String?
    ) async throws -> [String: String] {
        // Auth-URL aufbauen (analog fetch)
        let remoteArg: String
        if let urlString = remoteURL, !urlString.isEmpty {
            remoteArg = Self.authenticatedURL(urlString, username: username, password: password)
        } else {
            // Fallback: konfigurierten Remote-Namen verwenden
            guard let remote = try await remoteName() else {
                throw GitError.nonZeroExit(code: 128, stderr: "Kein Remote konfiguriert")
            }
            remoteArg = remote
        }

        let output = try await runner.runOrThrow(
            ["ls-remote", "--heads", remoteArg],
            workingDirectory: repositoryPath
        )
        return RepoRefSnapshot.parseLsRemote(output)
    }

    // MARK: - Statistiken

    /// Liefert Commits pro Autor über die gesamte Histoire (`git shortlog -sne --all`).
    /// Parsing erfolgt in `RepositoryStatistics.parseShortlog`.
    func authorCommitCounts() async throws -> [AuthorStat] {
        let output = try await runLogAllTolerant(["shortlog", "-sne", "--all"])
        return RepositoryStatistics.parseShortlog(output)
    }

    /// Liefert Unix-Zeitstempel aller Commits als Rohtext (ein Timestamp pro Zeile).
    /// Parsing und Aggregation erfolgen in `RepositoryStatistics.aggregate`.
    func commitTimestamps() async throws -> String {
        try await runLogAllTolerant(["log", "--all", "--pretty=format:%at"])
    }

    // MARK: - Lokale Repo-Statusabfragen (kein Netzwerk)

    /// Name des aktuell ausgecheckten Branches. nil bei detached HEAD oder Fehler.
    func currentBranch() async -> String? {
        guard let out = try? await runner.runOrThrow(
            ["rev-parse", "--abbrev-ref", "HEAD"],
            workingDirectory: repositoryPath
        ) else { return nil }
        let name = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty || name == "HEAD") ? nil : name
    }

    /// true, wenn das Arbeitsverzeichnis uncommittete Änderungen hat.
    func hasUncommittedChanges() async -> Bool {
        guard let out = try? await runner.runOrThrow(
            ["status", "--porcelain"],
            workingDirectory: repositoryPath
        ) else { return false }
        return RepoStatus.parsePorcelainDirty(out)
    }

    /// Datum des neuesten lokalen Commits (HEAD). nil bei leerem Repo oder Fehler.
    func lastCommitDate() async -> Date? {
        await loadSingleCommit(sha: "HEAD")?.date
    }

    /// Liefert Branch, Upstream-Ahead/Behind und ob es unkommittierte Änderungen gibt
    /// in einem Subprozess (`git status --porcelain=v2 --branch`) statt den drei
    /// separaten Aufrufen `currentBranch`/`hasUncommittedChanges`/`aheadBehind`.
    /// Wird vom Auto-Refresh-Monitoring verwendet, wo FSEvent-Bursts sonst mehrere
    /// git-Subprozesse pro Repo pro Event ausgelöst haben. `nil` bei Fehler.
    func localStatusSnapshot() async -> RepoStatus? {
        guard let output = try? await runner.runOrThrow(
            ["status", "--porcelain=v2", "--branch"],
            workingDirectory: repositoryPath
        ) else { return nil }
        return RepoStatus.parsePorcelainV2Branch(output)
    }
}
