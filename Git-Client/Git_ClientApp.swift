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
        }
        .defaultSize(width: 1200, height: 780)

        // Einstellungsfenster (⌘,)
        Settings {
            SettingsView()
        }
    }
}
