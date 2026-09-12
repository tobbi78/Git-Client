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
                Text(URL(fileURLWithPath: file.newPath).lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text(file.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .tag(file.id)
        }
        .listStyle(.sidebar)
    }

    private func patchView(_ file: DiffFile) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(file.hunks) { hunk in
                    // Hunk-Header
                    Text(hunk.header)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))

                    ForEach(hunk.lines) { line in
                        DiffLineView(line: line)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Einzelne Diff-Zeile

private struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Marker (+/-/ )
            Text(marker)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(width: 14, alignment: .center)

            // Zeileninhalt (ohne führendes +/-/ )
            Text(lineContent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
        }
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
