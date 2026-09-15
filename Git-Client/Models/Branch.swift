//
//  Branch.swift
//  Git-Client
//

import Foundation

nonisolated struct Branch: Identifiable, Hashable, Sendable {
    let name: String
    let shortName: String  // ohne "origin/" Präfix bei Remote-Branches
    let isCurrent: Bool
    let isRemote: Bool
    let remoteName: String?  // z.B. "origin" für "origin/main"
    let tipSha: String

    // Tracking-Informationen (nur für lokale Branches mit konfiguriertem Upstream)
    let upstreamName: String?  // z.B. "origin/main"; nil wenn kein Tracking-Branch
    let ahead: Int?            // lokale Commits vor dem Upstream (nil = kein Upstream)
    let behind: Int?           // Upstream-Commits, die lokal fehlen (nil = kein Upstream)

    var id: String { name }
}
