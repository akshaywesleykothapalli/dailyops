import Foundation

/// One local day of dictations, with every string the list needs already
/// rendered.
///
/// Grouping and formatting happen once per history or search change, so
/// nothing on the scroll path allocates a formatter, sorts, or builds a
/// dictionary.
struct HistorySection: Identifiable {
    /// Start of the local day these entries belong to. Doubles as the identity
    /// SwiftUI uses to keep sections — and their pinned headers — stable.
    let day: Date
    /// Pre-rendered header text: "TODAY", "YESTERDAY", or "SEP 9, 2026".
    let title: String
    let rows: [HistoryRow]

    var id: Date { day }

    var totalWords: Int {
        rows.reduce(0) { $0 + UsageStatisticsService.wordCount(of: $1.entry.cleaned) }
    }

    var formattedWordCount: String {
        let count = totalWords
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK words", k)
        } else {
            return "\(count) \(count == 1 ? "word" : "words")"
        }
    }
}

/// A single dictation plus its pre-rendered timestamp.
struct HistoryRow: Identifiable {
    let entry: DictationEntry
    let time: String

    var id: DictationEntry.ID { entry.id }
}

/// Pure, deterministic grouping for the dictation history list.
///
/// Deliberately outside `HistoryView`: the view calls this once per data
/// change and hands the result down as plain values, and the logic can be
/// unit tested without rendering anything.
enum HistoryGrouping {
    /// Reused rather than rebuilt per row. Constructing a format style — and
    /// the `Calendar.current` lookups behind `isDateInToday` — used to happen
    /// once per section *per body pass* on the old scroll path.
    ///
    /// Both styles are re-pointed at the caller's calendar before use, so the
    /// day a row is *filed under* and the day/time it *prints* can never
    /// disagree. In the app both are `.current`; in tests they are a fixed
    /// zone, which is the only way the rendered strings are assertable.
    private static let dayStyle = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
    private static let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)

    private static func styles(for calendar: Calendar) -> (day: Date.FormatStyle, time: Date.FormatStyle) {
        var day = dayStyle
        day.calendar = calendar
        day.timeZone = calendar.timeZone

        var time = timeStyle
        time.calendar = calendar
        time.timeZone = calendar.timeZone

        return (day, time)
    }

    /// Splits `entries` into day sections, optionally filtered by `search`.
    ///
    /// Single pass, no sorting: sections and rows keep the order the entries
    /// arrive in, which for the caller's `@Query(order: .reverse)` is already
    /// newest-first. The day dictionary guards that assumption rather than
    /// relying on it — out-of-order input still yields one section per day.
    ///
    /// `calendar` and `now` are injectable so day bucketing and the
    /// TODAY/YESTERDAY titles are testable without depending on the host's
    /// clock or timezone.
    static func sections(
        from entries: [DictationEntry],
        matching search: String = "",
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [HistorySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        // Built once per call, not once per row.
        let styles = styles(for: calendar)

        var days: [Date] = []
        var rowsByDay: [Date: [HistoryRow]] = [:]

        for entry in entries {
            guard matches(entry, search: search) else { continue }
            let day = calendar.startOfDay(for: entry.date)
            if rowsByDay[day] == nil { days.append(day) }
            rowsByDay[day, default: []].append(
                HistoryRow(entry: entry, time: entry.date.formatted(styles.time))
            )
        }

        return days.map { day in
            HistorySection(
                day: day,
                title: title(for: day, today: today, yesterday: yesterday, style: styles.day),
                rows: rowsByDay[day] ?? []
            )
        }
    }

    private static func matches(_ entry: DictationEntry, search: String) -> Bool {
        guard !search.isEmpty else { return true }
        return entry.cleaned.localizedCaseInsensitiveContains(search)
            || entry.raw.localizedCaseInsensitiveContains(search)
    }

    private static func title(
        for day: Date,
        today: Date,
        yesterday: Date?,
        style: Date.FormatStyle
    ) -> String {
        if day == today { return "TODAY" }
        if let yesterday, day == yesterday { return "YESTERDAY" }
        return day.formatted(style).uppercased()
    }
}
