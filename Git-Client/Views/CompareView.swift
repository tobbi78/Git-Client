//
//  CompareView.swift
//  Git-Client
//
//  Sheet-Ansicht zum Vergleich zweier beliebiger Stände (Branch, Tag oder SHA):
//  Kopfzeile mit Auswahl beider Seiten, darunter Dateiliste und Patch.
//

import SwiftUI

struct CompareView: View {
    @Binding var base: String
    @Binding var target: String
    @Binding var sinceMergeBase: Bool
    let localBranches: [String]
    let remoteBranches: [String]
    let tags: [String]
    let resolved: (base: String, target: String)?
    let diff: CommitDiff?
    let isLoading: Bool
    let error: String?

    /// Wird aufgerufen, wenn der Vergleich neu berechnet werden soll.
    var onCompare: (() -> Void)? = nil
    var onSwap: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                refField("Basis (A)", text: $base)
                Button {
                    onSwap?()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Basis und Ziel tauschen")
                refField("Ziel (B)", text: $target)
            }
            HStack(spacing: 12) {
                Picker("Art", selection: $sinceMergeBase) {
                    Text("Seit Abzweigung (A...B)").tag(true)
                    Text("Direkt (A..B)").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .onChange(of: sinceMergeBase) { _, _ in onCompare?() }
                summary
                Spacer()
                Button("Vergleichen") { onCompare?() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(base.trimmingCharacters(in: .whitespaces).isEmpty
                              || target.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func refField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { onCompare?() }
            Menu {
                Button("HEAD") { select("HEAD", into: text) }
                section("Lokale Branches", localBranches, into: text)
                section("Remote-Branches", remoteBranches, into: text)
                section("Tags", tags, into: text)
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Branch oder Tag auswählen")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ names: [String], into text: Binding<String>) -> some View {
        if !names.isEmpty {
            Section(title) {
                ForEach(names, id: \.self) { name in
                    Button(name) { select(name, into: text) }
                }
            }
        }
    }

    private func select(_ name: String, into text: Binding<String>) {
        text.wrappedValue = name
        onCompare?()
    }

    @ViewBuilder
    private var summary: some View {
        if let resolved, let diff {
            let added = diff.files.reduce(0) { $0 + $1.addedLines }
            let deleted = diff.files.reduce(0) { $0 + $1.deletedLines }
            HStack(spacing: 6) {
                Text("\(resolved.base.prefix(7)) → \(resolved.target.prefix(7))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(diff.files.count) Dateien")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("+\(added)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                Text("-\(deleted)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Vergleich wird geladen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView(
                "Vergleich nicht möglich",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff {
            if diff.files.isEmpty {
                ContentUnavailableView(
                    "Keine Unterschiede",
                    systemImage: "equal.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffFilesView(diff: diff)
            }
        } else {
            ContentUnavailableView(
                "Zwei Stände wählen",
                systemImage: "arrow.left.arrow.right",
                description: Text("Wähle Basis und Ziel und starte den Vergleich.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
