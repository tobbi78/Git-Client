//
//  BlameView.swift
//  Git-Client
//
//  Sheet-Ansicht für `git blame`: zeigt zeilenweise Autorschaft einer Datei
//  im Zustand eines bestimmten Commits. Klick auf eine Commit-SHA springt in
//  der Hauptliste zu diesem Commit.
//

import SwiftUI

struct BlameView: View {
    let filePath: String?
    let commitShortSha: String?
    let lines: [BlameLine]
    let isLoading: Bool
    let error: String?

    /// Wird aufgerufen wenn der Nutzer auf eine Commit-SHA klickt.
    var onSelectCommit: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Kopfzeile
            header
            Divider()

            // Inhalt
            if isLoading {
                ProgressView("Blame wird geladen…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView(
                    "Fehler beim Laden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                ContentUnavailableView(
                    "Keine Blame-Daten",
                    systemImage: "doc.text.magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                blameTable
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let path = filePath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.headline)
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let sha = commitShortSha {
                    Text("@ \(sha)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Fertig") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Blame-Tabelle

    private var blameTable: some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        BlameRowView(
                            line: line,
                            minWidth: geo.size.width,
                            dateFormatter: Self.dateFormatter
                        ) { sha in
                            onSelectCommit?(sha)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Einzelne Blame-Zeile

private struct BlameRowView: View {
    let line: BlameLine
    let minWidth: CGFloat
    let dateFormatter: DateFormatter
    let onSelectCommit: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Linke Metaspalte: SHA-Button + Autor + Datum
            HStack(spacing: 6) {
                Button(line.shortSha) {
                    onSelectCommit(line.sha)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .help(line.summary.isEmpty ? line.sha : line.summary)

                Text(line.author)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)

                Text(dateFormatter.string(from: line.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(width: 290, alignment: .leading)

            // Trennlinie
            Color.secondary.opacity(0.2).frame(width: 1)

            // Zeilennummer
            Text("\(line.lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.horizontal, 4)

            // Zeileninhalt
            Text(line.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 6)
                .padding(.trailing, 8)
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .padding(.vertical, 1)
        .background(Color.clear)
        .contextMenu {
            Button {
                ClipboardService.copy(line.sha)
            } label: {
                Label("SHA kopieren", systemImage: "doc.on.doc")
            }
        }
    }
}
