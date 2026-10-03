import Foundation

/// Aggregated, already-summed usage. Produced once by
/// `UsageStatisticsService` and handed to the Insights UI as plain values, so
/// no view ever sums, sorts or buckets history inside `body`.
///
/// Everything here is derived from what `DictationEntry` actually records —
/// date, cleaned text, duration and frontmost app. Nothing is estimated.
///
/// Deliberately free of any user-facing string: no date formatting, no
/// localisation, no pluralisation. That keeps the type locale-independent and
/// makes every number assertable in a test. Display strings are the view
/// model's job.

// MARK: - Totals

/// Running totals shared by every aggregation pass.
struct UsageTotals: Equatable, Sendable {
    var dictations = 0
    var seconds: TimeInterval = 0
    var words = 0
    var characters = 0

    static let zero = UsageTotals()

    mutating func add(seconds: TimeInterval, words: Int, characters: Int) {
        dictations += 1
        self.seconds += seconds
        self.words += words
        self.characters += characters
    }
}

// MARK: - Buckets

/// One local day of usage. Only days that actually have entries exist;
/// `dailySeries(in:)` zero-fills the gaps when a chart needs them.
struct DayUsage: Identifiable, Equatable, Sendable {
    /// Start of the local day, per the calendar the statistics were built with.
    let day: Date
    let dictations: Int
    let seconds: TimeInterval
    let words: Int
    let characters: Int

    var id: Date { day }
}

/// One hour-of-day bucket, summed across every day in range. Always 0...23.
struct HourUsage: Identifiable, Equatable, Sendable {
    let hour: Int
    let dictations: Int
    let seconds: TimeInterval
    let words: Int

    var id: Int { hour }
}

/// Usage attributed to the app that was frontmost when the text was inserted.
struct AppUsage: Identifiable, Equatable, Sendable {
    let name: String
    let dictations: Int
    let words: Int
    let seconds: TimeInterval

    var id: String { name }
}

/// A calendar bucket — a day, week, month or year — for the usage chart.
struct PeriodUsage: Identifiable, Equatable, Sendable {
    let start: Date
    let granularity: UsageGranularity
    let dictations: Int
    let seconds: TimeInterval
    let words: Int

    var id: Date { start }
}

/// A three-hour slice of the day, for the time-of-day visualization.
struct TimeBandUsage: Identifiable, Equatable, Sendable {
    /// Inclusive first hour of the band: 0, 3, 6 ... 21.
    let startHour: Int
    /// Exclusive last hour of the band.
    let endHour: Int
    let dictations: Int
    let seconds: TimeInterval
    let words: Int
    /// Busiest hour inside the band, or `nil` when the band is empty.
    /// Ties resolve to the earlier hour.
    let busiestHour: Int?

    var id: Int { startHour }
}

enum UsageGranularity: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

// MARK: - Activity intensity

/// Five intensity steps for the activity grid.
///
/// Intensity must never be conveyed by colour alone — every cell also carries
/// its real count in its accessibility label and tooltip.
enum ActivityLevel: Int, CaseIterable, Comparable, Sendable {
    case none = 0
    case low
    case medium
    case high
    case veryHigh

    static func < (lhs: ActivityLevel, rhs: ActivityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Maps a day's dictation count onto an `ActivityLevel`.
///
/// The cut points are the 25th/50th/75th percentiles (nearest-rank) of the
/// *non-zero* daily counts, so the scale adapts to how much the person
/// actually dictates instead of hard-coding "4 or more is dark". Uniform data
/// collapses all three cut points onto the same value, which puts every active
/// day at `.low` — correct, since no day stands out.
struct ActivityScale: Equatable, Sendable {
    /// Inclusive upper bound of `.low`.
    let low: Int
    /// Inclusive upper bound of `.medium`.
    let medium: Int
    /// Inclusive upper bound of `.high`. Anything above is `.veryHigh`.
    let high: Int

    static let empty = ActivityScale(low: 0, medium: 0, high: 0)

    func level(for count: Int) -> ActivityLevel {
        guard count > 0 else { return .none }
        if count <= low { return .low }
        if count <= medium { return .medium }
        if count <= high { return .high }
        return .veryHigh
    }

    static func quartiles(of counts: [Int]) -> ActivityScale {
        let sorted = counts.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return .empty }

        func percentile(_ fraction: Double) -> Int {
            let rank = max(1, Int((fraction * Double(sorted.count)).rounded(.up)))
            return sorted[min(rank, sorted.count) - 1]
        }

        return ActivityScale(low: percentile(0.25), medium: percentile(0.5), high: percentile(0.75))
    }
}

/// One cell of the activity grid.
struct ActivityCell: Identifiable, Equatable, Sendable {
    let day: Date
    let dictations: Int
    let seconds: TimeInterval
    let words: Int
    let level: ActivityLevel
    /// `false` for the leading/trailing days a week column needs in order to
    /// stay seven cells tall. Those must render as empty space, not as a
    /// zero-activity day.
    let isInRange: Bool

    var id: Date { day }
}

/// One column of the activity grid: always seven cells, weekday-ordered per
/// the calendar's `firstWeekday`.
struct ActivityWeek: Identifiable, Equatable, Sendable {
    let start: Date
    let cells: [ActivityCell]

    var id: Date { start }
}

/// Where a month label sits above the grid.
struct ActivityMonthLabel: Identifiable, Equatable, Sendable {
    let weekIndex: Int
    let month: Date

    var id: Int { weekIndex }
}

/// A week-per-column activity grid over a fixed window.
struct ActivityCalendar: Equatable, Sendable {
    let weeks: [ActivityWeek]
    let monthLabels: [ActivityMonthLabel]
    let scale: ActivityScale
    /// The half-open window the grid covers.
    let interval: DateInterval
}

// MARK: - Statistics

struct UsageStatistics: Equatable, Sendable {
    let totalDictations: Int
    let totalSeconds: TimeInterval
    let totalWords: Int
    let totalCharacters: Int
    /// Entries with a measured duration.
    ///
    /// Command confirmations and Writing Tools polishes are recorded with
    /// `duration == 0`, so averaging speaking time over *every* entry would
    /// silently understate it. Averages divide by this instead.
    let timedDictations: Int
    /// Ascending, one element per day that has at least one entry.
    let days: [DayUsage]
    /// Exactly 24 elements, hour 0 through 23.
    let hours: [HourUsage]
    /// Descending by words. Entries with a blank app name are counted in the
    /// totals but excluded here — they cannot honestly be attributed.
    let apps: [AppUsage]
    /// The calendar every date above was bucketed with. Carried so derived
    /// views (streaks, week/month grouping) can never disagree with it.
    let calendar: Calendar

    static func empty(calendar: Calendar = .current) -> UsageStatistics {
        UsageStatistics(
            totalDictations: 0,
            totalSeconds: 0,
            totalWords: 0,
            totalCharacters: 0,
            timedDictations: 0,
            days: [],
            hours: (0..<24).map { HourUsage(hour: $0, dictations: 0, seconds: 0, words: 0) },
            apps: [],
            calendar: calendar
        )
    }

    var isEmpty: Bool { totalDictations == 0 }

    /// Days with at least one dictation.
    var activeDays: Int { days.count }

    var firstDay: Date? { days.first?.day }
    var lastDay: Date? { days.last?.day }

    /// Mean duration of the entries that were actually timed. Zero when none
    /// were, rather than a misleading small number.
    var averageSeconds: TimeInterval {
        guard timedDictations > 0 else { return 0 }
        return totalSeconds / Double(timedDictations)
    }

    /// Mean words per dictation across every entry.
    var averageWords: Double {
        guard totalDictations > 0 else { return 0 }
        return Double(totalWords) / Double(totalDictations)
    }

    /// Words per minute over the timed entries only. Zero when nothing was
    /// timed or the timed entries carry no words.
    var wordsPerMinute: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalWords) / (totalSeconds / 60)
    }

    /// Highest dictation count. Ties resolve to the earlier day.
    var busiestDay: DayUsage? {
        var best: DayUsage?
        for day in days where best == nil || day.dictations > best!.dictations {
            best = day
        }
        return best
    }

    /// Highest dictation count. Ties resolve to the earlier hour. `nil` when
    /// there is no usage at all.
    var busiestHour: HourUsage? {
        var best: HourUsage?
        for hour in hours where hour.dictations > 0 {
            if best == nil || hour.dictations > best!.dictations { best = hour }
        }
        return best
    }

    /// Eight three-hour bands covering the whole day.
    var timeBands: [TimeBandUsage] {
        stride(from: 0, to: 24, by: 3).map { start in
            let slice = hours[start..<(start + 3)]
            var totals = UsageTotals.zero
            var busiest: HourUsage?
            for hour in slice {
                totals.dictations += hour.dictations
                totals.seconds += hour.seconds
                totals.words += hour.words
                if hour.dictations > 0, busiest == nil || hour.dictations > busiest!.dictations {
                    busiest = hour
                }
            }
            return TimeBandUsage(
                startHour: start,
                endHour: start + 3,
                dictations: totals.dictations,
                seconds: totals.seconds,
                words: totals.words,
                busiestHour: busiest?.hour
            )
        }
    }

    /// Consecutive active days ending today.
    ///
    /// Matches the behaviour the app already shipped: a streak that has not
    /// been extended today reads as zero.
    func currentStreak(asOf now: Date = .now) -> Int {
        let active = Set(days.map(\.day))
        var day = calendar.startOfDay(for: now)
        var count = 0
        while active.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Longest run of consecutive active days anywhere in history.
    var longestStreak: Int {
        guard !days.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for index in days.indices.dropFirst() {
            let previous = days[index - 1].day
            let current = days[index].day
            if calendar.dateComponents([.day], from: previous, to: current).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
        }
        return best
    }

    /// Rolls `days` up into calendar buckets.
    ///
    /// Derived from `days` rather than from the entries, which is exact: a
    /// local day never straddles a week, month or year boundary. Only buckets
    /// that contain usage appear.
    func buckets(_ granularity: UsageGranularity) -> [PeriodUsage] {
        guard granularity != .daily else {
            return days.map {
                PeriodUsage(
                    start: $0.day,
                    granularity: .daily,
                    dictations: $0.dictations,
                    seconds: $0.seconds,
                    words: $0.words
                )
            }
        }

        var starts: [Date] = []
        var totals: [Date: UsageTotals] = [:]

        for day in days {
            // `dateInterval(of:for:)` only returns nil for calendars where the
            // unit is undefined; falling back to the day keeps the entry in
            // the result rather than dropping usage on the floor.
            let start = calendar.dateInterval(of: granularity.component, for: day.day)?.start ?? day.day
            if totals[start] == nil { starts.append(start) }
            totals[start, default: .zero].dictations += day.dictations
            totals[start, default: .zero].seconds += day.seconds
            totals[start, default: .zero].words += day.words
        }

        return starts.map { start in
            let total = totals[start] ?? .zero
            return PeriodUsage(
                start: start,
                granularity: granularity,
                dictations: total.dictations,
                seconds: total.seconds,
                words: total.words
            )
        }
    }

    /// Every day in `interval`, zero-filled.
    ///
    /// The interval is treated as half-open (`start ..< end`), matching what
    /// `Calendar.dateInterval(of:for:)` returns for a month or a year.
    func dailySeries(in interval: DateInterval) -> [DayUsage] {
        let lookup = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
        var result: [DayUsage] = []
        var cursor = calendar.startOfDay(for: interval.start)

        while cursor < interval.end {
            result.append(
                lookup[cursor] ?? DayUsage(day: cursor, dictations: 0, seconds: 0, words: 0, characters: 0)
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Builds the week-per-column activity grid for `interval` (half-open).
    ///
    /// The intensity scale comes from the whole dataset, not just the window,
    /// so switching months does not silently re-scale the colours underneath
    /// the reader.
    func activityCalendar(in interval: DateInterval) -> ActivityCalendar {
        let series = dailySeries(in: interval)
        let scale = ActivityScale.quartiles(of: days.map(\.dictations))

        guard let firstDay = series.first?.day, let lastDay = series.last?.day else {
            return ActivityCalendar(weeks: [], monthLabels: [], scale: scale, interval: interval)
        }

        let lookup = Dictionary(uniqueKeysWithValues: series.map { ($0.day, $0) })
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay

        var weeks: [ActivityWeek] = []
        var monthLabels: [ActivityMonthLabel] = []
        var lastLabelledMonth: Date?
        var cursor = gridStart

        while cursor <= lastDay {
            var cells: [ActivityCell] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor) else { break }
                let inRange = day >= firstDay && day <= lastDay
                let usage = inRange ? lookup[day] : nil
                cells.append(
                    ActivityCell(
                        day: day,
                        dictations: usage?.dictations ?? 0,
                        seconds: usage?.seconds ?? 0,
                        words: usage?.words ?? 0,
                        level: inRange ? scale.level(for: usage?.dictations ?? 0) : .none,
                        isInRange: inRange
                    )
                )
            }

            // Label a column with the month its first in-range day belongs to,
            // the first time that month appears.
            if let firstInRange = cells.first(where: \.isInRange),
               let month = calendar.dateInterval(of: .month, for: firstInRange.day)?.start,
               month != lastLabelledMonth {
                monthLabels.append(ActivityMonthLabel(weekIndex: weeks.count, month: month))
                lastLabelledMonth = month
            }

            weeks.append(ActivityWeek(start: cursor, cells: cells))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        return ActivityCalendar(
            weeks: weeks,
            monthLabels: monthLabels,
            scale: scale,
            interval: interval
        )
    }
}
