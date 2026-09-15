//
//  RepoRefSnapshot.swift
//  Git-Client
//
//  Wertetypen und statische Parser-/Diff-Logik für das Auto-Refresh-Feature.
//  Rein funktional, kein I/O — vollständig unit-testbar.
//

import Foundation

// MARK: - RepoNewCommits

/// Zusammenfassung des „Neuigkeiten"-Stands eines Repositories.
nonisolated struct RepoNewCommits: Equatable, Sendable {
    /// `.git` hat sich gegenüber der Session-Baseline verändert
    /// (neuer lokaler Commit, externer Terminal-Fetch/-Pull).
    var hasLocalChanges: Bool = false

    /// Anzahl der Branches auf dem Server, deren SHA von den lokalen
    /// Remote-Tracking-Refs abweicht oder dort noch gar nicht vorhanden ist.
    var remoteAheadBranches: Int = 0

    /// `true`, wenn mindestens eine Art von Neuigkeit vorliegt.
    var hasNews: Bool { hasLocalChanges || remoteAheadBranches > 0 }
}

// MARK: - RepoRefSnapshot

/// Statische Parser-Methoden für git-Ref-Ausgaben.
nonisolated enum RepoRefSnapshot {

    // MARK: - Parser: for-each-ref

    /// Parst die `git for-each-ref --format="%(objectname) %(refname)"` Ausgabe.
    /// Ergibt ein `[refname: sha]`-Dictionary.
    static func parseForEachRef(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: "<sha> <refname>" — sha ist 40 hex, refname beginnt mit "refs/"
            let parts = trimmed.components(separatedBy: " ")
            guard parts.count >= 2 else { continue }
            let sha = parts[0]
            let refname = parts[1...].joined(separator: " ")
            guard sha.count == 40 else { continue }
            result[refname] = sha
        }
        return result
    }

    // MARK: - Parser: ls-remote

    /// Parst die `git ls-remote --heads` Ausgabe.
    /// Format je Zeile: `<sha>\t<refname>` — Peeled-Zeilen (`^{}`) werden verworfen.
    /// Ergibt ein `[refname: sha]`-Dictionary (nur `refs/heads/...`-Einträge).
    static func parseLsRemote(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Peeled-Zeilen verwerfen (z.B. für annotierte Tags — bei --heads nicht
            // erwartet, aber defensiv abgesichert)
            guard !trimmed.hasSuffix("^{}") else { continue }
            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count == 2 else { continue }
            let sha = parts[0]
            let refname = parts[1]
            guard sha.count == 40 else { continue }
            result[refname] = sha
        }
        return result
    }

    // MARK: - Vergleich

    /// Zählt, wie viele Server-Branches eine andere SHA haben als die lokalen
    /// Remote-Tracking-Refs (oder lokal überhaupt nicht bekannt sind).
    ///
    /// - Parameters:
    ///   - localSignature: Ergebnis von `parseForEachRef` — enthält u.a. `refs/remotes/<remote>/<branch>`.
    ///   - remoteHeads: Ergebnis von `parseLsRemote` — enthält `refs/heads/<branch>` vom Server.
    ///   - remoteName: Name des Remotes, z.B. `"origin"`.
    /// - Returns: Anzahl der Branches, bei denen Server-SHA ≠ lokaler Remote-Tracking-SHA.
    static func remoteAhead(
        localSignature: [String: String],
        remoteHeads: [String: String],
        remoteName: String
    ) -> Int {
        guard !remoteHeads.isEmpty, !remoteName.isEmpty else { return 0 }
        var count = 0
        for (refname, remoteSha) in remoteHeads {
            // Server: "refs/heads/<branch>" → lokal: "refs/remotes/<remote>/<branch>"
            guard refname.hasPrefix("refs/heads/") else { continue }
            let branch = String(refname.dropFirst("refs/heads/".count))
            let localRef = "refs/remotes/\(remoteName)/\(branch)"
            if localSignature[localRef] != remoteSha {
                count += 1
            }
        }
        return count
    }
}
