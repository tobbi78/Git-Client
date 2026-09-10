//
//  GraphRow.swift
//  Git-Client
//

import Foundation
import SwiftUI

struct GraphEdge: Sendable {
    let fromLane: Int
    let toLane: Int
    let color: Color
}

struct GraphRow: Sendable {
    let commit: Commit
    let lane: Int
    let laneCount: Int   // Gesamtbreite dieser Zeile
    let edges: [GraphEdge]
    let color: Color
}
