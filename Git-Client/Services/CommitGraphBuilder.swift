//
//  CommitGraphBuilder.swift
//  Git-Client
//
//  Lane-Assignment-Algorithmus: Berechnet für jede Commit-Zeile die Spur (Lane)
//  und die Verbindungslinien (Edges) zur nächsten Zeile.
//
//  Eingabe: [Commit] in topologischer Reihenfolge (git log --date-order --all).
//  Ausgabe: [GraphRow] — ein Eintrag pro Commit.
//

import Foundation
import SwiftUI

enum CommitGraphBuilder {

    // Farbpalette für die Spuren (rotiert)
    static let laneColors: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink, .mint, .indigo
    ]

    nonisolated static func build(from commits: [Commit]) -> [GraphRow] {
        // activeLanes[i] = SHA des Commits, den Lane i als nächsten erwartet
        var activeLanes: [String] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            // 1. Lane für diesen Commit bestimmen
            let lane: Int
            if let idx = activeLanes.firstIndex(of: commit.sha) {
                lane = idx
            } else {
                // Neuer Branch — erste freie Lane oder anhängen
                if let free = activeLanes.firstIndex(of: "") {
                    lane = free
                } else {
                    lane = activeLanes.count
                    activeLanes.append("")
                }
            }

            let color = laneColors[lane % laneColors.count]

            // 2. Kanten berechnen (von dieser Zeile zur nächsten)
            var edges: [GraphEdge] = []

            // Alle Lanes außer der eigenen bleiben in ihrer Spur
            for i in 0 ..< activeLanes.count {
                if i == lane { continue }
                let sha = activeLanes[i]
                if sha.isEmpty { continue }
                let edgeColor = laneColors[i % laneColors.count]
                edges.append(GraphEdge(fromLane: i, toLane: i, color: edgeColor))
            }

            // Parents dieses Commits belegen Lanes
            var newActiveLanes = activeLanes
            // Eigene Lane löschen — wird gleich durch ersten Parent ersetzt
            newActiveLanes[lane] = ""

            let parents = commit.parents
            if parents.isEmpty {
                // Root-Commit — Lane bleibt leer
            } else {
                // Erster Parent übernimmt die eigene Lane
                let firstParent = parents[0]
                // Nur setzen wenn der Parent noch nicht in einer anderen Lane ist
                if !newActiveLanes.contains(firstParent) {
                    newActiveLanes[lane] = firstParent
                    edges.append(GraphEdge(fromLane: lane, toLane: lane, color: color))
                } else {
                    // Parent schon in anderer Lane → Merge-Linie dorthin
                    if let targetLane = newActiveLanes.firstIndex(of: firstParent) {
                        edges.append(GraphEdge(fromLane: lane, toLane: targetLane, color: color))
                    }
                }

                // Weitere Parents (Merge-Commits) bekommen neue oder freie Lanes
                for parent in parents.dropFirst() {
                    if newActiveLanes.contains(parent) {
                        // Parent schon aktiv — Kante zu dessen Lane
                        if let targetLane = newActiveLanes.firstIndex(of: parent) {
                            let pColor = laneColors[targetLane % laneColors.count]
                            edges.append(GraphEdge(fromLane: lane, toLane: targetLane, color: pColor))
                        }
                    } else {
                        // Neuen Lane für diesen Parent aufmachen
                        let newLane: Int
                        if let free = newActiveLanes.firstIndex(of: "") {
                            newActiveLanes[free] = parent
                            newLane = free
                        } else {
                            newLane = newActiveLanes.count
                            newActiveLanes.append(parent)
                        }
                        let pColor = laneColors[newLane % laneColors.count]
                        edges.append(GraphEdge(fromLane: lane, toLane: newLane, color: pColor))
                    }
                }
            }

            // Leere Lanes am Ende entfernen
            while newActiveLanes.last == "" {
                newActiveLanes.removeLast()
            }

            let laneCount = max(activeLanes.count, newActiveLanes.count, lane + 1)

            rows.append(GraphRow(
                commit: commit,
                lane: lane,
                laneCount: laneCount,
                edges: edges,
                color: color
            ))

            activeLanes = newActiveLanes
        }

        return rows
    }
}
