//
//  BlameLine.swift
//  Git-Client
//
//  Repräsentiert eine einzelne Zeile in der Blame-Ausgabe von `git blame --porcelain`.
//

import Foundation

struct BlameLine: Identifiable, Sendable {
    let id: Int           // finale Zeilennummer (eindeutig pro Datei)
    let lineNumber: Int   // finale Zeilennummer in der aktuellen Datei
    let sha: String       // voller Commit-SHA (40 Hex-Zeichen)
    let shortSha: String  // erste 8 Zeichen — konsistent mit Commit.shortSha
    let author: String
    let date: Date
    let summary: String   // erste Zeile der Commit-Nachricht
    let content: String   // Zeileninhalt (ohne führendes Tab)
}
