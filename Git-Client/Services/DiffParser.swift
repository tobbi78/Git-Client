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

                    // Startzeilennummern aus dem Hunk-Header ermitteln
                    let startNums = parseHunkHeader(hunkHeader)
                    var oldNo = startNums?.oldStart ?? 0
                    var newNo = startNums?.newStart ?? 0
                    let hasNumbers = startNums != nil
                    i += 1

                    while i < lines.count {
                        let hl = lines[i]
                        if hl.hasPrefix("diff --git ") || hl.hasPrefix("@@ ") {
                            break
                        }

                        // „\ No newline at end of file" — Hinweiszeile, keine Nummer, kein Increment
                        if hl.hasPrefix("\\") {
                            hunkLines.append(DiffLine(id: lineIndex, type: .context, content: hl,
                                                      oldLineNumber: nil, newLineNumber: nil))
                            lineIndex += 1
                            i += 1
                            continue
                        }

                        let type: DiffLineType
                        let oldNum: Int?
                        let newNum: Int?
                        if hl.hasPrefix("+") {
                            type = .addition
                            addedLines += 1
                            oldNum = nil
                            newNum = hasNumbers ? newNo : nil
                            newNo += 1
                        } else if hl.hasPrefix("-") {
                            type = .deletion
                            deletedLines += 1
                            oldNum = hasNumbers ? oldNo : nil
                            newNum = nil
                            oldNo += 1
                        } else {
                            type = .context
                            oldNum = hasNumbers ? oldNo : nil
                            newNum = hasNumbers ? newNo : nil
                            oldNo += 1
                            newNo += 1
                        }
                        hunkLines.append(DiffLine(id: lineIndex, type: type, content: hl,
                                                  oldLineNumber: oldNum, newLineNumber: newNum))
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

    /// Liest die Startzeilennummern aus einem Hunk-Header.
    ///
    /// Erwartet das Format `@@ -<oldStart>[,<oldCount>] +<newStart>[,<newCount>] @@[ context]`.
    /// Gibt `nil` zurück, wenn der Header nicht dem erwarteten Format entspricht.
    ///
    /// Beispiele:
    /// - `"@@ -10,7 +12,9 @@"`  → `(oldStart: 10, newStart: 12)`
    /// - `"@@ -1 +1 @@"`        → `(oldStart: 1, newStart: 1)`
    /// - `"@@ -0,0 +1 @@"`      → `(oldStart: 0, newStart: 1)`
    nonisolated static func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int)? {
        // Format: "@@ -<old>[,<n>] +<new>[,<m>] @@"
        guard header.hasPrefix("@@ ") else { return nil }

        // Erste Zahl nach "-"
        guard let minusRange = header.range(of: "-"),
              let plusRange  = header.range(of: "+", range: minusRange.upperBound..<header.endIndex)
        else { return nil }

        let oldPart = header[minusRange.upperBound...]
            .prefix(while: { $0.isNumber || $0 == "," })
        let newPart = header[plusRange.upperBound...]
            .prefix(while: { $0.isNumber || $0 == "," })

        guard let oldStart = Int(oldPart.prefix(while: { $0.isNumber })),
              let newStart = Int(newPart.prefix(while: { $0.isNumber }))
        else { return nil }

        return (oldStart: oldStart, newStart: newStart)
    }
}
