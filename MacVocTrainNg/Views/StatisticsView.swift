import Charts
import SwiftUI
import VocabCore

struct StatisticsView: View {
    @ObservedObject var document: VocabularyDocument
    @State private var granularity: DeckStatistics.Granularity = .day
    @State private var figures = StatisticsFigures()

    var body: some View {
        // Re-evaluated every minute because cards become due as time passes. The time
        // comes from the document's clock and stays the same until the next minute, so
        // in between the figures come from the cache.
        TimelineView(.everyMinute) { context in
            content(at: figures.time(forTick: context.date, from: document.clock))
        }
    }

    private func content(at now: Date) -> some View {
        let deck = document.deck
        let calendar = document.calendar
        let today = calendar.dayNumber(for: now)

        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SummaryTiles(summary: figures.summary(of: deck, at: now, calendar: calendar))

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
                        series: figures.progress(
                            of: deck.progress,
                            today: today,
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
                        counts: figures.forecast(of: deck.cards, calendar: calendar, today: today, days: 30),
                        today: today
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

private struct ProgressChart: View {
    var series: ProgressSeries
    var granularity: DeckStatistics.Granularity
    @State private var selection: Date?

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
        if let last = series.dates.last {
            Chart {
                ForEach(series.bars) { bar in
                    BarMark(
                        x: .value("Date", bar.date, unit: unit),
                        y: .value("Cards", bar.count)
                    )
                    .foregroundStyle(by: .value("Maturity", bar.category.title))
                }
                if let selection, let index = series.index(closestTo: selection) {
                    RuleMark(x: .value("Date", series.dates[index], unit: unit))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ProgressTooltip(point: series.points[index], date: series.dates[index])
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
            .chartScrollPosition(initialX: last)
            .chartXSelection(value: $selection)
        } else {
            ContentUnavailableView("No Progress Yet", systemImage: "chart.bar", description: Text("Progress is recorded from the first change to the deck."))
        }
    }
}

private struct ProgressTooltip: View {
    var point: DeckStatistics.ProgressPoint
    var date: Date

    var body: some View {
        let counts = MaturityCategory.counts(fromBins: point.bins)
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(date: .abbreviated, time: .omitted))
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
