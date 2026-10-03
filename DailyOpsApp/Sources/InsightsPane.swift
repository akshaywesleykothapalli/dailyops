import SwiftData
import SwiftUI

struct InsightsPane: View {
    @Bindable var controller: DictationController

    @Query(sort: \DictationEntry.date, order: .reverse) private var entries: [DictationEntry]
    @State private var stats: UsageStatistics?
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        guard let stats = stats else { return [currentYear] }
        let calendar = stats.calendar
        let firstYear = stats.firstDay.flatMap { calendar.component(.year, from: $0) } ?? currentYear
        let lastYear = max(currentYear, stats.lastDay.flatMap { calendar.component(.year, from: $0) } ?? currentYear)
        return Array(firstYear...lastYear).reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let stats = stats, !stats.isEmpty {
                    // MARK: - Four Small Curved Metric Boxes
                    HStack(spacing: 12) {
                        SmallMetricBox(
                            title: "Total Words",
                            value: InsightsFormat.count(stats.totalWords)
                        )
                        SmallMetricBox(
                            title: "Average WPM",
                            value: stats.wordsPerMinute > 0 ? "\(Int(stats.wordsPerMinute))" : "—"
                        )
                        SmallMetricBox(
                            title: "Current Streak",
                            value: "\(stats.currentStreak()) \(stats.currentStreak() == 1 ? "day" : "days")"
                        )
                        SmallMetricBox(
                            title: "Longest Streak",
                            value: "\(stats.longestStreak) \(stats.longestStreak == 1 ? "day" : "days")"
                        )
                    }
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                    .padding(.bottom, 24)

                    // MARK: - Activity Heatmap
                    WFSection(title: "Activity") {
                        YearlyHeatmap(
                            entries: entries,
                            selectedYear: $selectedYear,
                            availableYears: availableYears
                        )
                        .padding(14)
                    }
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                    .padding(.bottom, 26)

                    // MARK: - Words by Application
                    if !stats.apps.isEmpty {
                        WFSection(title: "Words by Application") {
                            WordsByApplicationList(apps: stats.apps)
                                .padding(14)
                        }
                        .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                        .padding(.bottom, 24)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Dictations Yet", systemImage: "waveform")
                    } description: {
                        Text("Usage insights will appear here once you begin dictating. All metrics are calculated entirely on this Mac.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.horizontal, SettingsDesign.contentHorizontalMargin)
                }
            }
            .padding(.vertical, SettingsDesign.contentVerticalPadding)
        }
        .background(SettingsDesign.contentBackground)
        .onAppear {
            stats = UsageStatisticsService.statistics(for: entries)
            if let available = availableYears.first, !availableYears.contains(selectedYear) {
                selectedYear = available
            }
        }
        .onChange(of: entries) { _, _ in
            stats = UsageStatisticsService.statistics(for: entries)
        }
    }
}

// MARK: - Small Curved Metric Box

private struct SmallMetricBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(SettingsDesign.metricValueFont)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)

            Text(title)
                .font(SettingsDesign.metricLabelFont)
                .foregroundStyle(SettingsDesign.secondaryText)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(height: SettingsDesign.metricTileHeight)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.metricTileRadius, style: .continuous)
                .fill(SettingsDesign.controlBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsDesign.metricTileRadius, style: .continuous)
                .strokeBorder(SettingsDesign.separatorColor, lineWidth: 1)
        }
    }
}

// MARK: - Yearly Activity Heatmap

private struct YearlyHeatmap: View {
    let entries: [DictationEntry]
    @Binding var selectedYear: Int
    let availableYears: [Int]

    private let calendar = Calendar.current
    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3.5
    private let weekdayColWidth: CGFloat = 26

    private var dayStats: [Date: Int] {
        var counts: [Date: Int] = [:]
        for entry in entries where !entry.isCommand {
            if calendar.component(.year, from: entry.date) == selectedYear {
                let startOfDay = calendar.startOfDay(for: entry.date)
                counts[startOfDay, default: 0] += 1
            }
        }
        return counts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Year selector & legend
            HStack {
                Text("\(String(selectedYear)) Activity Graph")
                    .font(SettingsDesign.bodyFontMedium)
                    .foregroundStyle(Color.primary)

                Spacer()

                if availableYears.count > 1 {
                    WFPreferencePicker(
                        selection: $selectedYear,
                        options: availableYears.map {
                            WFPreferencePickerOption(value: $0, title: String($0))
                        },
                        minWidth: 76
                    )
                }

                // Legend
                HStack(spacing: 3.5) {
                    Text("Less")
                        .font(.system(size: 9.5))
                        .foregroundStyle(SettingsDesign.secondaryText)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 9, height: 9)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(SettingsDesign.accentBlue.opacity(0.35))
                        .frame(width: 9, height: 9)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(SettingsDesign.accentBlue.opacity(0.55))
                        .frame(width: 9, height: 9)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(SettingsDesign.accentBlue.opacity(0.75))
                        .frame(width: 9, height: 9)

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(SettingsDesign.accentBlue)
                        .frame(width: 9, height: 9)

                    Text("More")
                        .font(.system(size: 9.5))
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
                .padding(.leading, 10)
            }

            // Calendar Grid
            let weeks = generateWeeks(for: selectedYear)
            let monthLabels = generateMonthLabels(weeks: weeks, year: selectedYear)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    // Month labels placed over corresponding weeks
                    ZStack(alignment: .leading) {
                        ForEach(monthLabels) { label in
                            let xOffset = weekdayColWidth + 6 + CGFloat(label.weekIndex) * (cellSize + cellSpacing)
                            Text(label.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .offset(x: xOffset, y: 0)
                        }
                    }
                    .frame(height: 14)

                    // 7 Weekdays × Weeks
                    HStack(alignment: .top, spacing: 6) {
                        // Weekday labels
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { row in
                                Text(weekdayName(row: row))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: weekdayColWidth, height: cellSize, alignment: .trailing)
                            }
                        }

                        // Weeks
                        HStack(spacing: cellSpacing) {
                            ForEach(weeks) { week in
                                VStack(spacing: cellSpacing) {
                                    ForEach(week.days) { day in
                                        HeatmapCell(
                                            day: day,
                                            size: cellSize,
                                            count: dayStats[day.date] ?? 0
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func weekdayName(row: Int) -> String {
        switch row {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }

    private func generateWeeks(for year: Int) -> [HeatmapWeek] {
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endOfYear = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return []
        }

        let startOfFirstWeek = calendar.dateInterval(of: .weekOfYear, for: startOfYear)?.start ?? startOfYear
        let endOfLastWeek = calendar.dateInterval(of: .weekOfYear, for: endOfYear)?.end ?? endOfYear

        var weeks: [HeatmapWeek] = []
        var current = startOfFirstWeek
        let today = Date()

        while current < endOfLastWeek {
            var days: [HeatmapDay] = []
            for dayOffset in 0..<7 {
                if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: current) {
                    let inYear = calendar.component(.year, from: dayDate) == year
                    let isFuture = dayDate > today
                    days.append(HeatmapDay(
                        date: calendar.startOfDay(for: dayDate),
                        isInYear: inYear,
                        isFuture: isFuture
                    ))
                }
            }
            weeks.append(HeatmapWeek(startDate: current, days: days))
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
        }

        return weeks
    }

    private func generateMonthLabels(weeks: [HeatmapWeek], year: Int) -> [HeatmapMonthLabel] {
        var labels: [HeatmapMonthLabel] = []
        var lastMonth = -1

        for (index, week) in weeks.enumerated() {
            if let firstDay = week.days.first(where: { $0.isInYear }) {
                let month = calendar.component(.month, from: firstDay.date)
                if month != lastMonth {
                    lastMonth = month
                    let monthSymbol = calendar.shortMonthSymbols[month - 1]
                    labels.append(HeatmapMonthLabel(id: index, weekIndex: index, title: monthSymbol))
                }
            }
        }

        return labels
    }
}

private struct HeatmapWeek: Identifiable {
    let startDate: Date
    let days: [HeatmapDay]
    var id: Date { startDate }
}

private struct HeatmapDay: Identifiable {
    let date: Date
    let isInYear: Bool
    let isFuture: Bool
    var id: Date { date }
}

private struct HeatmapMonthLabel: Identifiable {
    let id: Int
    let weekIndex: Int
    let title: String
}

private struct HeatmapCell: View {
    let day: HeatmapDay
    let size: CGFloat
    let count: Int

    var body: some View {
        if !day.isInYear || day.isFuture {
            Color.clear
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: SettingsDesign.heatmapCellRadius)
                .fill(colorForCount(count))
                .frame(width: size, height: size)
                .help(tooltipText)
        }
    }

    private func colorForCount(_ count: Int) -> Color {
        if count == 0 {
            return Color.primary.opacity(0.06)
        } else if count <= 2 {
            return SettingsDesign.accentBlue.opacity(0.35)
        } else if count <= 5 {
            return SettingsDesign.accentBlue.opacity(0.55)
        } else if count <= 10 {
            return SettingsDesign.accentBlue.opacity(0.75)
        } else {
            return SettingsDesign.accentBlue
        }
    }

    private var tooltipText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: day.date)
        if count == 0 {
            return "\(dateString): No dictations"
        } else {
            return "\(dateString): \(count) dictation\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Words by Application

private struct WordsByApplicationList: View {
    let apps: [AppUsage]

    var body: some View {
        let totalWords = max(1, apps.map(\.words).reduce(0, +))

        VStack(spacing: 5) {
            ForEach(apps.prefix(8)) { app in
                let percentage = Double(app.words) / Double(totalWords)

                HStack(spacing: 12) {
                    Text(app.name.isEmpty ? "Unknown Application" : app.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .leading)

                    // Proportional bar: 7pt height, 3.5pt radius
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 7)

                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(SettingsDesign.accentBlue)
                                .frame(width: max(4, proxy.size.width * CGFloat(percentage)), height: 7)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 7)

                    // Count and percentage aligned right
                    HStack(spacing: 6) {
                        Text("\(InsightsFormat.count(app.words))")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary)

                        Text("(\(Int(percentage * 100))%)")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 80, alignment: .trailing)
                }
                .frame(height: 26)
            }
        }
    }
}