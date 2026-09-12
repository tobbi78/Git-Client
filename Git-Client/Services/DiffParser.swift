//
//  DiffParser.swift
//  Git-Client
//
//  Parst die Ausgabe von `git show --format= --patch <sha>` in DiffFile-Objekte.
//

import Foundation

enum DiffParser {

    nonisolated static func parse(_ output: String, sha: String) -> CommitDiff {
        let lines = output.components(separatedBy: "\n")
        var files: [DiffFile] = []
        var fileIndex = 0

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Neue Datei beginnt mit "diff --git"
            guard line.hasPrefix("diff --git ") else { i += 1; continue }

            var oldPath = ""
            var newPath = ""
            var hunks: [DiffHunk] = []
            var hunkIndex = 0
            var addedLines = 0
            var deletedLines = 0
            i += 1

            // Header-Zeilen überspringen bis zur ersten @@ oder nächstem diff
            while i < lines.count {
                let l = lines[i]
                if l.hasPrefix("--- ") {
                    oldPath = cleanPath(l.dropFirst(4))
                } else if l.hasPrefix("+++ ") {
                    newPath = cleanPath(l.dropFirst(4))
                } else if l.hasPrefix("@@ ") {
                    // Hunk beginnt
                    let hunkHeader = l
                    var hunkLines: [DiffLine] = []
                    var lineIndex = 0
                    i += 1

                    while i < lines.count {
                        let hl = lines[i]
                        if hl.hasPrefix("diff --git ") || hl.hasPrefix("@@ ") {
                            break
                        }
                        let type: DiffLineType
                        if hl.hasPrefix("+") {
                            type = .addition
                            addedLines += 1
                        } else if hl.hasPrefix("-") {
                            type = .deletion
                            deletedLines += 1
                        } else {
                            type = .context
                        }
                        hunkLines.append(DiffLine(id: lineIndex, type: type, content: hl))
                        lineIndex += 1
                        i += 1
                    }

                    hunks.append(DiffHunk(id: hunkIndex, header: hunkHeader, lines: hunkLines))
                    hunkIndex += 1
                    continue
                } else if l.hasPrefix("diff --git ") {
                    break
                }
                i += 1
            }

            if !oldPath.isEmpty || !newPath.isEmpty {
                files.append(DiffFile(
                    id: fileIndex,
                    oldPath: oldPath.isEmpty ? newPath : oldPath,
                    newPath: newPath.isEmpty ? oldPath : newPath,
                    hunks: hunks,
                    addedLines: addedLines,
                    deletedLines: deletedLines
                ))
                fileIndex += 1
            }
        }

        return CommitDiff(sha: sha, files: files)
    }

    private nonisolated static func cleanPath(_ raw: any StringProtocol) -> String {
        var s = String(raw)
        // Entfernt "a/" bzw. "b/" Präfix; "/dev/null" bleibt unverändert
        if s.hasPrefix("a/") || s.hasPrefix("b/") {
            s = String(s.dropFirst(2))
        }
        return s
    }
}
