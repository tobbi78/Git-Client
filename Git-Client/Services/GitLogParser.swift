//
//  GitLogParser.swift
//  Git-Client
//
//  Parst die Ausgabe von `git log --pretty=format:<format>` in Commit-Objekte.
//  Feldtrenner \u{1f} (Unit Separator), Datensatzende \u{1e} (Record Separator).
//

import Foundation

enum GitLogParser {
    // Format-String für git log:
    // sha \x1f shortSha \x1f parents \x1f author \x1f email \x1f isoDate \x1f refNames \x1f subject \x1f body \x1e
    static let formatString = "%H\u{1f}%h\u{1f}%P\u{1f}%an\u{1f}%ae\u{1f}%aI\u{1f}%D\u{1f}%s\u{1f}%b\u{1e}"

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated static func parse(_ output: String) -> [Commit] {
        output
            .components(separatedBy: "\u{1e}")
            .compactMap { parseRecord($0) }
    }

    nonisolated private static func parseRecord(_ record: String) -> Commit? {
        let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fields = trimmed.components(separatedBy: "\u{1f}")
        guard fields.count >= 9 else { return nil }

        let sha        = fields[0]
        let shortSha   = fields[1]
        let parents    = fields[2].split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let author     = fields[3]
        let email      = fields[4]
        let dateStr    = fields[5]
        let refNamesRaw = fields[6]
        let subject    = fields[7]
        let body       = fields[8]

        guard !sha.isEmpty else { return nil }

        let date = dateFormatter.date(from: dateStr) ?? Date.distantPast
        let refNames = parseRefNames(refNamesRaw)

        return Commit(
            sha: sha,
            shortSha: shortSha,
            parents: parents,
            author: author,
            authorEmail: email,
            date: date,
            subject: subject,
            body: body,
            refNames: refNames
        )
    }

    // "HEAD -> main, origin/main, tag: v1.0" → ["HEAD -> main", "origin/main", "tag: v1.0"]
    nonisolated private static func parseRefNames(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
