//
//  RepositoryStatistics.swift
//  Git-Client
//

import Foundation

struct AuthorStat: Identifiable, Equatable, Sendable {
    var id: String { email.isEmpty ? name : email }
    let name: String
    let email: String
    let commitCount: Int
    let percentage: Double
}

struct PeriodCount: Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String  // "YYYY-MM"
    let date: Date     // erster Tag des Monats
    let count: Int
}

struct DayCount: Identifiable, Equatable, Sendable {
    var id: Int { weekday }
    let weekday: Int   // 1=Mo … 7=So (ISO 8601)
    let count: Int
}

struct HourCount: Identifiable, Equatable, Sendable {
    var id: Int { hour }
    let hour: Int      // 0–23
    let count: Int
}

struct RepositoryStatistics: Equatable, Sendable {
    let totalCommits: Int
    let authorCount: Int
    let firstCommit: Date?
    let lastCommit: Date?
    let commitsPerWeekAverage: Double
    let branchCount: Int
    let tagCount: Int
    let authors: [AuthorStat]     // absteigend nach commitCount
    let monthly: [PeriodCount]    // chronologisch
    let weekday: [DayCount]       // Mo–So, immer 7 Einträge
    let hourly: [HourCount]       // 0–23, immer 24 Einträge

    var activeSpan: String {
        guard let first = firstCommit, let last = lastCommit else { return "–" }
        let days = Int(last.timeIntervalSince(first) / 86400)
        if days < 1   { return "< 1 Tag" }
        if days < 60  { return "\(days) Tage" }
        let months = days / 30
        if months < 24 { return "\(months) Monate" }
        return "\(months / 12) Jahre"
    }
}

// MARK: - Parsing & Aggregation

extension RepositoryStatistics {

    /// Parst die Ausgabe von `git shortlog -sne --all`.
    /// Format pro Zeile: `"   <n>\t<Name> <email>"` (die Anzahl ist rechts mit Leerzeichen aufgefüllt).
    nonisolated static func parseShortlog(_ output: String) -> [AuthorStat] {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var raw: [(count: Int, name: String, email: String)] = []

        for line in lines {
            guard let tabIdx = line.firstIndex(of: "\t") else { continue }
            let countStr = line[line.startIndex..<tabIdx].trimmingCharacters(in: .whitespaces)
            guard let count = Int(countStr) else { continue }
            let rest = String(line[line.index(after: tabIdx)...])

            if let ltIdx = rest.lastIndex(of: "<"),
               let gtIdx = rest.lastIndex(of: ">"),
               ltIdx < gtIdx {
                let name  = String(rest[rest.startIndex..<ltIdx]).trimmingCharacters(in: .whitespaces)
                let email = String(rest[rest.index(after: ltIdx)..<gtIdx])
                raw.append((count, name, email))
            } else {
                raw.append((count, rest.trimmingCharacters(in: .whitespaces), ""))
            }
        }

        let total = raw.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }

        return raw.sorted { $0.count > $1.count }.map { entry in
            AuthorStat(
                name: entry.name,
                email: entry.email,
                commitCount: entry.count,
                percentage: Double(entry.count) / Double(total) * 100
            )
        }
    }

    /// Aggregiert alle Statistiken aus Unix-Timestamp-Zeilen (`git log --all --pretty=%at`)
    /// und den bereits geparsten Autor- und Branch-/Tag-Daten.
    /// Diese Methode ist `nonisolated`, damit sie ohne Hop vom GitService-Actor aus aufrufbar ist.
    nonisolated static func aggregate(
        timestampLines: String,
        authors: [AuthorStat],
        branchCount: Int,
        tagCount: Int
    ) -> RepositoryStatistics {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")

        let dates: [Date] = timestampLines
            .components(separatedBy: "\n")
            .compactMap { line -> Date? in
                let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty, let ts = TimeInterval(s) else { return nil }
                return Date(timeIntervalSince1970: ts)
            }

        guard !dates.isEmpty else {
            return RepositoryStatistics(
                totalCommits: 0, authorCount: authors.count,
                firstCommit: nil, lastCommit: nil,
                commitsPerWeekAverage: 0,
                branchCount: branchCount, tagCount: tagCount,
                authors: authors,
                monthly: [],
                weekday: (1...7).map { DayCount(weekday: $0, count: 0) },
                hourly:  (0...23).map { HourCount(hour: $0, count: 0) }
            )
        }

        let sorted   = dates.sorted()
        let first    = sorted.first!
        let last     = sorted.last!
        let spanDays = max(1, Int(last.timeIntervalSince(first) / 86400))
        let avgPerWeek = Double(dates.count) / (Double(spanDays) / 7.0)

        // Monats-Buckets
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")

        var monthBuckets: [String: (date: Date, count: Int)] = [:]
        for date in dates {
            let label = df.string(from: date)
            var comps = cal.dateComponents([.year, .month], from: date)
            comps.day = 1
            let monthStart = cal.date(from: comps) ?? date
            if let existing = monthBuckets[label] {
                monthBuckets[label] = (existing.date, existing.count + 1)
            } else {
                monthBuckets[label] = (monthStart, 1)
            }
        }
        let monthly = monthBuckets
            .map { PeriodCount(label: $0.key, date: $0.value.date, count: $0.value.count) }
            .sorted { $0.date < $1.date }

        // Wochentag-Buckets (ISO 8601: 1=Mo … 7=So)
        // Calendar.component(.weekday): 1=So, 2=Mo, …, 7=Sa → Umrechnung:
        var wdBuckets = [Int: Int]()
        for d in 1...7 { wdBuckets[d] = 0 }
        for date in dates {
            let calWD = cal.component(.weekday, from: date)
            let isoWD = calWD == 1 ? 7 : calWD - 1
            wdBuckets[isoWD, default: 0] += 1
        }
        let weekday = (1...7).map { DayCount(weekday: $0, count: wdBuckets[$0] ?? 0) }

        // Stunden-Buckets
        var hourBuckets = [Int: Int]()
        for h in 0...23 { hourBuckets[h] = 0 }
        for date in dates {
            let h = cal.component(.hour, from: date)
            hourBuckets[h, default: 0] += 1
        }
        let hourly = (0...23).map { HourCount(hour: $0, count: hourBuckets[$0] ?? 0) }

        return RepositoryStatistics(
            totalCommits: dates.count,
            authorCount: authors.count,
            firstCommit: first,
            lastCommit: last,
            commitsPerWeekAverage: avgPerWeek,
            branchCount: branchCount,
            tagCount: tagCount,
            authors: authors,
            monthly: monthly,
            weekday: weekday,
            hourly: hourly
        )
    }
}
