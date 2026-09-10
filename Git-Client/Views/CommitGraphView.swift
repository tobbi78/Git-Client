//
//  CommitGraphView.swift
//  Git-Client
//
//  Zeichnet die Commit-Graph-Spur (Knoten + Verbindungslinien) für eine einzelne
//  Commit-Zeile via SwiftUI Canvas.
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

            // Linien zur nächsten Zeile
            for edge in row.edges {
                let fromX = laneX(edge.fromLane)
                let toX   = laneX(edge.toLane)

                var path = Path()
                path.move(to: CGPoint(x: fromX, y: midY))

                if fromX == toX {
                    // Gerade Linie
                    path.addLine(to: CGPoint(x: toX, y: size.height))
                } else {
                    // Geschwungene Linie (Bezier)
                    let cp1 = CGPoint(x: fromX, y: midY + size.height * 0.35)
                    let cp2 = CGPoint(x: toX,   y: size.height * 0.65)
                    path.addCurve(
                        to: CGPoint(x: toX, y: size.height),
                        control1: cp1,
                        control2: cp2
                    )
                }

                ctx.stroke(path, with: .color(edge.color), lineWidth: Self.lineWidth)
            }

            // Linie von oben in den Knoten (Eltern-Verbindung dieser Lane)
            let nodeX = laneX(row.lane)
            var topLine = Path()
            topLine.move(to: CGPoint(x: nodeX, y: 0))
            topLine.addLine(to: CGPoint(x: nodeX, y: midY - Self.nodeRadius))
            ctx.stroke(topLine, with: .color(row.color), lineWidth: Self.lineWidth)

            // Knoten
            let nodeRect = CGRect(
                x: nodeX - Self.nodeRadius,
                y: midY - Self.nodeRadius,
                width: Self.nodeRadius * 2,
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
