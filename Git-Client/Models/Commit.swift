//
//  Commit.swift
//  Git-Client
//

import Foundation

nonisolated struct Commit: Identifiable, Hashable, Sendable {
    let sha: String
    let shortSha: String
    let parents: [String]
    let author: String
    let authorEmail: String
    let date: Date
    let subject: String
    let body: String
    let refNames: [String]

    var id: String { sha }
}
