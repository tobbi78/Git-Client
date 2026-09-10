//
//  Branch.swift
//  Git-Client
//

import Foundation

struct Branch: Identifiable, Hashable, Sendable {
    let name: String
    let shortName: String  // ohne "origin/" Präfix bei Remote-Branches
    let isCurrent: Bool
    let isRemote: Bool
    let remoteName: String?  // z.B. "origin" für "origin/main"
    let tipSha: String

    var id: String { name }
}
