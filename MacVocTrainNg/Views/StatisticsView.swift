import Charts
import SwiftUI
import VocabCore

struct StatisticsView: View {
    @ObservedObject var document: VocabularyDocument
    @State private var granularity: DeckStatistics.Granularity = .day

    var body: some View {
        let now = Date()
        let summary = DeckStatistics.summary(of: document.deck, at: now, calendar: document.calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SummaryTiles(summary: summary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Progress")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Picker("Period", selection: $granularity) {
                            Text("Days").tag(DeckStatistics.Granularity.day)
                            Text("Weeks").tag(DeckStatistics.Granularity.week)
                            Text("Months").tag(DeckStatistics.Granularity.month)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    Text("How well the cards are known, by how long they are remembered.")
                        .foregroundStyle(.secondary)
                    ProgressChart(
                        points: DeckStatistics.progress(
                            snapshots: document.deck.progress,
                            today: document.calendar.dayNumber(for: now),
                            granularity: granularity,
                            firstWeekday: Calendar.current.firstWeekday
                        ),
                        granularity: granularity
                    )
                    .frame(height: 280)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Upcoming Reviews")
                        .font(.title2.weight(.semibold))
                    Text("Cards falling due in the next 30 days.")
                        .foregroundStyle(.secondary)
                    ForecastChart(
                        counts: DeckStatistics.forecast(
                            cards: document.deck.cards,
                            calendar: document.calendar,
                            today: document.calendar.dayNumber(for: now),
                            days: 30
                        ),
                        today: document.calendar.dayNumber(for: now)
                    )
                    .frame(height: 200)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Tiles

private struct SummaryTiles: View {
    var summary: DeckStatistics.Summary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            Tile(title: "Cards", value: summary.total.formatted())
            Tile(title: "Due Now", value: summary.dueNow.formatted())
            Tile(title: "New", value: summary.new.formatted())
            Tile(
                title: "Recall Probability",
                value: summary.averageRecallProbability.map(Format.percent) ?? "–",
                help: "Average recall probability of all studied cards right now."
            )
            Tile(
                title: "Reviewed Today",
                value: summary.reviewsToday.formatted(),
                detail: summary.reviewsToday > 0
                    ? String(localized: "\(Format.percent(Double(summary.recalledToday) / Double(summary.reviewsToday))) recalled")
                    : nil
            )
        }
    }
}

private struct Tile: View {
    var title: LocalizedStringKey
    var value: String
    var detail: String?
    var help: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
            Text(detail ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .help(help ?? title)
    }
}

// MARK: - Charts

/// Converts a study day to a date for the chart axis (noon avoids time zone edges).
private func chartDate(forDay day: Int) -> Date {
    let civil = CivilDate(dayNumber: day)
    return Calendar.current.date(from: DateComponents(year: civil.year, month: civil.month, day: civil.day, hour: 12)) ?? Date()
}

private struct ProgressChart: View {
    var points: [DeckStatistics.ProgressPoint]
    var granularity: DeckStatistics.Granularity
    @State private var selection: Date?

    private struct Bar: Identifiable {
        var date: Date
        var category: MaturityCategory
        var count: Int
        var id: String { "\(date.timeIntervalSince1970)-\(category.rawValue)" }
    }

    private var bars: [Bar] {
        points.flatMap { point in
            let counts = MaturityCategory.counts(fromBins: point.bins)
            let date = chartDate(forDay: point.day)
            // Most solid at the bottom of each stack.
            return MaturityCategory.allCases.reversed().map { category in
                Bar(date: date, category: category, count: counts[category] ?? 0)
            }
        }
    }

    private var unit: Calendar.Component {
        switch granularity {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    private var visibleLength: TimeInterval {
        switch granularity {
        case .day: 60 * 86400
        case .week: 52 * 7 * 86400
        case .month: 36 * 31 * 86400
        }
    }

    var body: some View {
        if points.isEmpty {
            ContentUnavailableView("No Progress Yet", systemImage: "chart.bar", description: Text("Progress is recorded from the first change to the deck."))
        } else {
            Chart {
                ForEach(bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: unit),
                        y: .value("Cards", bar.count)
                    )
                    .foregroundStyle(by: .value("Maturity", bar.category.title))
                }
                if let selected = selectedPoint {
                    RuleMark(x: .value("Date", chartDate(forDay: selected.day), unit: unit))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ProgressTooltip(point: selected, granularity: granularity)
                        }
                }
            }
            .chartForegroundStyleScale(
                domain: MaturityCategory.allCases.map(\.title),
                range: MaturityCategory.allCases.map(\.color)
            )
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleLength)
            .chartScrollPosition(initialX: chartDate(forDay: points.last!.day))
            .chartXSelection(value: $selection)
        }
    }

    private var selectedPoint: DeckStatistics.ProgressPoint? {
        guard let selection else { return nil }
        return points.min { abs(chartDate(forDay: $0.day).timeIntervalSince(selection)) < abs(chartDate(forDay: $1.day).timeIntervalSince(selection)) }
    }
}

private struct ProgressTooltip: View {
    var point: DeckStatistics.ProgressPoint
    var granularity: DeckStatistics.Granularity

    var body: some View {
        let counts = MaturityCategory.counts(fromBins: point.bins)
        VStack(alignment: .leading, spacing: 4) {
            Text(chartDate(forDay: point.day).formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
            ForEach(MaturityCategory.allCases.reversed(), id: \.self) { category in
                HStack(spacing: 6) {
                    Circle().fill(category.color).frame(width: 8, height: 8)
                    Text(category.title)
                    Spacer(minLength: 12)
                    Text((counts[category] ?? 0).formatted())
                        .monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text("Total")
                Spacer(minLength: 12)
                Text(point.bins.reduce(0, +).formatted())
                    .monospacedDigit()
            }
            .fontWeight(.semibold)
        }
        .font(.callout)
        .padding(10)
        .frame(width: 190)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
    }
}

private struct ForecastChart: View {
    var counts: [Int]
    /// Study day of index 0.
    var today: Int
    @State private var selection: Date?

    private func date(forOffset offset: Int) -> Date {
        chartDate(forDay: today + offset)
    }

    var body: some View {
        Chart {
            ForEach(Array(counts.enumerated()), id: \.offset) { offset, count in
                BarMark(
                    x: .value("Day", date(forOffset: offset), unit: .day),
                    y: .value("Cards", count)
                )
                .foregroundStyle(MaturityCategory.maturing.color)
                .cornerRadius(3)
            }
            if let selection, let offset = selectedOffset(selection) {
                RuleMark(x: .value("Day", date(forOffset: offset), unit: .day))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(offset == 0 ? String(localized: "Today (incl. overdue)") : date(forOffset: offset).formatted(date: .abbreviated, time: .omitted))
                                .font(.headline)
                            Text("\(counts[offset]) cards")
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 2)
                    }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selection)
    }

    private func selectedOffset(_ date: Date) -> Int? {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        let offset = CivilDate(year: year, month: month, day: day).dayNumber - today
        return counts.indices.contains(offset) ? offset : nil
    }
}
