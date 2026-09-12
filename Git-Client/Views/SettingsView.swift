//
//  SettingsView.swift
//  Git-Client
//
//  App-Einstellungen (⌘,): aktuell nur die Commit-Batch-Größe für das Lazy Loading.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.commitBatchSizeKey)
    private var batchSize: Int = AppSettings.defaultCommitBatchSize

    // Lokaler Puffer damit der Nutzer tippend eingeben kann, ohne dass
    // nach jeder Ziffer UserDefaults und ViewModel aktualisiert werden.
    @State private var batchSizeText: String = ""
    @State private var showMinWarning = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("", text: $batchSizeText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { applyBatchSize() }
                        .onAppear { batchSizeText = "\(batchSize)" }

                    Text("Commits pro Ladevorgang")
                        .foregroundStyle(.primary)
                }

                if showMinWarning {
                    Text("Mindestwert: \(AppSettings.minimumCommitBatchSize) Commits")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Beim Öffnen eines Repositories werden zunächst so viele Commits geladen. Scrollt man ans Ende der Liste, wird die nächste Gruppe nachgeladen. Die Änderung greift beim nächsten Öffnen oder Neu-Laden eines Repositories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Commit-Liste")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
        .onChange(of: batchSize) { _, newValue in
            batchSizeText = "\(newValue)"
        }
    }

    private func applyBatchSize() {
        guard let value = Int(batchSizeText.trimmingCharacters(in: .whitespaces)) else {
            batchSizeText = "\(batchSize)"
            return
        }
        if value < AppSettings.minimumCommitBatchSize {
            batchSize = AppSettings.minimumCommitBatchSize
            batchSizeText = "\(AppSettings.minimumCommitBatchSize)"
            showMinWarning = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                showMinWarning = false
            }
        } else {
            batchSize = value
            showMinWarning = false
        }
    }
}

#Preview {
    SettingsView()
}
