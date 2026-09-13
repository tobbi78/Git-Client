//
//  DiffView.swift
//  Git-Client
//
//  Detail-Ansicht für einen ausgewählten Commit:
//  Commit-Header, Dateiliste (links) und Patch (rechts).
//

import SwiftUI

struct DiffView: View {
    let commit: Commit
    let diff: CommitDiff?
    let isLoading: Bool

    @State private var selectedFileID: Int? = nil

    /// Wird aufgerufen, wenn der Nutzer „Blame anzeigen" im Kontextmenü wählt.
    var onBlameRequest: ((String) -> Void)? = nil

    // JIRA-Konfiguration — reagiert automatisch auf Einstellungsänderungen
    @AppStorage(AppSettings.jiraBaseURLKey) private var jiraBaseURL: String = ""

    /// Ticket-Matches für den aktuell angezeigten Commit.
    private var jiraTickets: [JiraTicketMatch] {
        JiraLinker.tickets(
            in: commit.subject + "\n" + commit.body,
            projects: AppSettings.jiraProjects,
            baseURL: jiraBaseURL
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            commitHeader
            Divider()
            if isLoading {
                ProgressView("Diff wird geladen…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let diff {
                diffContent(diff)
            } else {
                ContentUnavailableView(
                    "Kein Diff verfügbar",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Commit-Header

    private var commitHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.subject)
                .font(.headline)
                .textSelection(.enabled)
            if !commit.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(commit.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 16) {
                Label(commit.author, systemImage: "person")
                Label(Self.dateFormatter.string(from: commit.date), systemImage: "calendar")
                Text(commit.shortSha)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // JIRA-Ticket-Links (nur wenn Treffer vorhanden)
            if !jiraTickets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(jiraTickets) { ticket in
                        Link(destination: ticket.url) {
                            Label(ticket.key, systemImage: "link")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(ticket.projectDescription.isEmpty ? ticket.key : ticket.projectDescription)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Diff-Inhalt (Dateiliste + Patch)

    private func diffContent(_ diff: CommitDiff) -> some View {
        HSplitView {
            fileList(diff.files)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
            patchColumn(diff: diff)
        }
        // Explizite Größe damit NSSplitView den vollen verfügbaren Platz nutzt
        // statt sich nach dem intrinsischen Inhalt zu richten.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Extraktion verhindert Group-Wrapper: Frame-Constraints gelten direkt
    // für die Pane-View, sodass NSSplitView die Mindestbreite korrekt ausliest.
    @ViewBuilder
    private func patchColumn(diff: CommitDiff) -> some View {
        if let fileID = selectedFileID,
           let file = diff.files.first(where: { $0.id == fileID }) {
            patchView(file)
                .frame(minWidth: 360, maxWidth: .infinity)
        } else if let first = diff.files.first {
            patchView(first)
                .frame(minWidth: 360, maxWidth: .infinity)
        } else {
            Text("Keine geänderten Dateien.")
                .foregroundStyle(.secondary)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileList(_ files: [DiffFile]) -> some View {
        List(files, selection: $selectedFileID) { file in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: changeTypeIcon(file.changeType))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(changeTypeColor(file.changeType))
                        .frame(width: 13)
                    Text(URL(fileURLWithPath: file.newPath).lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if file.addedLines > 0 {
                        Text("+\(file.addedLines)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if file.deletedLines > 0 {
                        Text("-\(file.deletedLines)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    if file.oldPath != file.newPath {
                        Text(file.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(file.newPath)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .tag(file.id)
            .contextMenu {
                // Blame nur für existierende Dateien (nicht für gelöschte)
                if !file.isDeleted, let blameRequest = onBlameRequest {
                    Button {
                        blameRequest(file.newPath)
                    } label: {
                        Label("Blame anzeigen", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func changeTypeIcon(_ type: DiffFileChangeType) -> String {
        switch type {
        case .added:    return "plus.circle.fill"
        case .deleted:  return "minus.circle.fill"
        case .renamed:  return "arrow.triangle.2.circlepath"
        case .modified: return "pencil.circle.fill"
        }
    }

    private func changeTypeColor(_ type: DiffFileChangeType) -> Color {
        switch type {
        case .added:    return .green
        case .deleted:  return .red
        case .renamed:  return .orange
        case .modified: return .blue
        }
    }

    private func patchView(_ file: DiffFile) -> some View {
        // GeometryReader misst die Breite des sichtbaren Panels (außerhalb der
        // ScrollView). Jede Zeile bekommt minWidth: geo.size.width, damit Zeilen-
        // Hintergründe die volle Panel-Breite füllen — auch wenn der Text kürzer ist.
        // Längere Zeilen überschreiten geo.size.width und aktivieren den H-Scroll.
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(file.hunks) { hunk in
                        Text(hunk.header)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(minWidth: geo.size.width, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))

                        ForEach(hunk.lines) { line in
                            DiffLineView(line: line, minWidth: geo.size.width)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

// MARK: - Einzelne Diff-Zeile

private struct DiffLineView: View {
    let line: DiffLine
    var minWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            Text(marker)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(width: 14, alignment: .center)

            Text(lineContent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 8)
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var marker: String {
        switch line.type {
        case .addition:  return "+"
        case .deletion:  return "-"
        default:         return " "
        }
    }

    private var lineContent: String {
        // Führendes +/- entfernen, Leerzeichen (context) ebenfalls
        guard !line.content.isEmpty else { return "" }
        return String(line.content.dropFirst())
    }

    private var backgroundColor: Color {
        switch line.type {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        default:        return Color.clear
        }
    }

    private var textColor: Color {
        switch line.type {
        case .addition: return Color(nsColor: .labelColor)
        case .deletion: return Color(nsColor: .labelColor)
        default:        return Color(nsColor: .secondaryLabelColor)
        }
    }

    private var markerColor: Color {
        switch line.type {
        case .addition: return .green
        case .deletion: return .red
        default:        return Color(nsColor: .tertiaryLabelColor)
        }
    }
}
