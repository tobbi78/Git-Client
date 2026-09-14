//
//  Git_ClientApp.swift
//  Git-Client
//
//  Created by Tobias Florian on 10.09.26.
//

import SwiftUI

// TODO: App-Icon wird auf macOS 26 (Tahoe/Liquid Glass) im Dock nicht korrekt angezeigt.
// Bisherige Schritte: CFBundleIconName gesetzt, PNGs mit Alpha-Kanal (Opaque: False),
// korrekte Pixelgrößen via CGContext. Nächster Ansatz: .iconcomposer-Format (Icon Composer)
// oder vollflächige (nicht vorgeschnittene) Icons testen.
@main
struct Git_ClientApp: App {
    @State private var appModel = AppModel()
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppSettings.defaultAppearance.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if let repository = appModel.openedRepository {
                    MainWindowView(repository: repository)
                } else {
                    RepositoryBrowserView()
                }
            }
            .environment(appModel)
            .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
            .task {
                // Beim ersten Erscheinen NSAppearance synchronisieren, damit semantische
                // NSColor-Werte (z.B. .labelColor) sofort korrekt auflösen.
                applyNSAppearance(appearanceRaw)
            }
            .onChange(of: appearanceRaw) { _, newRaw in
                // Bei jedem Erscheinungsbild-Wechsel AppKit konsistent halten.
                applyNSAppearance(newRaw)
            }
        }
        .defaultSize(width: 1200, height: 780)

        // Einstellungsfenster (⌘,)
        Settings {
            SettingsView()
        }
    }

    /// Setzt NSApplication- und Fenster-Appearance, damit AppKit-Farben
    /// (Color(nsColor:)) sofort und ohne Fokus-Wechsel korrekt auflösen.
    /// NSApplication allein propagiert Änderungen zu Fenstern erst beim
    /// nächsten becomeKey/resignKey-Event — das explizite window.appearance
    /// löst viewDidChangeEffectiveAppearance sofort aus.
    private func applyNSAppearance(_ raw: String) {
        let nsAppearance = AppAppearance(rawValue: raw)?.nsAppearance
        NSApplication.shared.appearance = nsAppearance
        NSApplication.shared.windows.forEach { $0.appearance = nsAppearance }
    }
}
