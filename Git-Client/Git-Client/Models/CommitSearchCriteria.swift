//
//  CommitSearchCriteria.swift
//  Git-Client
//
//  Wertetyp für die Commit-Suchfilter.
//  Wird vom RepositoryViewModel verwendet, um GitService.searchCommits() auszulösen.
//

import Foundation

nonisolated struct CommitSearchCriteria: Equatable, Sendable {
    var message: String = ""
    var author:  String = ""
    var since:   Date?  = nil
    var until:   Date?  = nil
    var sha:     String = ""

    /// true, wenn mindestens ein Kriterium gesetzt ist.
    var isActive: Bool {
        !message.trimmed.isEmpty
        || !author.trimmed.isEmpty
        || since  != nil
        || until  != nil
        || !sha.trimmed.isEmpty
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
