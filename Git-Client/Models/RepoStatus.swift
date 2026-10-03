//
//  RepoStatus.swift
//  Git-Client
//
//  Wertetyp mit allen Kennzahlen, die pro Repository in der Übersichtsliste angezeigt werden.
//  Rein funktional, kein I/O — vollständig unit-testbar.
//

import Foundation

nonisolated struct RepoStatus: Equatable, Sendable {
    /// Aktuell ausgecheckter Branch (nil = detached HEAD oder unbekannt).
    var currentBranch: String? = nil
    /// Lokale Commits, die noch nicht auf den Server gepusht wurden.
    var aheadCount: Int = 0
    /// Commits auf dem Server, die lokal noch fehlen.
    var behindCount: Int = 0
    /// Upstream für den aktuellen Branch konfiguriert.
    var hasUpstream: Bool = false
    /// Uncommittete Änderungen im Arbeitsverzeichnis.
    var hasUncommittedChanges: Bool = false
    /// Datum des neuesten lokalen Commits (HEAD).
    var lastCommitDate: Date? = nil
    /// Existiert der Repository-Ordner noch auf der Festplatte. Wird einmalig bei der
    /// Aktualisierung dieses Status berechnet (siehe AppModel.refreshLocalStatus), nicht
    /// bei jedem Zeilen-Render in der Übersichtsliste.
    var pathExists: Bool = true

    /// true wenn der Server Commits hat, die lokal fehlen.
    var isBehind: Bool { hasUpstream && behindCount > 0 }

    // MARK: - Reine Helfer (synchron testbar; Typ selbst ist nonisolated)

    /// Gibt zurück, ob `git status --porcelain`-Ausgabe uncommittete Änderungen anzeigt.
    static func parsePorcelainDirty(_ output: String) -> Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Parst `git status --porcelain=v2 --branch` in einem Durchlauf statt drei
    /// separater Aufrufe (currentBranch/hasUncommittedChanges/aheadBehind) — reduziert
    /// die Anzahl der Git-Subprozesse pro Status-Aktualisierung. `lastCommitDate` und
    /// `pathExists` sind in dieser Ausgabe nicht enthalten und bleiben beim Default;
    /// die aufrufende Seite befüllt sie separat.
    static func parsePorcelainV2Branch(_ output: String) -> RepoStatus {
        var status = RepoStatus()
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.currentBranch = (head == "(detached)") ? nil : head
            } else if line.hasPrefix("# branch.ab ") {
                status.hasUpstream = true
                for part in line.dropFirst("# branch.ab ".count).components(separatedBy: " ") {
                    if part.hasPrefix("+"), let n = Int(part.dropFirst()) {
                        status.aheadCount = n
                    } else if part.hasPrefix("-"), let n = Int(part.dropFirst()) {
                        status.behindCount = n
                    }
                }
            } else if !line.isEmpty, !line.hasPrefix("#") {
                status.hasUncommittedChanges = true
            }
        }
        return status
    }

    /// Gecachter Formatter statt einer Neuallokation (inkl. Locale-Aufbau) pro Aufruf —
    /// gleiches Muster wie GitLogParser.dateFormatter.
    nonisolated(unsafe) private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Kompakte deutsche Relativzeitdarstellung eines Datums (z.B. „vor 3 Std.", „vor 2 Tg.").
    static func relativeLabel(from date: Date, to now: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
