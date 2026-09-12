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
    let id: Int  // Zeilennummer im Hunk
    let type: DiffLineType
    let content: String
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
}

struct CommitDiff: Sendable {
    let sha: String
    let files: [DiffFile]
}
