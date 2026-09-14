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
            // Immer einen konkreten Wert übergeben (nie nil): SwiftUI wendet nil nicht
            // zuverlässig zurück auf das System-Schema an. Für "Wie System" lesen wir
            // NSApp.effectiveAppearance — das ist bereits korrekt, weil onChange (s.u.)
            // NSApplication.shared.appearance VOR dieser body-Auswertung auf nil setzt.
            .preferredColorScheme(effectiveColorScheme)
            .task {
                applyNSAppearance(appearanceRaw)
            }
            .onChange(of: appearanceRaw) { _, newRaw in
                // NSAppearance VOR dem nächsten body-Lauf setzen, damit effectiveColorScheme
                // beim Re-Render bereits den richtigen Wert von NSApp.effectiveAppearance liest.
                applyNSAppearance(newRaw)
            }
        }
        .defaultSize(width: 1200, height: 780)

        // Einstellungsfenster (⌘,)
        Settings {
            SettingsView()
        }
    }

    /// Effektives Farbschema: für feste Einstellungen (hell/dunkel) direkt; für
    /// "Wie System" aus NSApp.effectiveAppearance abgeleitet — nie nil, damit
    /// SwiftUI stets einen konkreten Wert in die Umgebung schreibt.
    private var effectiveColorScheme: ColorScheme {
        if let scheme = AppAppearance(rawValue: appearanceRaw)?.colorScheme {
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
