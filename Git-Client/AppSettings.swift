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

    // MARK: - Commit-Batch

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

    // MARK: - JIRA

    /// UserDefaults-Schlüssel für die JIRA-Basis-URL.
    static let jiraBaseURLKey = "jiraBaseURL"

    /// UserDefaults-Schlüssel für die gespeicherte JIRA-Projektliste (JSON-Data).
    static let jiraProjectsKey = "jiraProjects"

    /// Aktuell konfigurierte JIRA-Basis-URL (leer wenn nicht gesetzt).
    static var jiraBaseURL: String {
        UserDefaults.standard.string(forKey: jiraBaseURLKey) ?? ""
    }

    static func setJiraBaseURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: jiraBaseURLKey)
    }

    /// Aktuell konfigurierte JIRA-Projekte.
    static var jiraProjects: [JiraProject] {
        guard let data = UserDefaults.standard.data(forKey: jiraProjectsKey) else { return [] }
        return (try? JSONDecoder().decode([JiraProject].self, from: data)) ?? []
    }

    static func setJiraProjects(_ projects: [JiraProject]) {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: jiraProjectsKey)
        }
    }
}
