//
//  DiffModels.swift
//  Git-Client
//

import Foundation

enum DiffLineType: Sendable {
    case context
    case addition
    case deletion
    case hunkHeader
}

struct DiffLine: Identifiable, Sendable {
    let id: Int  // Index im Hunk
    let type: DiffLineType
    let content: String
    /// Originale Zeilennummer (nil bei Additionen und „\ No newline"-Hinweiszeilen).
    let oldLineNumber: Int?
    /// Neue Zeilennummer (nil bei Deletionen und „\ No newline"-Hinweiszeilen).
    let newLineNumber: Int?
}

struct DiffHunk: Identifiable, Sendable {
    let id: Int
    let header: String
    let lines: [DiffLine]
}

enum DiffFileChangeType: Sendable {
    case added, deleted, modified, renamed
}

struct DiffFile: Identifiable, Sendable {
    let id: Int
    let oldPath: String
    let newPath: String
    let hunks: [DiffHunk]
    let addedLines: Int
    let deletedLines: Int

    var displayName: String {
        if oldPath == newPath { return newPath }
        return "\(oldPath) → \(newPath)"
    }

    var isNew: Bool { oldPath == "/dev/null" }
    var isDeleted: Bool { newPath == "/dev/null" }

    var changeType: DiffFileChangeType {
        if isNew     { return .added }
        if isDeleted { return .deleted }
        if oldPath != newPath { return .renamed }
        return .modified
    }

    /// Höchste vorhandene Zeilennummer im Patch (alt oder neu).
    /// Wird von der View verwendet, um die Spaltenbreite der Zeilennummernspalten zu berechnen.
    var maxLineNumber: Int {
        hunks.flatMap(\.lines)
             .flatMap { [$0.oldLineNumber, $0.newLineNumber] }
             .compactMap { $0 }
             .max() ?? 0
    }
}

struct CommitDiff: Sendable {
    let sha: String
    let files: [DiffFile]
}
