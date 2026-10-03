import SwiftUI

// MARK: - Local Metric Card for Insights

private struct InsightMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text(value)
                        .font(.custom("Playfair Display", size: 52).weight(.medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(Color(white: 1.0), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

/// The Insights pane.
///
/// Designed around a continuous, GitHub-style contribution graph hierarchy:
///
/// 1. **Yearly Insights (Main)**:
///    - Prominent year title and navigation.
///    - Continuous 52–53 week vertical contribution calendar with 7 weekday rows.
///    - Month labels positioned across the graph with click-to-open month report.
///    - Hover tooltips and day/month click drill-downs.
///    - Essential Yearly Summary (Total dictations, Total words, Active time).
///    - Clean, compact **Apps** insight with deterministic brand-inspired colors.
///    - Clean, compact **Usage** (Time-of-day) insight.
///
/// 2. **Monthly Report**:
///    - Clear `← Year` back navigation.
///    - Detailed monthly contribution calendar with weekday alignment.
///    - Day-level breakdown on day click.
///    - Essential monthly summary and monthly app usage.
///
/// All numbers come strictly from real local history data (`UsageStatistics`).

// MARK: - Dashboard

struct InsightsDashboard: View {
    let entries: [DictationEntry]

    @State private var model = InsightsViewModel()
    @State private var selectedMonth: Date? = nil
    @State private var selectedDay: Date? = nil
    @State private var didAlign = false

    var body: some View {
        let overall = model.statistics(for: entries)

        Group {
            if overall.isEmpty {
                ContentUnavailableView {
                    Label("No Dictations Yet", systemImage: "waveform")
                } description: {
                    Text("Insights appear here after your first dictation. Everything is counted locally on this Mac.")
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else if let month = selectedMonth {
                MonthlyReportView(
                    model: model,
                    entries: entries,
                    month: month,
                    selectedDay: $selectedDay,
                    onBack: {
                        selectedMonth = nil
                        selectedDay = nil
                        model.select(scope: .year)
                    },
                    onStepMonth: { delta in
                        if let nextMonth = model.calendar.date(byAdding: .month, value: delta, to: month) {
                            selectedMonth = nextMonth
                            selectedDay = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
            } else {
                YearlyInsightsView(
                    model: model,
                    entries: entries,
                    overall: overall,
                    onSelectMonth: { monthDate in
                        selectedMonth = monthDate
                        selectedDay = nil
                    },
                    onSelectDay: { dayDate in
                        let monthStart = model.calendar.dateInterval(of: .month, for: dayDate)?.start ?? dayDate
                        selectedMonth = monthStart
                        selectedDay = dayDate
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedMonth)
        .onAppear {
            model.select(scope: .year)
            guard !didAlign else { return }
            didAlign = true
            if let last = overall.lastDay {
                let lastYearStart = model.calendar.dateInterval(of: .year, for: last)?.start ?? last
                let currentYearStart = model.calendar.dateInterval(of: .year, for: .now)?.start ?? .now
                if model.windowStatistics(for: entries).isEmpty && lastYearStart < currentYearStart {
                    model.anchor = last
                }
            }
        }
    }
}

// MARK: - Yearly Insights

private struct YearlyInsightsView: View {
    let model: InsightsViewModel
    let entries: [DictationEntry]
    let overall: UsageStatistics
    let onSelectMonth: (Date) -> Void
    let onSelectDay: (Date) -> Void

    var body: some View {
        let yearStats = model.windowStatistics(for: entries)
        let calendar = model.calendar
        let yearInterval = calendar.dateInterval(of: .year, for: model.anchor)
            ?? DateInterval(start: model.anchor, duration: 86400 * 365)
        let grid = yearStats.activityCalendar(in: yearInterval)

        VStack(alignment: .leading, spacing: 22) {
            // Header: Year Navigation
            YearlyNavigationBar(model: model, overall: overall)

            // Centerpiece: Continuous GitHub-style Contribution Graph
            VStack(alignment: .leading, spacing: 10) {
                YearlyActivityGraph(
                    model: model,
                    grid: grid,
                    onSelectMonth: onSelectMonth,
                    onSelectDay: onSelectDay
                )

                ActivityLegend()
                    .padding(.top, 2)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }

            // Essential Yearly Summary Row
            HStack(spacing: 16) {
                InsightMetricCard(
                    title: "TOTAL WORDS",
                    value: InsightsFormat.count(yearStats.totalWords),
                    symbol: "textformat",
                    color: .blue
                )
                InsightMetricCard(
                    title: "AVG WPM",
                    value: yearStats.wordsPerMinute > 0 ? "\(Int(yearStats.wordsPerMinute))" : "—",
                    symbol: "timer",
                    color: .green
                )
                InsightMetricCard(
                    title: "CURRENT STREAK",
                    value: "\(yearStats.currentStreak()) days",
                    symbol: "flame.fill",
                    color: .orange
                )
                InsightMetricCard(
                    title: "LONGEST STREAK",
                    value: "\(yearStats.longestStreak) days",
                    symbol: "trophy.fill",
                    color: .purple
                )
            }
            .padding(.horizontal, 4)

            Divider().opacity(0.5)

            // Secondary Insights: Apps and Usage (Time of Day)
            HStack(alignment: .top, spacing: 28) {
                AppsInsightSection(apps: yearStats.apps)
                    .frame(maxWidth: .infinity, alignment: .leading)

                UsageTimeInsightSection(slices: timeOfDaySlices(for: yearStats))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func timeOfDaySlices(for statistics: UsageStatistics) -> [TimeOfDaySlice] {
        let morningHours = statistics.hours.filter { $0.hour >= 6 && $0.hour < 12 }
        let afternoonHours = statistics.hours.filter { $0.hour >= 12 && $0.hour < 18 }
        let eveningHours = statistics.hours.filter { $0.hour >= 18 && $0.hour < 22 }
        let nightHours = statistics.hours.filter { $0.hour >= 22 || $0.hour < 6 }

        let total = max(1, statistics.totalDictations)

        func makeSlice(_ slice: [HourUsage], name: String, range: String, icon: String) -> TimeOfDaySlice {
            let d = slice.reduce(0) { $0 + $1.dictations }
            let w = slice.reduce(0) { $0 + $1.words }
            let s = slice.reduce(0.0) { $0 + $1.seconds }
            let pct = Double(d) / Double(total)
            return TimeOfDaySlice(name: name, range: range, icon: icon, dictations: d, words: w, seconds: s, percentage: pct)
        }

        return [
            makeSlice(morningHours, name: "Morning", range: "6 AM – 12 PM", icon: "sun.max.fill"),
            makeSlice(afternoonHours, name: "Afternoon", range: "12 PM – 6 PM", icon: "sun.horizon.fill"),
            makeSlice(eveningHours, name: "Evening", range: "6 PM – 10 PM", icon: "moon.fill"),
            makeSlice(nightHours, name: "Night", range: "10 PM – 6 AM", icon: "moon.zzz.fill")
        ]
    }
}

// MARK: - Navigation Bar

private struct YearlyNavigationBar: View {
    let model: InsightsViewModel
    let overall: UsageStatistics

    var body: some View {
        let years = model.years(in: overall)

        HStack(spacing: 12) {
            Text(model.yearLabel(model.anchor))
                .font(.system(size: 26, weight: .bold, design: .serif))
                .monospacedDigit()

            if years.count > 1 {
                Menu {
                    ForEach(years, id: \.self) { year in
                        Button(String(year)) { model.show(year: year) }
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Jump to a year")
            }

            Spacer()

            HStack(spacing: 2) {
                Button { model.step(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Previous year")

                Button { model.step(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canStepForward())
                .help("Next year")
            }
        }
    }
}

// MARK: - Continuous Yearly Activity Graph

private struct YearlyActivityGraph: View {
    let model: InsightsViewModel
    let grid: ActivityCalendar
    let onSelectMonth: (Date) -> Void
    let onSelectDay: (Date) -> Void

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3
    private let weekdayColWidth: CGFloat = 28

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Month Labels Row
                YearlyActivityMonthLabels(
                    grid: grid,
                    model: model,
                    cellSize: cellSize,
                    cellSpacing: cellSpacing,
                    leadingOffset: weekdayColWidth + 6,
                    onSelectMonth: onSelectMonth
                )
                .frame(height: 18)

                // 7 Weekday Rows × 52-53 Weeks Columns
                HStack(alignment: .top, spacing: 6) {
                    // Weekday Labels on the left (e.g. Mon, Wed, Fri)
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(weekdayAbbreviation(row: row))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: weekdayColWidth, height: cellSize, alignment: .trailing)
                        }
                    }

                    // Columns of weeks
                    HStack(spacing: cellSpacing) {
                        ForEach(grid.weeks) { week in
                            VStack(spacing: cellSpacing) {
                                ForEach(week.cells) { cell in
                                    YearlyActivityGridCell(
                                        cell: cell,
                                        size: cellSize,
                                        tooltip: model.activityDescription(cell),
                                        onTap: {
                                            if cell.isInRange {
                                                onSelectDay(cell.day)
                                            }
                                        }
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

    private func weekdayAbbreviation(row: Int) -> String {
        // Show labels on alternating days to prevent vertical overcrowding (Mon, Wed, Fri)
        let isMondayFirst = model.calendar.firstWeekday == 2
        if isMondayFirst {
            switch row {
            case 0: return "Mon"
            case 2: return "Wed"
            case 4: return "Fri"
            default: return ""
            }
        } else {
            switch row {
            case 1: return "Mon"
            case 3: return "Wed"
            case 5: return "Fri"
            default: return ""
            }
        }
    }
}

private struct YearlyActivityMonthLabels: View {
    let grid: ActivityCalendar
    let model: InsightsViewModel
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    let leadingOffset: CGFloat
    let onSelectMonth: (Date) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(grid.monthLabels) { label in
                let xPosition = leadingOffset + CGFloat(label.weekIndex) * (cellSize + cellSpacing)
                Button {
                    onSelectMonth(label.month)
                } label: {
                    Text(model.monthLabel(label.month))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("View report for \(model.fullMonthLabel(label.month))")
                .offset(x: xPosition, y: 0)
            }
        }
        .frame(height: 18, alignment: .leading)
    }
}

private struct YearlyActivityGridCell: View {
    let cell: ActivityCell
    let size: CGFloat
    let tooltip: String
    let onTap: () -> Void

    var body: some View {
        Group {
            if cell.isInRange {
                Button(action: onTap) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: cell.level, dictations: cell.dictations))
                        .frame(width: size, height: size)
                }
                .buttonStyle(.plain)
                .help(tooltip)
            } else {
                Color.clear
                    .frame(width: size, height: size)
            }
        }
    }

    private func color(for level: ActivityLevel, dictations: Int) -> Color {
        if dictations == 0 {
            return Color.primary.opacity(0.06)
        }
        switch level {
        case .none: return Color.primary.opacity(0.06)
        case .low: return Color.wesleyBlue.opacity(0.35)
        case .medium: return Color.wesleyBlue.opacity(0.55)
        case .high: return Color.wesleyBlue.opacity(0.80)
        case .veryHigh: return Color.wesleyBlue
        }
    }
}

private struct ActivityLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            Spacer()

            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 9, height: 9)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.wesleyBlue.opacity(0.35))
                .frame(width: 9, height: 9)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.wesleyBlue.opacity(0.55))
                .frame(width: 9, height: 9)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.wesleyBlue.opacity(0.80))
                .frame(width: 9, height: 9)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.wesleyBlue)
                .frame(width: 9, height: 9)

            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Apps Section & Brand Colors

private struct AppsInsightSection: View {
    let apps: [AppUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            if apps.isEmpty {
                Text("No application data recorded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                let maxWords = max(1, apps.first?.words ?? 1)
                VStack(spacing: 8) {
                    ForEach(Array(apps.prefix(5).enumerated()), id: \.element.id) { index, app in
                        AppUsageBarRow(
                            app: app,
                            color: AppColorProvider.color(for: app.name, index: index),
                            maxWords: maxWords
                        )
                    }
                }
            }
        }
    }
}

private struct AppUsageBarRow: View {
    let app: AppUsage
    let color: Color
    let maxWords: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(app.name.isEmpty ? "Unknown App" : app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text("\(InsightsFormat.count(app.words)) words")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let fraction = min(1.0, max(0.04, Double(app.words) / Double(maxWords)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: proxy.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
        .help("\(app.name): \(InsightsFormat.dictations(app.dictations)) · \(InsightsFormat.count(app.words)) words · \(InsightsFormat.duration(app.seconds))")
    }
}

// MARK: - Usage (Time of Day) Section

private struct TimeOfDaySlice: Identifiable, Equatable, Sendable {
    let name: String
    let range: String
    let icon: String
    let dictations: Int
    let words: Int
    let seconds: TimeInterval
    let percentage: Double

    var id: String { name }
}

private struct UsageTimeInsightSection: View {
    let slices: [TimeOfDaySlice]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIME OF DAY")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            let maxDictations = max(1, slices.map(\.dictations).max() ?? 1)
            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    TimeSliceBarRow(
                        slice: slice,
                        maxDictations: maxDictations
                    )
                }
            }
        }
    }
}

private struct TimeSliceBarRow: View {
    let slice: TimeOfDaySlice
    let maxDictations: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: slice.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.wesleyBlue)
                    .frame(width: 14)

                Text(slice.name)
                    .font(.system(size: 13, weight: .medium))

                Text("(\(slice.range))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(InsightsFormat.dictations(slice.dictations))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let fraction = slice.dictations == 0 ? 0 : min(1.0, max(0.04, Double(slice.dictations) / Double(maxDictations)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.wesleyBlue.opacity(0.75))
                        .frame(width: proxy.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
        .help("\(slice.name): \(InsightsFormat.dictations(slice.dictations)) (\(InsightsFormat.percent(slice.percentage))) · \(InsightsFormat.duration(slice.seconds))")
    }
}

// MARK: - Dedicated Monthly Report

private struct MonthlyReportView: View {
    let model: InsightsViewModel
    let entries: [DictationEntry]
    let month: Date
    @Binding var selectedDay: Date?
    let onBack: () -> Void
    let onStepMonth: (Int) -> Void

    var body: some View {
        let calendar = model.calendar
        let monthInterval = calendar.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 86400 * 30)
        let monthStats = UsageStatisticsService.statistics(
            for: entries,
            in: monthInterval,
            calendar: calendar
        )
        let grid = monthStats.activityCalendar(in: monthInterval)
        let totalDaysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        VStack(alignment: .leading, spacing: 20) {
            // Header & Navigation
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.yearLabel(month))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color.wesleyBlue)
                }
                .buttonStyle(.plain)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(model.fullMonthLabel(month)) \(model.yearLabel(month))")
                    .font(.system(size: 24, weight: .bold, design: .serif))

                Spacer()

                HStack(spacing: 2) {
                    Button { onStepMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Previous month")

                    Button { onStepMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Next month")
                }
            }

            // Essential Monthly Summary
            HStack(spacing: 32) {
                EssentialMetric(
                    label: "ACTIVE DAYS",
                    value: "\(monthStats.activeDays) of \(totalDaysInMonth)"
                )
                EssentialMetric(
                    label: "DICTATIONS",
                    value: InsightsFormat.count(monthStats.totalDictations)
                )
                EssentialMetric(
                    label: "WORDS",
                    value: InsightsFormat.count(monthStats.totalWords)
                )
                EssentialMetric(
                    label: "ACTIVE TIME",
                    value: InsightsFormat.duration(monthStats.totalSeconds)
                )
            }
            .padding(.bottom, 2)

            Divider().opacity(0.5)

            // Monthly Activity Calendar
            VStack(alignment: .leading, spacing: 10) {
                Text("DAILY ACTIVITY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                MonthlyActivityCalendar(
                    model: model,
                    grid: grid,
                    selectedDay: $selectedDay
                )
            }

            // Clicked Day Detail Banner
            if let activeDay = effectiveDay(selectedDay: selectedDay, monthStats: monthStats) {
                MonthlyDayDetailCard(
                    day: activeDay,
                    dayStats: model.dayStatistics(for: entries, day: activeDay),
                    model: model
                )
            } else {
                Text("Select any day above to see its dictations.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            // Monthly Apps Breakdown
            if !monthStats.apps.isEmpty {
                Divider().opacity(0.5)
                AppsInsightSection(apps: monthStats.apps)
            }
        }
        .padding(.vertical, 4)
    }

    private func effectiveDay(selectedDay: Date?, monthStats: UsageStatistics) -> Date? {
        if let selectedDay { return selectedDay }
        return monthStats.days.last(where: { $0.dictations > 0 })?.day
    }
}

private struct MonthlyActivityCalendar: View {
    let model: InsightsViewModel
    let grid: ActivityCalendar
    @Binding var selectedDay: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Weekday labels column
            VStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { row in
                    Text(model.weekdaySymbols[row].prefix(2).uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 16, alignment: .trailing)
                }
            }
            .padding(.trailing, 4)

            // Columns of weeks
            ForEach(grid.weeks) { week in
                VStack(spacing: 4) {
                    ForEach(week.cells) { cell in
                        MonthlyGridCell(
                            cell: cell,
                            isSelected: isCellSelected(cell),
                            tooltip: model.activityDescription(cell),
                            onTap: {
                                if cell.isInRange {
                                    selectedDay = cell.day
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func isCellSelected(_ cell: ActivityCell) -> Bool {
        guard let selected = selectedDay else { return false }
        return cell.isInRange && model.calendar.isDate(cell.day, inSameDayAs: selected)
    }
}

private struct MonthlyGridCell: View {
    let cell: ActivityCell
    let isSelected: Bool
    let tooltip: String
    let onTap: () -> Void

    var body: some View {
        Group {
            if cell.isInRange {
                Button(action: onTap) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: cell.level, dictations: cell.dictations))
                        .frame(width: 16, height: 16)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.wesleyBlue, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(tooltip)
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func color(for level: ActivityLevel, dictations: Int) -> Color {
        if dictations == 0 {
            return Color.primary.opacity(0.06)
        }
        switch level {
        case .none: return Color.primary.opacity(0.06)
        case .low: return Color.wesleyBlue.opacity(0.35)
        case .medium: return Color.wesleyBlue.opacity(0.55)
        case .high: return Color.wesleyBlue.opacity(0.80)
        case .veryHigh: return Color.wesleyBlue
        }
    }
}

private struct MonthlyDayDetailCard: View {
    let day: Date
    let dayStats: UsageStatistics
    let model: InsightsViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.fullDayLabel(day))
                    .font(.system(size: 13, weight: .semibold))
                Text(dayStats.totalDictations > 0 ? "Daily Activity" : "No activity recorded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if dayStats.totalDictations > 0 {
                HStack(spacing: 16) {
                    Text(InsightsFormat.dictations(dayStats.totalDictations))
                        .font(.system(size: 13, weight: .medium))

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text("\(InsightsFormat.count(dayStats.totalWords)) words")
                        .font(.system(size: 13, weight: .medium))

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(InsightsFormat.duration(dayStats.totalSeconds))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.wesleyBlue)
                }
            } else {
                Text("0 dictations")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Reusable Metric Display

private struct EssentialMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .monospacedDigit()
        }
    }
}

// MARK: - Deterministic Distinct App Color Provider

enum AppColorProvider {
    private static let brandColors: [String: Color] = [
        "whatsapp": Color(red: 0.15, green: 0.83, blue: 0.40),       // WhatsApp Green #25D366
        "safari": Color(red: 0.00, green: 0.48, blue: 1.00),         // Safari Blue #007AFF
        "notes": Color(red: 0.96, green: 0.65, blue: 0.14),          // Notes Gold #F5A623
        "terminal": Color(red: 0.18, green: 0.80, blue: 0.44),       // Terminal Emerald #2ECC71
        "iterm": Color(red: 0.10, green: 0.74, blue: 0.61),          // iTerm Teal #1ABC9C
        "iterm2": Color(red: 0.10, green: 0.74, blue: 0.61),
        "code": Color(red: 0.00, green: 0.48, blue: 0.80),           // VS Code Azure #007ACC
        "visual studio code": Color(red: 0.00, green: 0.48, blue: 0.80),
        "xcode": Color(red: 0.08, green: 0.49, blue: 0.98),          // Xcode Blue #147EFB
        "slack": Color(red: 0.29, green: 0.08, blue: 0.29),          // Slack Aubergine #4A154B
        "messages": Color(red: 0.20, green: 0.78, blue: 0.35),       // Messages Green #34C759
        "mail": Color(red: 0.11, green: 0.55, blue: 0.97),           // Mail Blue #1D8BF8
        "music": Color(red: 0.98, green: 0.18, blue: 0.28),          // Music Magenta #FA2D48
        "chrome": Color(red: 0.90, green: 0.49, blue: 0.13),         // Chrome Amber-Orange #E67E22
        "google chrome": Color(red: 0.90, green: 0.49, blue: 0.13),
        "firefox": Color(red: 1.00, green: 0.44, blue: 0.22),        // Firefox Orange #FF7139
        "figma": Color(red: 0.64, green: 0.35, blue: 1.00),          // Figma Purple #A259FF
        "notion": Color(red: 0.18, green: 0.20, blue: 0.22),         // Notion Charcoal #2F3437
        "discord": Color(red: 0.35, green: 0.40, blue: 0.95),        // Discord Blurple #5865F2
        "pages": Color(red: 1.00, green: 0.58, blue: 0.00),          // Pages Orange #FF9500
        "keynote": Color(red: 0.04, green: 0.52, blue: 1.00),        // Keynote Blue #0A84FF
        "numbers": Color(red: 0.19, green: 0.82, blue: 0.35),        // Numbers Green #30D158
        "reminders": Color(red: 1.00, green: 0.23, blue: 0.19),      // Reminders Coral
        "calendar": Color(red: 1.00, green: 0.27, blue: 0.23)        // Calendar Red
    ]

    private static let fallbackPalette: [Color] = [
        Color(red: 0.24, green: 0.51, blue: 0.96), // Indigo
        Color(red: 0.85, green: 0.37, blue: 0.15), // Rust
        Color(red: 0.12, green: 0.65, blue: 0.53), // Teal
        Color(red: 0.70, green: 0.28, blue: 0.68), // Orchid
        Color(red: 0.88, green: 0.60, blue: 0.12), // Honey
        Color(red: 0.32, green: 0.60, blue: 0.85), // Cerulean
        Color(red: 0.82, green: 0.25, blue: 0.40), // Crimson
        Color(red: 0.38, green: 0.68, blue: 0.35), // Sage
        Color(red: 0.55, green: 0.40, blue: 0.80), // Amethyst
        Color(red: 0.20, green: 0.68, blue: 0.75)  // Cyan
    ]

    static func color(for appName: String, index: Int = 0) -> Color {
        let lower = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = brandColors[lower] {
            return direct
        }
        for (key, color) in brandColors {
            if lower.contains(key) {
                return color
            }
        }
        var hash: UInt = 5381
        for byte in lower.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt(byte)
        }
        let paletteIndex = Int((hash &+ UInt(index * 3)) % UInt(fallbackPalette.count))
        return fallbackPalette[paletteIndex]
    }
}
