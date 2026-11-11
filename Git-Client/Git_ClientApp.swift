//
//  Git_ClientApp.swift
//  Git-Client
//
//  Created by Tobias Florian on 10.09.26.
//

import SwiftUI

@main
struct Git_ClientApp: App {
    @State private var appModel = AppModel()
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppSettings.defaultAppearance.rawValue
    @AppStorage(AppSettings.showMenuBarExtraKey) private var showMenuBarExtra = AppSettings.defaultShowMenuBarExtra
    @AppStorage(AppSettings.showDockBadgeKey) private var showDockBadge = AppSettings.defaultShowDockBadge

    // Explizit gespeichertes Farbschema: nie nil — onChange setzt es VOR dem nächsten
    // Render-Lauf, damit .preferredColorScheme immer einen konkreten Wert bekommt.
    // Der Initialwert darf NSApp NICHT nutzen (noch nil beim App-Start) — für
    // "Wie System" wird stattdessen der System-UserDefaults-Schlüssel gelesen.
    @State private var resolvedScheme: ColorScheme = {
        let raw = UserDefaults.standard.string(forKey: AppSettings.appearanceKey)
            ?? AppSettings.defaultAppearance.rawValue
        if let scheme = AppAppearance(rawValue: raw)?.colorScheme {
            return scheme
        }
        // System: AppleInterfaceStyle == "Dark" → Dunkel, sonst Hell
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            ? .dark : .light
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if let repository = appModel.openedRepository {
                    MainWindowView(repository: repository)
                } else {
                    RepositoryBrowserView()
                }
            }
            .environment(appModel)
            .preferredColorScheme(resolvedScheme)
            .task {
                applyNSAppearance(appearanceRaw)
                resolvedScheme = Self.computeScheme(appearanceRaw)
            }
            .onChange(of: showDockBadge) { _, _ in
                // Schalter in den Einstellungen wirkt sofort.
                appModel.updateDockBadge()
            }
            .onChange(of: appearanceRaw) { _, newRaw in
                // applyNSAppearance VOR computeScheme: NSApp.effectiveAppearance
                // spiegelt nach dem Setzen von NSApp.appearance sofort den neuen Wert.
                applyNSAppearance(newRaw)
                resolvedScheme = Self.computeScheme(newRaw)
            }
            .overlay {
                if appModel.isCommandPaletteOpen {
                    CommandPaletteView()
                }
            }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandMenu("Navigation") {
                Button("Befehlspalette") {
                    appModel.isCommandPaletteOpen.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        // Statistik-Fenster — geöffnet per openWindow(id: "repo-statistics", value: bookmark)
        WindowGroup(id: "repo-statistics", for: RepositoryBookmark.self) { $bookmark in
            if let repo = bookmark {
                NavigationStack {
                    StatisticsView(repository: repo)
                }
            }
        }
        .defaultSize(width: 900, height: 700)

        // Menu-Bar-Extra: Repos mit Neuigkeiten (abschaltbar in den Einstellungen)
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            NewsMenuBarView()
                .environment(appModel)
        } label: {
            let count = appModel.newsRepositoryCount
            if count > 0 {
                Label("\(count)", systemImage: "arrow.triangle.branch")
            } else {
                Image(systemName: "arrow.triangle.branch")
            }
        }

        // Einstellungsfenster (⌘,)
        Settings {
            SettingsView()
        }
    }

    /// Leitet den ColorScheme-Wert aus dem rawValue ab. Für „Wie System" wird
    /// NSApp.effectiveAppearance herangezogen — nach applyNSAppearance bereits korrekt.
    private static func computeScheme(_ raw: String) -> ColorScheme {
        if let scheme = AppAppearance(rawValue: raw)?.colorScheme {
            return scheme
        }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark : .light
    }

    /// Setzt NSApplication- und Fenster-Appearance, damit AppKit-Farben
    /// (Color(nsColor:)) sofort und ohne Fokus-Wechsel korrekt auflösen.
    private func applyNSAppearance(_ raw: String) {
        let nsAppearance = AppAppearance(rawValue: raw)?.nsAppearance
        NSApplication.shared.appearance = nsAppearance
        NSApplication.shared.windows.forEach { $0.appearance = nsAppearance }
    }
}
