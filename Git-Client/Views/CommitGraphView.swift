//
//  CommitGraphView.swift
//  Git-Client
//
//  Zeichnet eine einzelne Commit-Graph-Zeile via SwiftUI Canvas.
//  Obere Hälfte:  incoming-Kanten  (0     → midY)
//  Knoten:        Kreis            (midY)
//  Untere Hälfte: outgoing-Kanten  (midY  → height)
//
//  Durch symmetrisches Rendering beider Hälften entstehen keine Lücken mehr.
//

import SwiftUI

struct CommitGraphView: View {
    let row: GraphRow
    let rowHeight: CGFloat

    private static let laneWidth: CGFloat = 14
    private static let nodeRadius: CGFloat = 4
    private static let lineWidth: CGFloat = 2

    private var totalWidth: CGFloat {
        CGFloat(max(row.laneCount, row.lane + 1)) * Self.laneWidth
    }

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2

            // Obere Hälfte — incoming (0 → midY)
            for edge in row.incoming {
                let fromX = laneX(edge.fromLane)
                let toX   = laneX(edge.toLane)
                var path  = Path()
                path.move(to: CGPoint(x: fromX, y: 0))
                if fromX == toX {
                    path.addLine(to: CGPoint(x: toX, y: midY))
                } else {
                    // Bezier: gespiegelt zur unteren Kurve
                    let cp1 = CGPoint(x: fromX, y: size.height * 0.35)
                    let cp2 = CGPoint(x: toX,   y: midY - size.height * 0.35)
                    path.addCurve(to: CGPoint(x: toX, y: midY), control1: cp1, control2: cp2)
                }
                ctx.stroke(path, with: .color(edge.color), lineWidth: Self.lineWidth)
            }

            // Untere Hälfte — outgoing (midY → height)
            for edge in row.outgoing {
                let fromX = laneX(edge.fromLane)
                let toX   = laneX(edge.toLane)
                var path  = Path()
                path.move(to: CGPoint(x: fromX, y: midY))
                if fromX == toX {
                    path.addLine(to: CGPoint(x: toX, y: size.height))
                } else {
                    let cp1 = CGPoint(x: fromX, y: midY + size.height * 0.35)
                    let cp2 = CGPoint(x: toX,   y: size.height * 0.65)
                    path.addCurve(to: CGPoint(x: toX, y: size.height), control1: cp1, control2: cp2)
                }
                ctx.stroke(path, with: .color(edge.color), lineWidth: Self.lineWidth)
            }

            // Knoten
            let nodeX    = laneX(row.lane)
            let nodeRect = CGRect(
                x: nodeX - Self.nodeRadius,
                y: midY  - Self.nodeRadius,
                width:  Self.nodeRadius * 2,
                height: Self.nodeRadius * 2
            )
            ctx.fill(Path(ellipseIn: nodeRect), with: .color(row.color))
        }
        .frame(width: totalWidth, height: rowHeight)
    }

    private func laneX(_ lane: Int) -> CGFloat {
        CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2
    }
}
