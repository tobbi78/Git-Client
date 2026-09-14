//
//  StatisticsView.swift
//  Git-Client
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @State private var vm: StatisticsViewModel

    init(repository: RepositoryBookmark) {
        _vm = State(wrappedValue: StatisticsViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Statistiken werden berechnet…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.errorMessage {
                ContentUnavailableView(
                    "Fehler beim Laden",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            } else if let stats = vm.statistics, stats.totalCommits > 0 {
                statsContent(stats)
            } else {
                ContentUnavailableView(
                    "Keine Commits",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Das Repository enthält noch keine Commits.")
                )
            }
        }
        .navigationTitle("Statistiken — \(vm.repository.name)")
        .task { await vm.load() }
    }

    // MARK: - Hauptinhalt

    private func statsContent(_ s: RepositoryStatistics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                overviewSection(s)
                if !s.authors.isEmpty   { authorsSection(s) }
                if !s.monthly.isEmpty   { activitySection(s) }
                rhythmSection(s)
            }
            .padding(28)
        }
    }

    // MARK: - Überblick

    private func overviewSection(_ s: RepositoryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Überblick")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 240))],
                spacing: 12
            ) {
                kpiTile("Commits gesamt",    value: "\(s.totalCommits)")
                kpiTile("Autoren",           value: "\(s.authorCount)")
                kpiTile("Branches",          value: "\(s.branchCount)")
                kpiTile("Tags",              value: "\(s.tagCount)")
                kpiTile("Ø Commits/Woche",   value: String(format: "%.1f", s.commitsPerWeekAverage))
                kpiTile("Aktiver Zeitraum",  value: s.activeSpan)
                if let first = s.firstCommit {
                    kpiTile("Erster Commit",
                            value: first.formatted(date: .abbreviated, time: .omitted))
                }
                if let last = s.lastCommit {
                    kpiTile("Letzter Commit",
                            value: last.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func kpiTile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Color.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Autoren

    private func authorsSection(_ s: RepositoryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Commits pro Autor")
            let top = Array(s.authors.prefix(15))
            Chart(top) { author in
                BarMark(
                    x: .value("Commits", author.commitCount),
                    y: .value("Autor", author.name)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .annotation(position: .trailing, spacing: 6) {
                    Text(String(format: "%.0f%%", author.percentage))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel() }
            }
            .frame(height: CGFloat(top.count) * 30 + 20)
        }
    }

    // MARK: - Aktivität über Zeit

    private func activitySection(_ s: RepositoryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Aktivität über Zeit")
            Chart(s.monthly) { period in
                AreaMark(
                    x: .value("Monat", period.date),
                    y: .value("Commits", period.count)
                )
                .foregroundStyle(Color.accentColor.opacity(0.2))
                LineMark(
                    x: .value("Monat", period.date),
                    y: .value("Commits", period.count)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 180)
        }
    }

    // MARK: - Commit-Rhythmus

    private let weekdayLabels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    private func rhythmSection(_ s: RepositoryStatistics) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Commit-Rhythmus")

            VStack(alignment: .leading, spacing: 8) {
                subHeader("Nach Wochentag")
                Chart(s.weekday) { day in
                    BarMark(
                        x: .value("Wochentag", weekdayLabels[day.weekday - 1]),
                        y: .value("Commits", day.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .frame(height: 130)
            }

            VStack(alignment: .leading, spacing: 8) {
                subHeader("Nach Tageszeit")
                Chart(s.hourly) { h in
                    BarMark(
                        x: .value("Stunde", h.hour),
                        y: .value("Commits", h.count)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21, 23]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text("\(h) Uhr")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 130)
            }
        }
    }

    // MARK: - Hilfselemente

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.primary)
    }

    private func subHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
    }
}
