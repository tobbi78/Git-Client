//
//  AppSettings.swift
//  Git-Client
//
//  Zentrale App-Einstellungen, gespeichert in UserDefaults.
//  Wird von RepositoryViewModel (Batch-Größe lesen) und SettingsView
//  (Batch-Größe schreiben) gemeinsam genutzt.
//
//  Injizierbar über `defaults:` statt hartkodiertem UserDefaults.standard, damit
//  Tests eine eigene, isolierte Suite verwenden können und nie die echten
//  App-Einstellungen berühren (siehe withIsolatedSettings in den Tests).
//

import Foundation

nonisolated struct AppSettings {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Produktions-Instanz auf der Standard-Domain.
    static let shared = AppSettings()

    // MARK: - Commit-Batch

    /// UserDefaults-Schlüssel für die Commit-Batch-Größe.
    static let commitBatchSizeKey = "commitBatchSize"

    /// Standardwert: 2000 Commits pro Ladevorgang.
    static let defaultCommitBatchSize = 2000

    /// Mindestgröße; verhindert endlose Mini-Batches bei sehr kleinen Werten.
    static let minimumCommitBatchSize = 100

    /// Aktuell konfigurierte Batch-Größe (mindestens `minimumCommitBatchSize`).
    var commitBatchSize: Int {
        let stored = defaults.integer(forKey: Self.commitBatchSizeKey)
        // integer(forKey:) gibt 0 zurück, wenn der Key nie gesetzt wurde.
        let value = stored > 0 ? stored : Self.defaultCommitBatchSize
        return max(value, Self.minimumCommitBatchSize)
    }

    // MARK: - JIRA

    /// UserDefaults-Schlüssel für die JIRA-Basis-URL.
    static let jiraBaseURLKey = "jiraBaseURL"

    /// UserDefaults-Schlüssel für die gespeicherte JIRA-Projektliste (JSON-Data).
    static let jiraProjectsKey = "jiraProjects"

    /// Aktuell konfigurierte JIRA-Basis-URL (leer wenn nicht gesetzt).
    var jiraBaseURL: String {
        defaults.string(forKey: Self.jiraBaseURLKey) ?? ""
    }

    func setJiraBaseURL(_ url: String) {
        defaults.set(url, forKey: Self.jiraBaseURLKey)
    }

    /// Aktuell konfigurierte JIRA-Projekte.
    var jiraProjects: [JiraProject] {
        guard let data = defaults.data(forKey: Self.jiraProjectsKey) else { return [] }
        return (try? JSONDecoder().decode([JiraProject].self, from: data)) ?? []
    }

    func setJiraProjects(_ projects: [JiraProject]) {
        if let data = try? JSONEncoder().encode(projects) {
            defaults.set(data, forKey: Self.jiraProjectsKey)
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
    var autoRefreshEnabled: Bool {
        // bool(forKey:) gibt false zurück, wenn der Key nie gesetzt wurde —
        // deshalb expliziter Check, ob der Key existiert.
        if defaults.object(forKey: Self.autoRefreshEnabledKey) == nil {
            return Self.defaultAutoRefreshEnabled
        }
        return defaults.bool(forKey: Self.autoRefreshEnabledKey)
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.autoRefreshEnabledKey)
    }

    /// Poll-Intervall in Sekunden. `0` deaktiviert das Remote-Polling (lokales
    /// FSEvent-Watching bleibt aktiv). Mindestens `minimumRemotePollInterval`.
    var remotePollInterval: Int {
        let stored = defaults.integer(forKey: Self.remotePollIntervalKey)
        if stored == 0 {
            // Wert nie gesetzt → Default
            if defaults.object(forKey: Self.remotePollIntervalKey) == nil {
                return Self.defaultRemotePollInterval
            }
            // Explizit auf 0 gesetzt → Remote-Poll aus
            return 0
        }
        return max(stored, Self.minimumRemotePollInterval)
    }

    func setRemotePollInterval(_ seconds: Int) {
        defaults.set(seconds, forKey: Self.remotePollIntervalKey)
    }

    // MARK: - Neuigkeiten außerhalb des Fensters

    /// UserDefaults-Schlüssel: Dock-Badge mit der Zahl der Repos mit Neuigkeiten.
    static let showDockBadgeKey = "showDockBadge"

    /// UserDefaults-Schlüssel: Menu-Bar-Extra mit der Liste der Repos mit Neuigkeiten.
    static let showMenuBarExtraKey = "showMenuBarExtra"

    /// Standardwert: Dock-Badge ist eingeschaltet.
    static let defaultShowDockBadge = true

    /// Standardwert: Menu-Bar-Extra ist eingeschaltet.
    static let defaultShowMenuBarExtra = true

    var showDockBadge: Bool {
        if defaults.object(forKey: Self.showDockBadgeKey) == nil {
            return Self.defaultShowDockBadge
        }
        return defaults.bool(forKey: Self.showDockBadgeKey)
    }

    func setShowDockBadge(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.showDockBadgeKey)
    }

    var showMenuBarExtra: Bool {
        if defaults.object(forKey: Self.showMenuBarExtraKey) == nil {
            return Self.defaultShowMenuBarExtra
        }
        return defaults.bool(forKey: Self.showMenuBarExtraKey)
    }

    func setShowMenuBarExtra(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.showMenuBarExtraKey)
    }

    // MARK: - Anzeige

    /// UserDefaults-Schlüssel: Zeilennummern im Diff anzeigen.
    static let showDiffLineNumbersKey = "showDiffLineNumbers"

    /// Standardwert: Zeilennummern sind eingeblendet.
    static let defaultShowDiffLineNumbers = true

    /// Gibt zurück, ob Zeilennummern im Diff-Patch angezeigt werden sollen.
    var showDiffLineNumbers: Bool {
        if defaults.object(forKey: Self.showDiffLineNumbersKey) == nil {
            return Self.defaultShowDiffLineNumbers
        }
        return defaults.bool(forKey: Self.showDiffLineNumbersKey)
    }

    func setShowDiffLineNumbers(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.showDiffLineNumbersKey)
    }

    // MARK: - Erscheinungsbild

    /// UserDefaults-Schlüssel: Erscheinungsbild (rawValue von AppAppearance).
    static let appearanceKey = "appearance"

    /// Standardwert: dem System folgen.
    static let defaultAppearance: AppAppearance = .system

    /// Aktuell gewähltes Erscheinungsbild.
    var appearance: AppAppearance {
        guard let raw = defaults.string(forKey: Self.appearanceKey),
              let value = AppAppearance(rawValue: raw) else { return Self.defaultAppearance }
        return value
    }

    func setAppearance(_ appearance: AppAppearance) {
        defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
    }
}
