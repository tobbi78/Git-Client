//
//  JiraLinker.swift
//  Git-Client
//
//  Sucht JIRA-Ticket-Keys der konfigurierten Projekte in einem Text und
//  baut daraus Browse-URLs der Form <baseURL>/browse/<KEY-123>.
//  Alle Methoden sind nonisolated und rein funktional — gut testbar ohne App-Kontext.
//

import Foundation

// MARK: - Treffer-Typ

struct JiraTicketMatch: Equatable, Identifiable, Sendable {
    /// Vollständiger Ticket-Key, z.B. „PROJ-123"
    let key: String
    /// Browser-URL, z.B. https://firma.atlassian.net/browse/PROJ-123
    let url: URL
    /// Beschreibung des JIRA-Projekts (für den Tooltip)
    let projectDescription: String

    var id: String { key }
}

// MARK: - Linker

enum JiraLinker {

    /// Findet Tickets der in `projects` konfigurierten Projekte im `text` und baut
    /// die Browse-URLs. Gibt Treffer in Reihenfolge ihres Auftretens zurück,
    /// dedupliziert nach Ticket-Key.
    ///
    /// - Parameter text:     Commit-Subject + Body (o.ä.)
    /// - Parameter projects: Konfigurierte JIRA-Projekte aus `AppSettings`.
    /// - Parameter baseURL:  JIRA-Basis-URL aus `AppSettings` (mit oder ohne „/"-Suffix).
    /// - Returns: Geordnete, deduplizierte Liste von `JiraTicketMatch`.
    static func tickets(
        in text: String,
        projects: [JiraProject],
        baseURL: String
    ) -> [JiraTicketMatch] {
        // Leere oder fehlende Basis-URL → keine Links möglich
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { return [] }

        var seen = Set<String>()
        var results: [JiraTicketMatch] = []

        for project in projects {
            let trimmedKey = project.key.trimmingCharacters(in: .whitespaces)
            guard !trimmedKey.isEmpty else { continue }

            // Muster: kein Buchstabe/Ziffer davor, dann KEY-<Zahl>
            let escaped = NSRegularExpression.escapedPattern(for: trimmedKey)
            let pattern = "(?<![A-Za-z0-9])\(escaped)-(\\d+)"

            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let fullKey = String(text[range])
                guard !seen.contains(fullKey) else { continue }
                seen.insert(fullKey)

                let urlString = "\(base)/browse/\(fullKey)"
                guard let url = URL(string: urlString) else { continue }

                results.append(JiraTicketMatch(
                    key: fullKey,
                    url: url,
                    projectDescription: project.description
                ))
            }
        }

        return results
    }
}
