//
//  SettingsView.swift
//  Git-Client
//
//  App-Einstellungen (⌘,): Commit-Batch-Größe für das Lazy Loading.
//  Änderungen werden erst beim Klick auf „Speichern" übernommen.
//  Wird das Fenster ohne Speichern geschlossen und es gibt Änderungen,
//  erscheint eine Bestätigungs-Warnung.
//

import SwiftUI
import AppKit

// MARK: - SettingsView

struct SettingsView: View {

    // Persistierter Wert (UserDefaults) — Quelle der Wahrheit
    @AppStorage(AppSettings.commitBatchSizeKey)
    private var savedBatchSize: Int = AppSettings.defaultCommitBatchSize

    // Lokaler Entwurf — wird erst beim Speichern nach UserDefaults geschrieben
    @State private var draftText: String = ""
    @State private var showMinWarning = false
    @State private var showCloseConfirmation = false

    @Environment(\.dismiss) private var dismiss

    // MARK: Abgeleitete Werte

    private var parsedDraft: Int? {
        Int(draftText.trimmingCharacters(in: .whitespaces))
    }

    /// true wenn der eingetippte Wert vom gespeicherten Wert abweicht.
    private var hasChanges: Bool {
        parsedDraft != savedBatchSize
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("", text: $draftText)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)

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

            Divider()

            // Speichern / Abbrechen
            HStack {
                Spacer()
                Button("Abbrechen") { cancelAndClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") { saveAndClose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedDraft == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        // Draft beim (erneuten) Öffnen des Einstellungs-Fensters synchronisieren
        .onAppear { draftText = "\(savedBatchSize)" }
        .onChange(of: savedBatchSize) { _, newValue in draftText = "\(newValue)" }
        // Warnung bei ungespeicherten Änderungen
        .confirmationDialog(
            "Ungespeicherte Änderungen",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Änderungen verwerfen", role: .destructive) {
                // Draft zurücksetzen → Guard lässt das Schließen zu
                draftText = "\(savedBatchSize)"
                dismiss()
            }
            Button("Zurück zum Dialog", role: .cancel) { }
        } message: {
            Text("Die geänderte Batch-Größe wurde nicht gespeichert. Beim Schließen gehen die Änderungen verloren.")
        }
        // Fenster-Schließen-Button abfangen (AppKit-Brücke)
        .background(
            WindowCloseGuard {
                if hasChanges {
                    showCloseConfirmation = true
                    return false    // Schließen vorerst verhindern
                }
                return true         // keine Änderung → normal schließen
            }
        )
    }

    // MARK: Aktionen

    private func saveAndClose() {
        guard let value = parsedDraft else { return }
        let clamped = max(value, AppSettings.minimumCommitBatchSize)
        if clamped != value {
            // Eingabe wurde auf Mindestwert korrigiert → kurzen Hinweis zeigen
            showMinWarning = true
            draftText = "\(clamped)"
            Task {
                try? await Task.sleep(for: .seconds(3))
                showMinWarning = false
            }
        }
        savedBatchSize = clamped    // → UserDefaults
        // Draft synchronisieren, damit der Guard beim dismiss keine Änderung mehr sieht
        draftText = "\(clamped)"
        dismiss()
    }

    private func cancelAndClose() {
        // Draft zurücksetzen → Guard (windowShouldClose) lässt das Schließen zu
        draftText = "\(savedBatchSize)"
        dismiss()
    }
}

// MARK: - WindowCloseGuard

/// Minimale AppKit-Brücke: setzt sich als NSWindowDelegate und ruft `shouldClose` auf,
/// wenn der Nutzer das Fenster über den roten Schließen-Button (oder ⌘W) zu schließen
/// versucht. Bei `false` wird das Schließen verhindert.
private struct WindowCloseGuard: NSViewRepresentable {
    var shouldClose: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldClose: shouldClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Das Fenster ist erst nach dem Einhängen in die View-Hierarchie verfügbar.
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
        // Bei SwiftUI-Updates erneut einhängen (falls Fenster nach makeNSView gesetzt wurde)
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
        }

        func attach(to window: NSWindow?) {
            // delegate ist weak in NSWindow → der Coordinator hält sich selbst
            // über den NSViewRepresentable-Lebenszyklus am Leben.
            window?.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldClose()
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
