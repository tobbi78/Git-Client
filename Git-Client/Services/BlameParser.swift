//
//  BlameParser.swift
//  Git-Client
//
//  Parst die Ausgabe von `git blame --porcelain` in BlameLine-Objekte.
//
//  Format einer Porcelain-Gruppe:
//    <40-sha> <origLine> <finalLine> [<groupCount>]    ← Header-Zeile
//    author <name>                                     ← nur beim ersten Auftreten des SHA
//    author-time <epoch>                               ← nur beim ersten Auftreten
//    summary <text>                                    ← nur beim ersten Auftreten
//    … (weitere Meta-Zeilen)
//    \t<content>                                       ← Tab-prefixte Inhaltszeile
//

import Foundation

enum BlameParser {

    nonisolated static func parse(_ output: String) -> [BlameLine] {
        let lines = output.components(separatedBy: "\n")
        var result: [BlameLine] = []

        // Cache für bereits gesehene Commits (sha → Info)
        struct CommitInfo {
            var author: String = ""
            var date: Date = Date(timeIntervalSince1970: 0)
            var summary: String = ""
        }
        var cache: [String: CommitInfo] = [:]

        // Aktueller Kontext innerhalb einer Gruppe
        var currentSha = ""
        var currentFinalLine = 0
        var currentInfo = CommitInfo()

        for line in lines {
            // Header-Zeile: beginnt mit 40 Hex-Zeichen, gefolgt von Leerzeichen + Zahlen
            if line.count >= 40 {
                let candidate = String(line.prefix(40))
                if candidate.allSatisfy({ $0.isHexDigit }),
                   line.count > 40, line[line.index(line.startIndex, offsetBy: 40)] == " " {
                    currentSha = candidate
                    // Finale Zeilennummer ist das dritte Token
                    let tokens = line.split(separator: " ", maxSplits: 3)
                    if tokens.count >= 3, let finalLine = Int(tokens[2]) {
                        currentFinalLine = finalLine
                    }
                    // Cache-Eintrag vorbereiten (wird ggf. mit Meta-Zeilen befüllt)
                    if cache[currentSha] == nil {
                        cache[currentSha] = CommitInfo()
                    }
                    currentInfo = cache[currentSha]!
                    continue
                }
            }

            // Meta-Zeilen (nur mit Leerzeichen nach dem Key — verhindert Fehlmatch mit
            // author-mail, author-time, author-tz etc.)
            if line.hasPrefix("author ") {
                let value = String(line.dropFirst("author ".count))
                cache[currentSha]?.author = value
                currentInfo.author = value
                continue
            }
            if line.hasPrefix("author-time ") {
                let epochStr = String(line.dropFirst("author-time ".count))
                if let epoch = TimeInterval(epochStr) {
                    let date = Date(timeIntervalSince1970: epoch)
                    cache[currentSha]?.date = date
                    currentInfo.date = date
                }
                continue
            }
            if line.hasPrefix("summary ") {
                let value = String(line.dropFirst("summary ".count))
                cache[currentSha]?.summary = value
                currentInfo.summary = value
                continue
            }

            // Inhaltszeile: mit Tab eingeleitet
            if line.hasPrefix("\t") {
                let content = String(line.dropFirst())  // führendes Tab entfernen
                // Falls ein weiterer Aufruf für denselben SHA im Cache ist, aus Cache holen
                let info = cache[currentSha] ?? currentInfo
                result.append(BlameLine(
                    id: currentFinalLine,
                    lineNumber: currentFinalLine,
                    sha: currentSha,
                    shortSha: String(currentSha.prefix(8)),
                    author: info.author,
                    date: info.date,
                    summary: info.summary,
                    content: content
                ))
            }
        }

        return result
    }
}
