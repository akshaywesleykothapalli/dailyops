import Foundation

/// Turns raw `DictationEntry` records into `UsageStatistics`.
///
/// This is the only place history is summed. Views and the view model consume
/// the result; nothing recomputes an aggregate inside `body`.
///
/// The whole pass is a single traversal of the entries plus one sort of the
/// days and one of the apps, so it stays cheap even for a long history.
///
/// Synchronous and side-effect free: same entries plus same calendar always
/// give the same numbers, which is what makes the aggregation testable.
enum UsageStatisticsService {

    /// Aggregates dictation entries only; command feedback is not dictated text.
    ///
    /// Entries may arrive in any order — `@Query` delivers them newest-first,
    /// but nothing here depends on that.
    static func statistics(
        for entries: [DictationEntry],
        calendar: Calendar = .current
    ) -> UsageStatistics {
        guard !entries.isEmpty else { return .empty(calendar: calendar) }

        var overall = UsageTotals.zero
        var timedDictations = 0
        var dayTotals: [Date: UsageTotals] = [:]
        var hourTotals = [UsageTotals](repeating: .zero, count: 24)
        var appTotals: [String: UsageTotals] = [:]

        for entry in entries where !entry.isCommand {
            let words = wordCount(of: entry.cleaned)
            let characters = entry.cleaned.count
            // Durations are never negative in practice, but a corrupt record
            // must not be allowed to subtract from the totals.
            let seconds = max(entry.duration, 0)

            overall.add(seconds: seconds, words: words, characters: characters)
            if seconds > 0 { timedDictations += 1 }

            let day = calendar.startOfDay(for: entry.date)
            dayTotals[day, default: .zero].add(seconds: seconds, words: words, characters: characters)

            let hour = calendar.component(.hour, from: entry.date)
            if hourTotals.indices.contains(hour) {
                hourTotals[hour].add(seconds: seconds, words: words, characters: characters)
            }

            // A blank app name carries no information, so it is counted in the
            // totals but left out of the per-app breakdown rather than shown
            // as a nameless row.
            let appName = entry.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !appName.isEmpty {
                appTotals[appName, default: .zero].add(seconds: seconds, words: words, characters: characters)
            }
        }

        let days = dayTotals.keys.sorted().map { day in
            let total = dayTotals[day] ?? .zero
            return DayUsage(
                day: day,
                dictations: total.dictations,
                seconds: total.seconds,
                words: total.words,
                characters: total.characters
            )
        }

        let hours = hourTotals.indices.map { hour in
            HourUsage(
                hour: hour,
                dictations: hourTotals[hour].dictations,
                seconds: hourTotals[hour].seconds,
                words: hourTotals[hour].words
            )
        }

        // Most words first; ties fall back to dictation count and then to the
        // name, so the order never shuffles between two identical runs.
        let apps = appTotals
            .map { name, total in
                AppUsage(
                    name: name,
                    dictations: total.dictations,
                    words: total.words,
                    seconds: total.seconds
                )
            }
            .sorted { lhs, rhs in
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                if lhs.dictations != rhs.dictations { return lhs.dictations > rhs.dictations }
                return lhs.name < rhs.name
            }

        return UsageStatistics(
            totalDictations: overall.dictations,
            totalSeconds: overall.seconds,
            totalWords: overall.words,
            totalCharacters: overall.characters,
            timedDictations: timedDictations,
            days: days,
            hours: hours,
            apps: apps,
            calendar: calendar
        )
    }

    /// Aggregates only the entries inside `interval`, treated as half-open
    /// (`start ..< end`).
    ///
    /// Half-open matches what `Calendar.dateInterval(of:for:)` returns, so
    /// scoping to "September" cannot double-count an entry that lands exactly
    /// on 1 October at 00:00:00.
    static func statistics(
        for entries: [DictationEntry],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> UsageStatistics {
        statistics(
            for: entries.filter { $0.date >= interval.start && $0.date < interval.end },
            calendar: calendar
        )
    }

    /// Words in a transcript.
    ///
    /// Splits on any whitespace rather than on the space character alone, so
    /// newlines and runs of spaces do not inflate or collapse the count.
    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
