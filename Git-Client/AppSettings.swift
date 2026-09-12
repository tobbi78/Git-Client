//
//  AppSettings.swift
//  Git-Client
//
//  Zentrale App-Einstellungen, gespeichert in UserDefaults.
//  Wird von RepositoryViewModel (Batch-Größe lesen) und SettingsView
//  (Batch-Größe schreiben) gemeinsam genutzt.
//

import Foundation

enum AppSettings {
    /// UserDefaults-Schlüssel für die Commit-Batch-Größe.
    static let commitBatchSizeKey = "commitBatchSize"

    /// Standardwert: 2000 Commits pro Ladevorgang.
    static let defaultCommitBatchSize = 2000

    /// Mindestgröße; verhindert endlose Mini-Batches bei sehr kleinen Werten.
    static let minimumCommitBatchSize = 100

    /// Aktuell konfigurierte Batch-Größe (mindestens `minimumCommitBatchSize`).
    static var commitBatchSize: Int {
        let stored = UserDefaults.standard.integer(forKey: commitBatchSizeKey)
        // integer(forKey:) gibt 0 zurück, wenn der Key nie gesetzt wurde.
        let value = stored > 0 ? stored : defaultCommitBatchSize
        return max(value, minimumCommitBatchSize)
    }
}
