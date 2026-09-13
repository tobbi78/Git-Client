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

    // MARK: - Auto-Refresh

    /// UserDefaults-Schlüssel für das Aktivieren des Auto-Refresh.
    static let autoRefreshEnabledKey = "autoRefreshEnabled"

    /// UserDefaults-Schlüssel für das Remote-Poll-Intervall (in Sekunden).
    static let remotePollIntervalKey = "remotePollInterval"

    /// Standardwert: Auto-Refresh ist eingeschaltet.
    static let defaultAutoRefreshEnabled = true

    /// Standardwert: alle 5 Minuten auf Remote-Refs prüfen.
    static let defaultRemotePollInterval = 300

    /// Mindestwert für das Remote-Poll-Intervall (verhindert zu häufige Netzwerkanfragen).
    static let minimumRemotePollInterval = 60

    /// Gibt zurück, ob der Auto-Refresh aktiv sein soll.
    static var autoRefreshEnabled: Bool {
        // bool(forKey:) gibt false zurück, wenn der Key nie gesetzt wurde —
        // deshalb expliziter Check, ob der Key existiert.
        if UserDefaults.standard.object(forKey: autoRefreshEnabledKey) == nil {
            return defaultAutoRefreshEnabled
        }
        return UserDefaults.standard.bool(forKey: autoRefreshEnabledKey)
    }

    static func setAutoRefreshEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: autoRefreshEnabledKey)
    }

    /// Poll-Intervall in Sekunden. `0` deaktiviert das Remote-Polling (lokales
    /// FSEvent-Watching bleibt aktiv). Mindestens `minimumRemotePollInterval`.
    static var remotePollInterval: Int {
        let stored = UserDefaults.standard.integer(forKey: remotePollIntervalKey)
        if stored == 0 {
            // Wert nie gesetzt → Default
            if UserDefaults.standard.object(forKey: remotePollIntervalKey) == nil {
                return defaultRemotePollInterval
            }
            // Explizit auf 0 gesetzt → Remote-Poll aus
            return 0
        }
        return max(stored, minimumRemotePollInterval)
    }

    static func setRemotePollInterval(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: remotePollIntervalKey)
    }
}
