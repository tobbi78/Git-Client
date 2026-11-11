//
//  FileHistoryEntry.swift
//  Git-Client
//
//  Ein Eintrag der Datei-Historie (`git log --follow`): der Commit plus der
//  Pfad der Datei in diesem Commit.
//

import Foundation

nonisolated struct FileHistoryEntry: Identifiable, Sendable {
    let commit: Commit
    /// Pfad der Datei in diesem Commit.
    let path: String
    /// Vorheriger Pfad, nur bei Umbenennung.
    let oldPath: String?
    let changeType: DiffFileChangeType

    var id: String { commit.sha }

    /// Pfad, unter dem die Datei in älteren Commits weiterverfolgt wird.
    var pathBefore: String { oldPath ?? path }
}
