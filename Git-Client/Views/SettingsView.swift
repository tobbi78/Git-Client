//
//  SettingsView.swift
//  Git-Client
//
//  App-Einstellungen (⌘,): JIRA-Konfiguration und Commit-Batch-Größe.
//  Zwei Reiter (JIRA zuerst, dann Commits). Änderungen werden erst beim
//  Klick auf „Speichern" übernommen. Wird das Fenster ohne Speichern
//  geschlossen und es gibt Änderungen, erscheint eine Bestätigungs-Warnung.
//

import SwiftUI
import AppKit

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: Commit-Batch (persistiert)
    @AppStorage(AppSettings.commitBatchSizeKey)
    private var savedBatchSize: Int = AppSettings.defaultCommitBatchSize

    // MARK: Draft-State
    @State private var draftBatchText: String = ""
    @State private var draftBaseURL: String = ""
    @State private var draftProjects: [JiraProject] = []
    @State private var selectedProjectID: UUID? = nil

    // MARK: UI-Hilfszustand
    @State private var showMinWarning = false
    @State private var showCloseConfirmation = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Abgeleitete Werte

    private var parsedBatch: Int? {
        Int(draftBatchText.trimmingCharacters(in: .whitespaces))
    }

    private var hasChanges: Bool {
        parsedBatch != savedBatchSize
        || draftBaseURL != AppSettings.jiraBaseURL
        || draftProjects != AppSettings.jiraProjects
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabView {
                jiraTab
                    .tabItem {
                        Label("JIRA", systemImage: "link")
                    }

                commitsTab
                    .tabItem {
                        Label("Commits", systemImage: "list.bullet")
                    }
            }

            Divider()

            // Globaler Speichern / Abbrechen-Bereich
            HStack {
                Spacer()
                Button("Abbrechen") { cancelAndClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") { saveAndClose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsedBatch == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 480)
        .onAppear { syncDraftFromSettings() }
        .onChange(of: savedBatchSize) { _, _ in syncDraftFromSettings() }
        .confirmationDialog(
            "Ungespeicherte Änderungen",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Änderungen verwerfen", role: .destructive) {
                syncDraftFromSettings()
                dismiss()
            }
            Button("Zurück zum Dialog", role: .cancel) { }
        } message: {
            Text("Es gibt ungespeicherte Änderungen. Beim Schließen gehen sie verloren.")
        }
        .background(
            WindowCloseGuard {
                if hasChanges {
                    showCloseConfirmation = true
                    return false
                }
                return true
            }
        )
    }

    // MARK: - Reiter: JIRA

    private var jiraTab: some View {
        Form {
            Section {
                TextField("https://firma.atlassian.net", text: $draftBaseURL)
                    .textFieldStyle(.roundedBorder)

                Text("Basis-URL deines JIRA-Servers. Ticket-Links werden als <Basis-URL>/browse/<KEY-123> geöffnet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Server")
            }

            Section {
                // Projektliste mit editierbaren Zeilen
                VStack(spacing: 0) {
                    // Spaltenheader
                    HStack {
                        Text("Projekt-Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Text("Beschreibung")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                    Divider()

                    // Einträge
                    List(selection: $selectedProjectID) {
                        ForEach($draftProjects) { $project in
                            HStack(spacing: 8) {
                                TextField("KEY", text: $project.key)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .font(.system(.body, design: .monospaced))
                                TextField("Beschreibung (optional)", text: $project.description)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .tag(project.id)
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.bordered)
                    .frame(minHeight: 120, idealHeight: 160)
                    .alternatingRowBackgrounds()

                    Divider()

                    // +/− Buttons
                    HStack(spacing: 0) {
                        Button {
                            let newProject = JiraProject()
                            draftProjects.append(newProject)
                            selectedProjectID = newProject.id
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .help("Neues Projekt hinzufügen")

                        Button {
                            if let sel = selectedProjectID {
                                draftProjects.removeAll { $0.id == sel }
                                selectedProjectID = nil
                            }
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedProjectID == nil)
                        .help("Ausgewähltes Projekt entfernen")

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

                Text("Erkennt Ticket-Keys wie PROJ-123 in Commit-Nachrichten und zeigt sie als klickbare Links im Commit-Detail an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Projekte")
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 4)
    }

    // MARK: - Reiter: Commits

    private var commitsTab: some View {
        Form {
            Section {
                HStack {
                    TextField("", text: $draftBatchText)
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
        .padding(.bottom, 4)
    }

    // MARK: - Aktionen

    private func syncDraftFromSettings() {
        draftBatchText = "\(savedBatchSize)"
        draftBaseURL   = AppSettings.jiraBaseURL
        draftProjects  = AppSettings.jiraProjects
    }

    private func saveAndClose() {
        guard let value = parsedBatch else { return }

        // Batch-Größe
        let clamped = max(value, AppSettings.minimumCommitBatchSize)
        if clamped != value {
            showMinWarning = true
            draftBatchText = "\(clamped)"
            Task {
                try? await Task.sleep(for: .seconds(3))
                showMinWarning = false
            }
        }
        savedBatchSize = clamped

        // JIRA
        AppSettings.setJiraBaseURL(draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        AppSettings.setJiraProjects(draftProjects.filter {
            !$0.key.trimmingCharacters(in: .whitespaces).isEmpty
        })

        syncDraftFromSettings()
        dismiss()
    }

    private func cancelAndClose() {
        syncDraftFromSettings()
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
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
        }

        func attach(to window: NSWindow?) {
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
