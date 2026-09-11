//
//  CloneRepositoryView.swift
//  Git-Client
//
//  Sheet zum Klonen eines HTTPS-Git-Repositories.
//  Das Passwort/Token verlässt dieses View nie als Klartext —
//  es wird direkt an AppModel.cloneRepository übergeben und von
//  dort im Keychain abgelegt (nie in bookmarks.json).
//

import SwiftUI

struct CloneRepositoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var remoteURL = ""
    @State private var localParentPath: URL? = nil
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isCloning = false
    @State private var errorMessage: String? = nil

    private var canClone: Bool {
        !remoteURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        localParentPath != nil &&
        !effectiveName.isEmpty &&
        !isCloning
    }

    private var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return URL(string: remoteURL)?
            .deletingPathExtension()
            .lastPathComponent ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Repository klonen")
                .font(.headline)

            // Remote URL
            LabeledContent("Remote URL") {
                TextField("https://github.com/owner/repo.git", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: remoteURL) { _, url in
                        if name.trimmingCharacters(in: .whitespaces).isEmpty {
                            name = URL(string: url)?.deletingPathExtension().lastPathComponent ?? ""
                        }
                    }
            }

            // Zielordner
            LabeledContent("Zielordner") {
                HStack {
                    Text(localParentPath?.path ?? "Kein Ordner gewählt")
                        .foregroundStyle(localParentPath == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Wählen…") { pickLocalParent() }
                }
            }

            // Name des Ordners
            LabeledContent("Ordnername") {
                TextField(
                    URL(string: remoteURL)?.deletingPathExtension().lastPathComponent ?? "repo",
                    text: $name
                )
                .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Credentials (optional — für private Repos)
            Group {
                Text("Zugangsdaten (optional, nur für private Repositories)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Benutzername") {
                    TextField("Benutzername", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Passwort / Token") {
                    SecureField("Passwort oder Personal Access Token", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Fehlermeldung
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            HStack {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isCloning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }
                Button("Klonen") { startClone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canClone)
            }
        }
        .padding(24)
        .frame(minWidth: 480)
    }

    // MARK: - Aktionen

    private func pickLocalParent() {
        let panel = NSOpenPanel()
        panel.title = "Zielordner wählen"
        panel.message = "Wähle den Ordner, in dem das Repository angelegt wird."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localParentPath = url
    }

    private func startClone() {
        guard let parent = localParentPath else { return }
        let localPath = parent.appendingPathComponent(effectiveName)
        isCloning = true
        errorMessage = nil
        Task {
            do {
                try await appModel.cloneRepository(
                    remoteURL: remoteURL.trimmingCharacters(in: .whitespaces),
                    to: localPath,
                    name: effectiveName,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCloning = false
        }
    }
}

#Preview {
    CloneRepositoryView()
        .environment(AppModel())
}
