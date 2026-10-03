import Foundation
import Observation

/// Presentation state and display strings for Insights.
///
/// Completes the chain the data layer starts:
/// `HistoryStore` → `UsageStatisticsService` → `UsageStatistics` →
/// `InsightsViewModel` → views. Views read already-computed numbers and
/// already-rendered strings; nothing here runs inside a `body` more than once
/// per history change, because every aggregate is memoised.
///
/// The split is deliberate: `UsageStatistics` holds no user-facing text, so it
/// stays locale-independent and assertable; every string lives here or in
/// `InsightsFormat`.

// MARK: - Selections

/// The five things the Insights header can put in focus.
///
/// "Apps" stands where a commands breakdown would sit. `DictationEntry` has no
/// dictation-vs-command discriminator, so a commands count cannot be derived
/// from the history that already exists — inventing one would mean guessing.
/// Frontmost-app attribution is recorded, so it is shown instead.
enum InsightsFocus: String, CaseIterable, Identifiable, Sendable {
    case activity
    case time
    case dictations
    case words
    case apps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: "Activity"
        case .time: "Time"
        case .dictations: "Dictations"
        case .words: "Words"
        case .apps: "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .activity: "square.grid.3x3"
        case .time: "clock"
        case .dictations: "waveform"
        case .words: "text.alignleft"
        case .apps: "macwindow"
        }
    }
}

/// The reporting window: one calendar month or one calendar year.
enum InsightsScope: String, CaseIterable, Identifiable, Sendable {
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Month"
        case .year: "Year"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .month: .month
        case .year: .year
        }
    }
}

/// A headline number in the overview row. Each one is clickable and opens the
/// matching detail.
enum InsightsMetric: String, CaseIterable, Identifiable, Sendable {
    case dictations
    case speakingTime
    case words
    case activeDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictations: "Dictations"
        case .speakingTime: "Speaking Time"
        case .words: "Words"
        case .activeDays: "Active Days"
        }
    }

    var symbol: String {
        switch self {
        case .dictations: "waveform"
        case .speakingTime: "clock"
        case .words: "text.alignleft"
        case .activeDays: "calendar"
        }
    }
}

/// What a detail view is showing. Selecting one never changes the underlying
/// numbers — it only picks which slice of them to explain.
enum InsightsDetail: Hashable, Identifiable, Sendable {
    case metric(InsightsMetric)
    /// A three-hour band, identified by its inclusive first hour.
    case timeBand(startHour: Int)
    /// One local day, identified by its start.
    case day(Date)

    var id: String {
        switch self {
        case .metric(let metric): "metric.\(metric.rawValue)"
        case .timeBand(let startHour): "band.\(startHour)"
        case .day(let day): "day.\(day.timeIntervalSinceReferenceDate)"
        }
    }
}

// MARK: - Rendered values

/// One tile in the overview row.
struct InsightsSummaryTile: Identifiable, Equatable, Sendable {
    let metric: InsightsMetric
    let title: String
    let value: String
    let caption: String

    var id: String { metric.rawValue }
}

/// A labelled number inside a detail view.
struct InsightsHighlight: Identifiable, Equatable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

/// One proportional row inside a detail view.
struct InsightsBreakdownItem: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    /// 0...1, measured against the largest row in the same breakdown — so the
    /// bars compare rows with each other, never against an absolute the reader
    /// cannot see.
    let fraction: Double

    var id: String { label }
}

/// A titled group of proportional rows. Absent when every row would be zero,
/// rather than drawn as a panel full of empty bars.
struct InsightsBreakdown: Equatable, Sendable {
    let title: String
    let items: [InsightsBreakdownItem]
}

/// Everything a detail view renders, resolved up front.
struct InsightsDetailReport: Equatable, Sendable {
    /// What is being explained, e.g. "Speaking Time" or "6 PM – 9 PM".
    let title: String
    /// The window it is scoped to, e.g. "September 2026".
    let scope: String
    /// The headline figure.
    let value: String
    /// One line of plain-language context under the headline.
    let caption: String
    /// Zero-filled daily usage for the window, for the detail chart. Empty for
    /// details that a per-day chart would misrepresent.
    let series: [DayUsage]
    let highlights: [InsightsHighlight]
    /// Proportional rows explaining how the headline splits up, or `nil` when
    /// the slice has nothing to split.
    let breakdown: InsightsBreakdown?
}

// MARK: - Formatting

/// Pure, calendar-free string rendering.
///
/// Kept off the view model — and off any actor — so it can be called from
/// anywhere and asserted directly in tests. Durations and clock labels are
/// composed by hand rather than through a locale-sensitive style, so the same
/// seconds always print the same string on any machine.
enum InsightsFormat {

    /// "1h 24m" / "3m 12s" / "45s". Zero and anything negative read as "0s"
    /// rather than as an empty string.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "0s" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60

        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return remainder > 0 ? "\(minutes)m \(remainder)s" : "\(minutes)m" }
        return "\(remainder)s"
    }

    /// Grouped count, e.g. "12,480" — the one place a locale is welcome,
    /// because digit grouping is exactly what a reader expects to be local.
    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// One decimal place, for averages that would be misleading as integers.
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "12 AM", "9 AM", "12 PM", "6 PM".
    static func hour(_ hour: Int) -> String {
        let normalised = ((hour % 24) + 24) % 24
        switch normalised {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case 1..<12: return "\(normalised) AM"
        default: return "\(normalised - 12) PM"
        }
    }

    /// "6 PM – 9 PM". The end hour is exclusive, and 24 wraps to "12 AM".
    static func band(startHour: Int, endHour: Int) -> String {
        "\(self.hour(startHour)) – \(self.hour(endHour))"
    }

    /// "3 dictations" / "1 dictation".
    static func dictations(_ value: Int) -> String {
        "\(count(value)) \(value == 1 ? "dictation" : "dictations")"
    }

    /// "38%", from a 0...1 fraction. Whole percent on purpose — a tenth of a
    /// percent of a month's dictations is noise, not information.
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }
}

// MARK: - View model

@MainActor
@Observable
final class InsightsViewModel {

    /// Which control in the header is selected.
    var focus: InsightsFocus = .activity
    /// Bucket size for the usage chart.
    var granularity: UsageGranularity = .daily
    /// Month or year reporting.
    var scope: InsightsScope = .month
    /// Any instant inside the window on screen. Stored rather than a
    /// `DateInterval` so stepping forward and back is a single calendar call
    /// and month lengths take care of themselves.
    var anchor: Date
    /// The open detail, or `nil` for the overview.
    ///
    /// Read-only from the outside so every entry and exit goes through `open`
    /// and `closeDetail`, which is what keeps the back stack honest.
    private(set) var detail: InsightsDetail?

    /// The details already open behind `detail`, oldest first.
    ///
    /// A metric detail charts its window by day, and those bars open a day
    /// detail — so stepping back from the day has to land on the metric that
    /// led there, not on the overview.
    private(set) var detailStack: [InsightsDetail] = []

    /// Fixed for the lifetime of the view model so bucketing, streaks and the
    /// rendered dates can never disagree. Injectable for tests.
    let calendar: Calendar

    /// The seven weekday abbreviations in grid order, starting at the calendar's
    /// `firstWeekday`.
    ///
    /// `Calendar.shortWeekdaySymbols` is always Sunday-indexed regardless of
    /// `firstWeekday`, so the rotation is done explicitly here rather than left
    /// to a guess at the call site. Resolved once, because pulling symbols out
    /// of a calendar is not free and the grid asks for them on every render.
    let weekdaySymbols: [String]

    /// The seven full weekday names in the same grid order, for row labels
    /// where an abbreviation would read as an abbreviation of nothing.
    let weekdayNames: [String]

    private let monthYearStyle: Date.FormatStyle
    private let yearStyle: Date.FormatStyle
    private let monthStyle: Date.FormatStyle
    private let fullMonthStyle: Date.FormatStyle
    private let dayStyle: Date.FormatStyle
    private let weekdayStyle: Date.FormatStyle

    // Held in observation-ignored storage on purpose. A view calls
    // `statistics(for:)` from inside `body`; if the cache were observed, that
    // read would register a dependency and the write would trip SwiftUI's
    // "Modifying state during view update" warning. `.onChange(initial: true)`
    // was the alternative and was rejected — it renders one empty frame first.
    @ObservationIgnored private var overallCache: (signature: HistorySignature, statistics: UsageStatistics)?
    @ObservationIgnored private var scopedCache: (signature: HistorySignature, window: DateInterval, statistics: UsageStatistics)?
    @ObservationIgnored private var activityCache: (signature: HistorySignature, window: DateInterval, grid: ActivityCalendar)?
    @ObservationIgnored private var dayCache: (signature: HistorySignature, day: Date, statistics: UsageStatistics)?

    init(calendar: Calendar = .current, anchor: Date = .now) {
        self.calendar = calendar
        self.anchor = anchor
        self.weekdaySymbols = Self.rotate(calendar.shortWeekdaySymbols, firstWeekday: calendar.firstWeekday)
        self.weekdayNames = Self.rotate(calendar.weekdaySymbols, firstWeekday: calendar.firstWeekday)
        self.monthYearStyle = Self.pin(.dateTime.month(.wide).year(), to: calendar)
        self.yearStyle = Self.pin(.dateTime.year(), to: calendar)
        self.monthStyle = Self.pin(.dateTime.month(.abbreviated), to: calendar)
        self.fullMonthStyle = Self.pin(.dateTime.month(.wide), to: calendar)
        self.dayStyle = Self.pin(.dateTime.month(.abbreviated).day(), to: calendar)
        self.weekdayStyle = Self.pin(.dateTime.weekday(.abbreviated).month(.abbreviated).day(), to: calendar)
    }

    /// Rotates a Sunday-indexed symbol array into grid order.
    ///
    /// Both of `Calendar`'s weekday symbol arrays are Sunday-first regardless of
    /// `firstWeekday`, so the rotation is done explicitly here rather than left
    /// to a guess at the call site.
    private static func rotate(_ symbols: [String], firstWeekday: Int) -> [String] {
        guard symbols.count == 7 else { return symbols }
        let offset = firstWeekday - 1
        return (0..<7).map { symbols[((offset + $0) % 7 + 7) % 7] }
    }

    private static func pin(_ style: Date.FormatStyle, to calendar: Calendar) -> Date.FormatStyle {
        var pinned = style
        pinned.calendar = calendar
        pinned.timeZone = calendar.timeZone
        return pinned
    }

    // MARK: Window

    /// The half-open window currently being reported on.
    ///
    /// Half-open matches `Calendar.dateInterval(of:for:)`, so an entry landing
    /// exactly on the first instant of the next month belongs to that month and
    /// is never counted twice.
    var window: DateInterval {
        calendar.dateInterval(of: scope.component, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 86_400)
    }

    /// "September 2026" or "2026".
    var windowTitle: String {
        switch scope {
        case .month: anchor.formatted(monthYearStyle)
        case .year: anchor.formatted(yearStyle)
        }
    }

    /// Moves the window by whole months or whole years.
    func step(by delta: Int) {
        guard let moved = calendar.date(byAdding: scope.component, value: delta, to: anchor) else { return }
        anchor = moved
        // A detail explains one window. Moving the window would leave it
        // explaining a slice that is no longer on screen, so it closes.
        dismissDetails()
    }

    /// False once the window already contains the present, so the UI can stop
    /// the reader paging into empty future months.
    func canStepForward(now: Date = .now) -> Bool {
        window.end <= now
    }

    /// Every year the history touches, ascending. Empty when there is no
    /// history, so the UI can hide the year switcher entirely.
    func years(in statistics: UsageStatistics) -> [Int] {
        guard let first = statistics.firstDay, let last = statistics.lastDay else { return [] }
        let start = calendar.component(.year, from: first)
        let end = calendar.component(.year, from: last)
        guard start <= end else { return [start] }
        return Array(start...end)
    }

    /// Jumps to a year, keeping the month-of-year where that makes sense.
    func show(year: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: anchor)
        components.year = year
        // Clamp the day so 31 January → a 30-day month cannot fail to resolve.
        components.day = 1
        if let moved = calendar.date(from: components) {
            anchor = moved
            dismissDetails()
        }
    }

    // MARK: Statistics

    /// Aggregates over the whole history, memoised.
    func statistics(for entries: [DictationEntry]) -> UsageStatistics {
        let signature = HistorySignature(entries)
        if let overallCache, overallCache.signature == signature { return overallCache.statistics }

        let statistics = UsageStatisticsService.statistics(for: entries, calendar: calendar)
        overallCache = (signature, statistics)
        return statistics
    }

    /// Aggregates over the current window, memoised on both the history and the
    /// window, so paging months does not re-scan history the reader already saw.
    func windowStatistics(for entries: [DictationEntry]) -> UsageStatistics {
        let signature = HistorySignature(entries)
        let window = window
        if let scopedCache, scopedCache.signature == signature, scopedCache.window == window {
            return scopedCache.statistics
        }

        let statistics = UsageStatisticsService.statistics(for: entries, in: window, calendar: calendar)
        scopedCache = (signature, window, statistics)
        return statistics
    }

    /// The activity grid for the current window, memoised.
    ///
    /// Built from the *whole-history* statistics on purpose.
    /// `activityCalendar(in:)` derives its intensity scale from every day it
    /// knows about, so handing it window statistics would re-scale the shading
    /// each time the reader paged to another month — the same cell count would
    /// change colour for no reason the reader could see.
    func activityCalendar(for entries: [DictationEntry]) -> ActivityCalendar {
        let signature = HistorySignature(entries)
        let window = window
        if let activityCache, activityCache.signature == signature, activityCache.window == window {
            return activityCache.grid
        }

        let grid = statistics(for: entries).activityCalendar(in: window)
        activityCache = (signature, window, grid)
        return grid
    }

    /// Aggregates a single local day, memoised.
    ///
    /// A day detail cannot be read off the window statistics: `apps` and `hours`
    /// there are summed across every day in the window, so attributing them to
    /// one day would attribute the whole month's apps to it. The day is
    /// re-aggregated instead, which is honest and — at one day's worth of
    /// filtering — cheap.
    func dayStatistics(for entries: [DictationEntry], day: Date) -> UsageStatistics {
        let start = calendar.startOfDay(for: day)
        let signature = HistorySignature(entries)
        if let dayCache, dayCache.signature == signature, dayCache.day == start {
            return dayCache.statistics
        }

        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let statistics = UsageStatisticsService.statistics(
            for: entries,
            in: DateInterval(start: start, end: end),
            calendar: calendar
        )
        dayCache = (signature, start, statistics)
        return statistics
    }

    /// Bars for the usage chart.
    ///
    /// A bucket finer than the window comes from the window; a bucket as coarse
    /// as it or coarser comes from the whole history. Otherwise "Yearly" inside
    /// a month would draw a single bar and say nothing.
    ///
    /// Daily is the one case that is zero-filled: a month chart with the quiet
    /// days missing would compress the busy ones together and read as denser
    /// usage than actually happened.
    func usageBuckets(overall: UsageStatistics, scoped: UsageStatistics) -> [PeriodUsage] {
        guard usesWindow(for: granularity) else { return overall.buckets(granularity) }

        guard granularity == .daily else { return scoped.buckets(granularity) }

        return scoped.dailySeries(in: window).map { day in
            PeriodUsage(
                start: day.day,
                granularity: .daily,
                dictations: day.dictations,
                seconds: day.seconds,
                words: day.words
            )
        }
    }

    /// Whether `granularity` is finer than the reporting scope.
    func usesWindow(for granularity: UsageGranularity) -> Bool {
        func rank(_ granularity: UsageGranularity) -> Int {
            switch granularity {
            case .daily: 0
            case .weekly: 1
            case .monthly: 2
            case .yearly: 3
            }
        }
        let scopeRank = scope == .month ? 2 : 3
        return rank(granularity) < scopeRank
    }

    /// Bucket sizes worth offering at the current scope.
    ///
    /// Deliberately narrower than `UsageGranularity.allCases`: "Yearly" inside a
    /// month is one bar, and "Daily" across a year is 365 of them. Both are
    /// honest and both are unreadable, so the picker does not offer them.
    var availableGranularities: [UsageGranularity] {
        switch scope {
        case .month: [.daily, .weekly]
        case .year: [.weekly, .monthly]
        }
    }

    /// Switches scope, keeping the bucket size legal for the new one.
    ///
    /// Done here rather than in a view so the correction never happens during a
    /// `body` evaluation.
    func select(scope newScope: InsightsScope) {
        guard scope != newScope else { return }
        scope = newScope
        if !availableGranularities.contains(granularity) {
            granularity = availableGranularities.first ?? .daily
        }
        dismissDetails()
    }

    // MARK: Navigation

    /// Opens a detail, remembering whatever was on screen so `closeDetail` can
    /// step back to it.
    ///
    /// Re-opening the detail already on screen is a no-op rather than a second
    /// stack entry, so a double-click cannot make the back button need pressing
    /// twice.
    func open(_ detail: InsightsDetail) {
        guard self.detail != detail else { return }
        if let current = self.detail { detailStack.append(current) }
        self.detail = detail
    }

    /// Steps back one level: to the detail that opened this one, or — when
    /// nothing opened it — to the overview.
    func closeDetail() {
        detail = detailStack.popLast()
    }

    /// Closes every open detail at once.
    ///
    /// Used when the window itself moves: the numbers a detail is explaining
    /// would no longer be the numbers on screen.
    func dismissDetails() {
        detail = nil
        detailStack.removeAll()
    }

    /// What the back control leads to — the detail underneath, or "Insights".
    var backTitle: String {
        guard let previous = detailStack.last else { return "Insights" }
        return title(for: previous)
    }

    /// The short name of a detail, as used in the back control.
    func title(for detail: InsightsDetail) -> String {
        switch detail {
        case .metric(let metric): metric.title
        case .timeBand(let startHour): InsightsFormat.band(startHour: startHour, endHour: startHour + 3)
        case .day(let day): dayLabel(calendar.startOfDay(for: day))
        }
    }

    // MARK: Overview

    /// The four headline tiles, in reading order.
    func summary(for statistics: UsageStatistics) -> [InsightsSummaryTile] {
        let dayCount = calendar.dateComponents([.day], from: window.start, to: window.end).day ?? 0

        return [
            InsightsSummaryTile(
                metric: .dictations,
                title: InsightsMetric.dictations.title,
                value: InsightsFormat.count(statistics.totalDictations),
                caption: statistics.timedDictations == statistics.totalDictations
                    ? "in \(windowTitle)"
                    : "\(InsightsFormat.count(statistics.timedDictations)) timed"
            ),
            InsightsSummaryTile(
                metric: .speakingTime,
                title: InsightsMetric.speakingTime.title,
                value: InsightsFormat.duration(statistics.totalSeconds),
                caption: statistics.timedDictations > 0
                    ? "\(InsightsFormat.duration(statistics.averageSeconds)) average"
                    : "nothing timed yet"
            ),
            InsightsSummaryTile(
                metric: .words,
                title: InsightsMetric.words.title,
                value: InsightsFormat.count(statistics.totalWords),
                caption: statistics.totalDictations > 0
                    ? "\(InsightsFormat.decimal(statistics.averageWords)) per dictation"
                    : "no words yet"
            ),
            InsightsSummaryTile(
                metric: .activeDays,
                title: InsightsMetric.activeDays.title,
                value: InsightsFormat.count(statistics.activeDays),
                caption: dayCount > 0 ? "of \(dayCount)" : ""
            )
        ]
    }

    // MARK: Details

    /// Resolves an open detail into everything its view renders.
    ///
    /// Takes the raw history rather than a pre-made `UsageStatistics` because a
    /// day detail needs its own one-day aggregation — see `dayStatistics`.
    /// Everything else is explained against the window on screen, not against
    /// all of history.
    func report(for detail: InsightsDetail, entries: [DictationEntry]) -> InsightsDetailReport {
        switch detail {
        case .metric(let metric):
            return metricReport(metric, statistics: windowStatistics(for: entries))
        case .timeBand(let startHour):
            return bandReport(startHour: startHour, statistics: windowStatistics(for: entries))
        case .day(let day):
            return dayReport(day, statistics: dayStatistics(for: entries, day: day))
        }
    }

    /// Builds a proportional breakdown, or `nil` when there is nothing to split.
    ///
    /// Fractions are measured against the largest row rather than against the
    /// total, so the bars compare rows with each other — the same convention the
    /// time-bands panel already uses. A breakdown whose rows are all zero is
    /// dropped rather than drawn as a panel full of empty bars.
    private func makeBreakdown(
        _ title: String,
        rows: [(label: String, weight: Double, value: String)],
        dropZeros: Bool = true
    ) -> InsightsBreakdown? {
        guard let peak = rows.map(\.weight).max(), peak > 0 else { return nil }
        let kept = dropZeros ? rows.filter { $0.weight > 0 } : rows
        guard !kept.isEmpty else { return nil }

        return InsightsBreakdown(
            title: title,
            items: kept.map {
                InsightsBreakdownItem(label: $0.label, value: $0.value, fraction: $0.weight / peak)
            }
        )
    }

    /// The top apps for a statistics slice, as breakdown rows.
    ///
    /// Capped because a long tail of one-dictation apps is a scroll, not an
    /// insight; `apps` is already sorted by words descending, so `weighted`
    /// re-sorts only when the caller measures something else.
    private func appRows(
        _ statistics: UsageStatistics,
        limit: Int = 6,
        weight: (AppUsage) -> Double,
        value: (AppUsage) -> String
    ) -> [(label: String, weight: Double, value: String)] {
        statistics.apps
            .map { (label: $0.name, weight: weight($0), value: value($0)) }
            .sorted { $0.weight > $1.weight }
            .prefix(limit)
            .map { $0 }
    }

    private func metricReport(_ metric: InsightsMetric, statistics: UsageStatistics) -> InsightsDetailReport {
        let series = statistics.dailySeries(in: window)
        var highlights: [InsightsHighlight] = []
        var breakdown: InsightsBreakdown?
        let value: String
        let caption: String

        switch metric {
        case .dictations:
            value = InsightsFormat.count(statistics.totalDictations)
            caption = "\(InsightsFormat.dictations(statistics.totalDictations)) across \(InsightsFormat.count(statistics.activeDays)) active days"
            if let busiest = statistics.busiestDay {
                highlights.append(InsightsHighlight(label: "Busiest day", value: "\(dayLabel(busiest.day)) · \(InsightsFormat.count(busiest.dictations))"))
            }
            if let hour = statistics.busiestHour {
                highlights.append(InsightsHighlight(label: "Peak hour", value: "\(InsightsFormat.hour(hour.hour)) · \(InsightsFormat.count(hour.dictations))"))
            }
            highlights.append(InsightsHighlight(label: "Per active day", value: perActiveDay(statistics)))
            breakdown = makeBreakdown(
                "By App",
                rows: appRows(
                    statistics,
                    weight: { Double($0.dictations) },
                    value: { InsightsFormat.count($0.dictations) }
                )
            )

        case .speakingTime:
            value = InsightsFormat.duration(statistics.totalSeconds)
            caption = statistics.timedDictations > 0
                ? "\(InsightsFormat.dictations(statistics.timedDictations)) with a measured duration"
                : "no dictation in this period was timed"
            highlights.append(InsightsHighlight(label: "Average", value: InsightsFormat.duration(statistics.averageSeconds)))
            if let longest = statistics.days.max(by: { $0.seconds < $1.seconds }), longest.seconds > 0 {
                highlights.append(InsightsHighlight(label: "Longest day", value: "\(dayLabel(longest.day)) · \(InsightsFormat.duration(longest.seconds))"))
            }
            if statistics.wordsPerMinute > 0 {
                highlights.append(InsightsHighlight(label: "Words per minute", value: InsightsFormat.decimal(statistics.wordsPerMinute)))
            }
            breakdown = makeBreakdown(
                "By App",
                rows: appRows(
                    statistics,
                    weight: { $0.seconds },
                    value: { InsightsFormat.duration($0.seconds) }
                )
            )

        case .words:
            value = InsightsFormat.count(statistics.totalWords)
            caption = "\(InsightsFormat.count(statistics.totalCharacters)) characters written"
            highlights.append(InsightsHighlight(label: "Per dictation", value: InsightsFormat.decimal(statistics.averageWords)))
            if let wordiest = statistics.days.max(by: { $0.words < $1.words }), wordiest.words > 0 {
                highlights.append(InsightsHighlight(label: "Most words", value: "\(dayLabel(wordiest.day)) · \(InsightsFormat.count(wordiest.words))"))
            }
            if let top = statistics.apps.first {
                highlights.append(InsightsHighlight(label: "Most used in", value: "\(top.name) · \(InsightsFormat.count(top.words))"))
            }
            breakdown = makeBreakdown(
                "By App",
                rows: appRows(
                    statistics,
                    weight: { Double($0.words) },
                    value: { InsightsFormat.count($0.words) }
                )
            )

        case .activeDays:
            value = InsightsFormat.count(statistics.activeDays)
            let dayCount = calendar.dateComponents([.day], from: window.start, to: window.end).day ?? 0
            caption = dayCount > 0
                ? "active on \(InsightsFormat.count(statistics.activeDays)) of \(InsightsFormat.count(dayCount)) days"
                : "no days in range"
            highlights.append(InsightsHighlight(label: "Longest streak", value: "\(InsightsFormat.count(statistics.longestStreak))d"))
            if let first = statistics.firstDay {
                highlights.append(InsightsHighlight(label: "First", value: dayLabel(first)))
            }
            if let last = statistics.lastDay {
                highlights.append(InsightsHighlight(label: "Last", value: dayLabel(last)))
            }
            breakdown = makeBreakdown(
                "By Weekday",
                rows: weekdayRows(statistics),
                // Every weekday stays, zero included: a week with a quiet
                // Sunday is the shape being described, and dropping the row
                // would hide it.
                dropZeros: false
            )
        }

        return InsightsDetailReport(
            title: metric.title,
            scope: windowTitle,
            value: value,
            caption: caption,
            series: series,
            highlights: highlights,
            breakdown: breakdown
        )
    }

    /// Active days per weekday, in the calendar's own grid order.
    private func weekdayRows(_ statistics: UsageStatistics) -> [(label: String, weight: Double, value: String)] {
        var counts = [Int](repeating: 0, count: 7)
        for day in statistics.days where day.dictations > 0 {
            // `weekday` is 1-based and Sunday-first; `weekdayNames` was rotated
            // into grid order at init, so undo the calendar's start offset here.
            let weekday = calendar.component(.weekday, from: day.day)
            let index = ((weekday - calendar.firstWeekday) % 7 + 7) % 7
            if counts.indices.contains(index) { counts[index] += 1 }
        }

        return (0..<7).map { index in
            let name = weekdayNames.indices.contains(index) ? weekdayNames[index] : ""
            return (label: name, weight: Double(counts[index]), value: InsightsFormat.count(counts[index]))
        }
    }

    private func bandReport(startHour: Int, statistics: UsageStatistics) -> InsightsDetailReport {
        let band = statistics.timeBands.first { $0.startHour == startHour }
            ?? TimeBandUsage(startHour: startHour, endHour: startHour + 3, dictations: 0, seconds: 0, words: 0, busiestHour: nil)

        var highlights = [
            InsightsHighlight(label: "Speaking time", value: InsightsFormat.duration(band.seconds)),
            InsightsHighlight(label: "Words", value: InsightsFormat.count(band.words))
        ]
        if let busiest = band.busiestHour {
            highlights.append(InsightsHighlight(label: "Most active hour", value: InsightsFormat.hour(busiest)))
        }
        if statistics.totalDictations > 0 {
            highlights.append(InsightsHighlight(
                label: "Share of \(scope.title.lowercased())",
                value: InsightsFormat.percent(Double(band.dictations) / Double(statistics.totalDictations))
            ))
        }

        let hours = statistics.hours.filter { $0.hour >= band.startHour && $0.hour < band.endHour }
        let breakdown = makeBreakdown(
            "By Hour",
            rows: hours.map { hour in
                (label: InsightsFormat.hour(hour.hour), weight: Double(hour.dictations), value: InsightsFormat.count(hour.dictations))
            },
            // A band is three hours whether or not all three were used; hiding
            // the quiet ones would change what the panel is describing.
            dropZeros: false
        )

        return InsightsDetailReport(
            title: InsightsFormat.band(startHour: band.startHour, endHour: band.endHour),
            scope: windowTitle,
            value: InsightsFormat.count(band.dictations),
            caption: InsightsFormat.dictations(band.dictations),
            // Hour-of-day usage is summed across every day in the window, so a
            // per-day chart underneath it would be charting something else.
            series: [],
            highlights: highlights,
            breakdown: breakdown
        )
    }

    private func dayReport(_ day: Date, statistics: UsageStatistics) -> InsightsDetailReport {
        let start = calendar.startOfDay(for: day)
        // `statistics` is the one-day aggregation from `dayStatistics`, so its
        // totals are already this day's — `days` holds at most one entry.
        let usage = statistics.days.first { $0.day == start }
            ?? DayUsage(day: start, dictations: 0, seconds: 0, words: 0, characters: 0)

        var highlights = [
            InsightsHighlight(label: "Speaking time", value: InsightsFormat.duration(usage.seconds)),
            InsightsHighlight(label: "Words", value: InsightsFormat.count(usage.words)),
            InsightsHighlight(label: "Characters", value: InsightsFormat.count(usage.characters))
        ]
        if let busiest = statistics.busiestHour {
            highlights.append(InsightsHighlight(label: "Busiest hour", value: InsightsFormat.hour(busiest.hour)))
        }

        let breakdown = makeBreakdown(
            "By App",
            rows: appRows(
                statistics,
                weight: { Double($0.dictations) },
                value: { InsightsFormat.count($0.dictations) }
            )
        )

        return InsightsDetailReport(
            title: fullDayLabel(start),
            scope: windowTitle,
            value: InsightsFormat.count(usage.dictations),
            caption: InsightsFormat.dictations(usage.dictations),
            series: [],
            highlights: highlights,
            breakdown: breakdown
        )
    }

    private func perActiveDay(_ statistics: UsageStatistics) -> String {
        guard statistics.activeDays > 0 else { return "0" }
        return InsightsFormat.decimal(Double(statistics.totalDictations) / Double(statistics.activeDays))
    }

    // MARK: Date strings

    /// "Sep 11".
    func dayLabel(_ day: Date) -> String { day.formatted(dayStyle) }

    /// "Fri, Sep 11".
    func fullDayLabel(_ day: Date) -> String { day.formatted(weekdayStyle) }

    /// "Sep".
    func monthLabel(_ month: Date) -> String { month.formatted(monthStyle) }

    /// "September".
    func fullMonthLabel(_ month: Date) -> String { month.formatted(fullMonthStyle) }

    /// "2026".
    func yearLabel(_ year: Date) -> String { year.formatted(yearStyle) }

    /// The x-axis label for a usage bar, at whatever granularity produced it.
    func bucketLabel(_ bucket: PeriodUsage) -> String {
        switch bucket.granularity {
        case .daily, .weekly: dayLabel(bucket.start)
        case .monthly: monthLabel(bucket.start)
        case .yearly: yearLabel(bucket.start)
        }
    }

    /// A full sentence for an activity cell, used as its accessibility label
    /// and its tooltip — intensity is never left to colour alone.
    func activityDescription(_ cell: ActivityCell) -> String {
        guard cell.isInRange else { return "" }
        if cell.dictations == 0 {
            return "\(fullDayLabel(cell.day)): No dictations"
        }
        var parts = ["\(fullDayLabel(cell.day)): \(InsightsFormat.dictations(cell.dictations))"]
        if cell.seconds > 0 {
            parts.append(InsightsFormat.duration(cell.seconds))
        }
        if cell.words > 0 {
            parts.append("\(InsightsFormat.count(cell.words)) words")
        }
        return parts.joined(separator: " · ")
    }

    /// A full sentence for a month day cell, used as its tooltip.
    func dayCellDescription(_ cell: MonthDayCell) -> String {
        if cell.dictations == 0 {
            return "\(fullDayLabel(cell.day)): No dictations"
        }
        var parts = ["\(fullDayLabel(cell.day)): \(InsightsFormat.dictations(cell.dictations))"]
        if cell.seconds > 0 {
            parts.append(InsightsFormat.duration(cell.seconds))
        }
        if cell.words > 0 {
            parts.append("\(InsightsFormat.count(cell.words)) words")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Year Summary

    struct MonthDayCell: Identifiable, Equatable, Sendable {
        let day: Date
        let dayNumber: Int
        let dictations: Int
        let seconds: TimeInterval
        let words: Int
        let level: ActivityLevel

        var id: Date { day }
    }

    struct MonthSummary: Identifiable, Equatable, Sendable {
        let start: Date
        let monthName: String
        let fullMonthName: String
        let dictations: Int
        let seconds: TimeInterval
        let words: Int
        let days: [MonthDayCell]

        var id: Date { start }
    }

    struct YearSummary: Equatable, Sendable {
        let totalDictations: Int
        let totalSeconds: TimeInterval
        let totalWords: Int
        let activeMonths: Int
        let totalMonthsInYear: Int
        let mostActiveMonth: MonthSummary?
        let averageMonthlyDictations: Double
        let averageMonthlyWords: Double
        let months: [MonthSummary]
    }

    func yearSummary(for statistics: UsageStatistics) -> YearSummary {
        var months: [MonthSummary] = []
        let calendar = self.calendar
        var cursor = window.start

        let daysLookup = Dictionary(uniqueKeysWithValues: statistics.days.map { ($0.day, $0) })
        let scale = ActivityScale.quartiles(of: statistics.days.map(\.dictations))

        while cursor < window.end {
            guard let monthInterval = calendar.dateInterval(of: .month, for: cursor) else { break }
            let monthName = monthLabel(cursor)
            let fullMonthName = fullMonthLabel(cursor)

            var dayCells: [MonthDayCell] = []
            var dayCursor = monthInterval.start
            var dayNumber = 1
            var monthDictations = 0
            var monthSeconds: TimeInterval = 0
            var monthWords = 0

            while dayCursor < monthInterval.end {
                let usage = daysLookup[dayCursor]
                let dictations = usage?.dictations ?? 0
                let seconds = usage?.seconds ?? 0
                let words = usage?.words ?? 0

                monthDictations += dictations
                monthSeconds += seconds
                monthWords += words

                dayCells.append(MonthDayCell(
                    day: dayCursor,
                    dayNumber: dayNumber,
                    dictations: dictations,
                    seconds: seconds,
                    words: words,
                    level: scale.level(for: dictations)
                ))

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                dayCursor = nextDay
                dayNumber += 1
            }

            months.append(MonthSummary(
                start: monthInterval.start,
                monthName: monthName,
                fullMonthName: fullMonthName,
                dictations: monthDictations,
                seconds: monthSeconds,
                words: monthWords,
                days: dayCells
            ))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        let active = months.filter { $0.dictations > 0 }
        let activeCount = active.count
        let mostActive = active.max(by: { $0.dictations < $1.dictations })
        let avgDictations = activeCount > 0 ? Double(statistics.totalDictations) / Double(activeCount) : 0
        let avgWords = activeCount > 0 ? Double(statistics.totalWords) / Double(activeCount) : 0

        return YearSummary(
            totalDictations: statistics.totalDictations,
            totalSeconds: statistics.totalSeconds,
            totalWords: statistics.totalWords,
            activeMonths: activeCount,
            totalMonthsInYear: months.count,
            mostActiveMonth: mostActive,
            averageMonthlyDictations: avgDictations,
            averageMonthlyWords: avgWords,
            months: months
        )
    }

    // MARK: Cache key

    /// A cheap stand-in for the identity of a history array.
    ///
    /// Comparing the whole array would cost more than the aggregation it is
    /// meant to avoid, so the count and the two endpoint dates stand in for it.
    /// Adding, deleting or reordering history moves at least one of the three.
    ///
    /// The honest limitation: a single update that both removes and adds an
    /// entry, where both the count and both endpoints survive unchanged, would
    /// reuse a stale aggregate. Nothing in the app does that — history is
    /// appended one dictation at a time and deleted one row at a time.
    private struct HistorySignature: Equatable {
        let count: Int
        let newest: Date?
        let oldest: Date?

        init(_ entries: [DictationEntry]) {
            count = entries.count
            // Reads only `date`, never `persistentModelID`, so this stays cheap
            // and never faults an entry in. Endpoints are min/max'd rather than
            // assumed, so the signature does not depend on `@Query`'s ordering.
            if let first = entries.first?.date, let last = entries.last?.date {
                newest = Swift.max(first, last)
                oldest = Swift.min(first, last)
            } else {
                newest = nil
                oldest = nil
            }
        }
    }
}
