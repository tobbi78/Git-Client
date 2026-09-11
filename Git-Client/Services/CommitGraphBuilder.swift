//
//  CommitGraphBuilder.swift
//  Git-Client
//
//  Lane-Assignment-Algorithmus. Berechnet für jede Zeile:
//  - lane:     welche Spur der Commit belegt
//  - incoming: Kanten obere Hälfte (von vorheriger Zeile in den Knoten)
//  - outgoing: Kanten untere Hälfte (vom Knoten in nächste Zeile)
//
//  Kein Lücken-Problem mehr: jede Zeile zeichnet BEIDE Hälften aller
//  aktiven Lanes, nicht nur die Knotenzeile.
//

import Foundation
import SwiftUI

enum CommitGraphBuilder {

    nonisolated static let laneColors: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink, .mint, .indigo
    ]

    nonisolated static func build(from commits: [Commit]) -> [GraphRow] {
        var activeLanes: [String] = []   // activeLanes[i] = SHA, den Lane i als nächsten erwartet
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {

            // 1. Lane für diesen Commit bestimmen
            let lane: Int
            if let idx = activeLanes.firstIndex(of: commit.sha) {
                lane = idx
            } else if let free = activeLanes.firstIndex(of: "") {
                lane = free
            } else {
                lane = activeLanes.count
                activeLanes.append("")
            }

            let color = laneColors[lane % laneColors.count]

            // 2. INCOMING-Kanten (obere Hälfte: activeLanes-Snapshot VOR Mutation)
            //    Jede belegte Lane muss oben gezeichnet werden, damit keine Lücken entstehen.
            var incoming: [GraphEdge] = []
            for i in 0 ..< activeLanes.count {
                let sha = activeLanes[i]
                guard !sha.isEmpty else { continue }
                let edgeColor = laneColors[i % laneColors.count]
                if sha == commit.sha {
                    // Diese Lane war auf diesen Commit gerichtet → konvergiert zum Knoten
                    incoming.append(GraphEdge(fromLane: i, toLane: lane, color: edgeColor))
                } else {
                    // Durchlauf-Lane → gerade durch
                    incoming.append(GraphEdge(fromLane: i, toLane: i, color: edgeColor))
                }
            }

            // 3. OUTGOING-Kanten (untere Hälfte) + activeLanes mutieren
            var outgoing: [GraphEdge] = []
            var newActiveLanes = activeLanes
            newActiveLanes[lane] = ""   // eigene Lane freigeben, wird gleich neu belegt

            // Pass-through Lanes
            for i in 0 ..< activeLanes.count {
                if i == lane { continue }
                let sha = activeLanes[i]
                guard !sha.isEmpty else { continue }
                let edgeColor = laneColors[i % laneColors.count]
                outgoing.append(GraphEdge(fromLane: i, toLane: i, color: edgeColor))
            }

            let parents = commit.parents
            if !parents.isEmpty {
                let firstParent = parents[0]
                if !newActiveLanes.contains(firstParent) {
                    newActiveLanes[lane] = firstParent
                    outgoing.append(GraphEdge(fromLane: lane, toLane: lane, color: color))
                } else if let targetLane = newActiveLanes.firstIndex(of: firstParent) {
                    outgoing.append(GraphEdge(fromLane: lane, toLane: targetLane, color: color))
                }

                for parent in parents.dropFirst() {
                    if let targetLane = newActiveLanes.firstIndex(of: parent) {
                        let pColor = laneColors[targetLane % laneColors.count]
                        outgoing.append(GraphEdge(fromLane: lane, toLane: targetLane, color: pColor))
                    } else {
                        let newLane: Int
                        if let free = newActiveLanes.firstIndex(of: "") {
                            newActiveLanes[free] = parent
                            newLane = free
                        } else {
                            newLane = newActiveLanes.count
                            newActiveLanes.append(parent)
                        }
                        let pColor = laneColors[newLane % laneColors.count]
                        outgoing.append(GraphEdge(fromLane: lane, toLane: newLane, color: pColor))
                    }
                }
            }

            while newActiveLanes.last == "" { newActiveLanes.removeLast() }

            let laneCount = max(activeLanes.count, newActiveLanes.count, lane + 1)

            rows.append(GraphRow(
                commit: commit,
                lane: lane,
                laneCount: laneCount,
                incoming: incoming,
                outgoing: outgoing,
                color: color
            ))

            activeLanes = newActiveLanes
        }

        return rows
    }
}
