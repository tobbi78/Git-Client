//
//  FileHistoryParser.swift
//  Git-Client
//
//  Parst die Ausgabe von `git log --follow --name-status` mit vorangestelltem
//  Datensatz-Marker \u{1d} und dem Format von `GitLogParser`.
//

import Foundation

enum FileHistoryParser {
    /// Marker vor jedem Datensatz (Group Separator).
    nonisolated static let recordMarker = "\u{1d}"

    /// `startPath` ist der Pfad der Datei im ersten (neuesten) Eintrag der Ausgabe.
    /// Er wird bei Umbenennungen nach alt weitergereicht, damit auch Einträge ohne
    /// Status-Zeile (Merges) den passenden Pfad bekommen.
    nonisolated static func parse(_ output: String, startPath: String) -> [FileHistoryEntry] {
        var currentPath = startPath
        var result: [FileHistoryEntry] = []

        for chunk in output.components(separatedBy: recordMarker) {
            guard let separatorEnd = chunk.range(of: "\u{1e}") else { continue }
            let head = String(chunk[..<separatorEnd.upperBound])
            guard let commit = GitLogParser.parse(head).first else { continue }
            let statusPart = String(chunk[separatorEnd.upperBound...])

            var path = currentPath
            var oldPath: String? = nil
            var changeType: DiffFileChangeType = .modified

            let line = statusPart
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            if let line {
                let cols = line.components(separatedBy: "\t")
                let status = cols[0]
                switch status.first {
                case "R" where cols.count >= 3:
                    oldPath = cols[1]
                    path = cols[2]
                    changeType = .renamed
                case "C" where cols.count >= 3:
                    path = cols[2]
                    changeType = .added
                case "A" where cols.count >= 2:
                    path = cols[1]
                    changeType = .added
                case "D" where cols.count >= 2:
                    path = cols[1]
                    changeType = .deleted
                case "M" where cols.count >= 2, "T" where cols.count >= 2:
                    path = cols[1]
                default:
                    break
                }
            }

            result.append(FileHistoryEntry(
                commit: commit, path: path, oldPath: oldPath, changeType: changeType
            ))
            currentPath = oldPath ?? path
        }
        return result
    }
}
