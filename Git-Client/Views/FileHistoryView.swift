//
//  FileHistoryView.swift
//  Git-Client
//
//  Sheet-Ansicht für die Datei-Historie (`git log --follow`): links die Commits,
//  die die Datei geändert haben, rechts der Diff dieser Datei im gewählten Commit.
//

import SwiftUI

struct FileHistoryView: View {
    let filePath: String?
    let commitShortSha: String?
    let entries: [FileHistoryEntry]
    let isLoading: Bool
    let canLoadMore: Bool
    let error: String?
    let diff: DiffFile?
    let isDiffLoading: Bool
    @Binding var selectedSha: String?

    /// Wird bei Doppelklick bzw. „Zum Commit springen" mit der Commit-SHA aufgerufen.
    var onSelectCommit: ((String) -> Void)? = nil
    /// Wird aufgerufen, wenn das Listenende sichtbar wird und weitere Einträge existieren.
    var onLoadMore: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 560)
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
                    Text("Historie ab @ \(sha)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Zum Commit springen") {
                if let sha = selectedSha { onSelectCommit?(sha) }
            }
            .disabled(selectedSha == nil)
            Button("Fertig") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if let error, entries.isEmpty {
            ContentUnavailableView(
                "Fehler beim Laden",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty && isLoading {
            ProgressView("Historie wird geladen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            ContentUnavailableView(
                "Keine Historie",
                systemImage: "clock.arrow.circlepath"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                entryList
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
                diffPane
                    .frame(minWidth: 360, maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var entryList: some View {
        List(selection: $selectedSha) {
            ForEach(entries) { entry in
                FileHistoryRow(entry: entry, dateFormatter: Self.dateFormatter)
                    .tag(entry.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onSelectCommit?(entry.id) }
                    .contextMenu {
                        Button {
                            ClipboardService.copy(entry.commit.sha)
                        } label: {
                            Label("SHA kopieren", systemImage: "doc.on.doc")
                        }
                    }
            }
            if canLoadMore {
                // Unsichtbarer Trigger: onAppear feuert, sobald das Listenende erreicht ist.
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                    Spacer()
                }
                .onAppear { onLoadMore?() }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var diffPane: some View {
        if isDiffLoading {
            ProgressView("Diff wird geladen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff {
            DiffPatchView(file: diff)
        } else {
            ContentUnavailableView(
                "Kein Diff verfügbar",
                systemImage: "doc.text.magnifyingglass"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Einzelner Eintrag

private struct FileHistoryRow: View {
    let entry: FileHistoryEntry
    let dateFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: entry.changeType.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.changeType.color)
                    .frame(width: 13)
                Text(entry.commit.subject)
                    .font(.callout)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(entry.commit.shortSha)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text(entry.commit.author)
                    .lineLimit(1)
                Text(dateFormatter.string(from: entry.commit.date))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            if let oldPath = entry.oldPath {
                Text("\(oldPath) → \(entry.path)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
