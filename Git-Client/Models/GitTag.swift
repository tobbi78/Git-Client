//
//  GitTag.swift
//  Git-Client
//

import Foundation

nonisolated struct GitTag: Identifiable, Hashable, Sendable {
    let name: String
    let targetSha: String

    var id: String { name }
}
