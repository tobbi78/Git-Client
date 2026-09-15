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

    // MARK: Abgeleitete KPIs (kein zusätzlicher git-Aufruf)

    /// Minimale Anzahl Autoren, die zusammen ≥ 80 % der Commits verantworten.
    let busFactor: Int
    /// Durchschnittliche Anzahl Tage zwischen zwei Commits (Zeitspanne / (n−1)).
    let averageDaysBetweenCommits: Double
    /// Längste ununterbrochene Folge von Kalendertagen mit mindestens einem Commit.
    let longestStreakDays: Int
    /// Monat mit den meisten Commits.
    let mostActiveMonth: PeriodCount?
    /// Wochentag (ISO: 1=Mo…7=So) mit den meisten Commits.
    let mostActiveWeekday: DayCount?

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

    /// Minimale Autorenanzahl, die zusammen ≥ `threshold` % der Commits abdeckt.
    /// Autoren müssen **absteigend nach Commit-Anzahl** sortiert sein.
    /// Gibt 0 zurück, wenn die Liste leer ist.
    nonisolated static func computeBusFactor(
        _ authors: [AuthorStat],
        threshold: Double = 80
    ) -> Int {
        guard !authors.isEmpty else { return 0 }
        var cumulative = 0.0
        for (i, author) in authors.enumerated() {
            cumulative += author.percentage
            if cumulative >= threshold { return i + 1 }
        }
        return authors.count
    }

    /// Längste Folge aufeinanderfolgender Kalendertage mit ≥ 1 Commit.
    /// Mehrere Commits am selben Tag werden als ein Aktivitätstag gewertet.
    nonisolated static func longestDailyStreak(_ dates: [Date], calendar: Calendar) -> Int {
        guard !dates.isEmpty else { return 0 }
        // Deduplizieren auf Tagesebene (Mitternacht des jeweiligen Tages)
        let uniqueDays = Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
        guard uniqueDays.count > 1 else { return 1 }

        var longest = 1
        var current = 1
        for i in 1..<uniqueDays.count {
            let diff = calendar.dateComponents([.day], from: uniqueDays[i - 1], to: uniqueDays[i]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

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

        // Commits pro E-Mail-Adresse summieren (gleiche Adresse, verschiedene Namen → ein Eintrag)
        var buckets: [String: Int] = [:]
        for entry in raw {
            let key = (entry.email.isEmpty ? entry.name : entry.email).lowercased()
            buckets[key, default: 0] += entry.count
        }

        let total = buckets.values.reduce(0, +)
        guard total > 0 else { return [] }

        return buckets
            .map { key, count in
                AuthorStat(
                    name: key,
                    email: key.contains("@") ? key : "",
                    commitCount: count,
                    percentage: Double(count) / Double(total) * 100
                )
            }
            .sorted { $0.commitCount > $1.commitCount }
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
                hourly:  (0...23).map { HourCount(hour: $0, count: 0) },
                busFactor: 0,
                averageDaysBetweenCommits: 0,
                longestStreakDays: 0,
                mostActiveMonth: nil,
                mostActiveWeekday: nil
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

        // Abgeleitete KPIs (kein zusätzlicher git-Aufruf)
        let busFactor  = Self.computeBusFactor(authors)
        let avgDays    = dates.count > 1
            ? last.timeIntervalSince(first) / 86400 / Double(dates.count - 1)
            : 0
        let streak     = Self.longestDailyStreak(dates, calendar: cal)
        let topMonth   = monthly.max { $0.count < $1.count }
        let topWeekday = weekday.allSatisfy { $0.count == 0 }
            ? nil
            : weekday.max { $0.count < $1.count }

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
            hourly: hourly,
            busFactor: busFactor,
            averageDaysBetweenCommits: avgDays,
            longestStreakDays: streak,
            mostActiveMonth: topMonth,
            mostActiveWeekday: topWeekday
        )
    }
}
