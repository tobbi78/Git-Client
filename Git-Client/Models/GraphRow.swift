//
//  GraphRow.swift
//  Git-Client
//

import Foundation
import SwiftUI

nonisolated struct GraphEdge: Sendable {
    let fromLane: Int
    let toLane: Int
    let color: Color
}

nonisolated struct GraphRow: Sendable {
    let commit: Commit
    let lane: Int
    let laneCount: Int       // Gesamtbreite dieser Zeile
    let incoming: [GraphEdge] // Obere Zeilenhälfte: Kanten von oben in den Knoten
    let outgoing: [GraphEdge] // Untere Zeilenhälfte: Kanten vom Knoten nach unten
    let color: Color
}
