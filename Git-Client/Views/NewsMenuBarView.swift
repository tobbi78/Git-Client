//
//  NewsMenuBarView.swift
//  Git-Client
//
//  Inhalt des Menu-Bar-Extras: Liste der Repositories mit Neuigkeiten.
//

import SwiftUI

struct NewsMenuBarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let repos = appModel.repositoriesWithNews

        if repos.isEmpty {
            Text("Keine neuen Commits")
        } else {
            ForEach(repos) { repo in
                Button {
                    appModel.openRepository(repo)
                    showMainWindow()
                } label: {
                    let summary = appModel.newCommitStatus[repo.id]?.summary ?? ""
                    Text(summary.isEmpty ? repo.name : "\(repo.name) — \(summary)")
                }
            }
        }

        Divider()

        Button("Git-Client öffnen") {
            showMainWindow()
        }
    }

    /// Holt die App nach vorn und öffnet das Hauptfenster, falls keines sichtbar ist.
    private func showMainWindow() {
        NSApp.activate()
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if !hasVisibleWindow {
            openWindow(id: "main")
        }
    }
}
