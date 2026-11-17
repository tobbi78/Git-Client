//
//  BranchParser.swift
//  Git-Client
//
//  Parst die Ausgabe von `git for-each-ref` für Branches und Tags.
//  Rein funktional, kein I/O — vollständig unit-testbar.
//

import Foundation

nonisolated enum BranchParser {

    /// Parst `git for-each-ref --format="%(refname)\t%(objectname)\t%(HEAD)\t%(upstream:short)\t%(upstream:track,nobracket)\t%(committerdate:unix)"`.
    static func parseBranches(from output: String) -> [Branch] {
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
                let lastCommitDate = fields.count >= 6
                    ? TimeInterval(fields[5]).map { Date(timeIntervalSince1970: $0) }
                    : nil

                if refname.hasPrefix("refs/heads/") {
                    let name = String(refname.dropFirst("refs/heads/".count))
                    // Upstream nur setzen, wenn tatsächlich konfiguriert
                    let hasUpstream = !upstreamShort.isEmpty
                    let tracking = hasUpstream ? parseTrack(trackString) : nil
                    return Branch(name: name, shortName: name, isCurrent: isCurrent,
                                  isRemote: false, remoteName: nil, tipSha: sha,
                                  upstreamName: hasUpstream ? upstreamShort : nil,
                                  ahead: tracking?.ahead, behind: tracking?.behind,
                                  lastCommitDate: lastCommitDate)
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
                                  upstreamName: nil, ahead: nil, behind: nil,
                                  lastCommitDate: lastCommitDate)
                }

                return nil
            }
    }

    /// Parst den `%(upstream:track,nobracket)`-String (z.B. „ahead 2, behind 3")
    /// und extrahiert die Anzahl der vorausgehenden / fehlenden Commits.
    /// Bei `gone`, leerem String oder nicht erkanntem Format wird (0, 0) zurückgegeben.
    static func parseTrack(_ track: String) -> (ahead: Int, behind: Int) {
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

    /// Parst `git for-each-ref --format="%(refname:short)\t%(objectname)\t%(*objectname)"`.
    /// `%(*objectname)` liefert den dereferenzierten Commit-SHA bei annotierten Tags;
    /// bei Lightweight-Tags ist es leer → Fallback auf `%(objectname)`.
    static func parseTags(from output: String) -> [GitTag] {
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
}
