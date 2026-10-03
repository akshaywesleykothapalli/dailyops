import XCTest
@testable import DailyOps

/// Grouping is pure, so these tests never touch SwiftData: `DictationEntry`
/// instances are constructed but never inserted into a context. Nothing here
/// reads `.id`/`persistentModelID` — only `date`, `raw` and `cleaned`.
///
/// Calendar and `now` are pinned to UTC and to fixed instants so day
/// bucketing, TODAY/YESTERDAY naming and month/year boundaries are
/// deterministic regardless of the host's clock or timezone.
final class HistoryGroupingTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)!
    }

    private func entry(
        at date: Date,
        raw: String = "raw text",
        cleaned: String = "cleaned text"
    ) -> DictationEntry {
        DictationEntry(date: date, raw: raw, cleaned: cleaned, duration: 1, appName: "TestApp")
    }

    private func sections(
        _ entries: [DictationEntry],
        search: String = "",
        now: Date
    ) -> [HistorySection] {
        HistoryGrouping.sections(from: entries, matching: search, calendar: utc, now: now)
    }

    // MARK: - Shape

    func testEmptyHistoryProducesNoSections() {
        let result = sections([], now: date(2026, 9, 10))

        XCTAssertTrue(result.isEmpty)
    }

    func testSingleEntryProducesOneSectionWithOneRow() {
        let result = sections([entry(at: date(2026, 9, 10, 9, 30))], now: date(2026, 9, 10))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].rows.count, 1)
    }

    func testEntriesOnTheSameDayShareOneSection() {
        let day = [
            entry(at: date(2026, 9, 10, 17, 0)),
            entry(at: date(2026, 9, 10, 12, 0)),
            entry(at: date(2026, 9, 10, 8, 0))
        ]

        let result = sections(day, now: date(2026, 9, 10))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].rows.count, 3)
    }

    func testDifferentDaysProduceSeparateSectionsInInputOrder() {
        let entries = [
            entry(at: date(2026, 9, 10)),
            entry(at: date(2026, 9, 9)),
            entry(at: date(2026, 9, 8))
        ]

        let result = sections(entries, now: date(2026, 9, 10))

        XCTAssertEqual(result.map(\.day), [
            date(2026, 9, 10, 0, 0),
            date(2026, 9, 9, 0, 0),
            date(2026, 9, 8, 0, 0)
        ])
    }

    func testSectionDayIsStartOfDay() {
        let result = sections([entry(at: date(2026, 9, 10, 23, 59))], now: date(2026, 9, 10))

        XCTAssertEqual(result[0].day, date(2026, 9, 10, 0, 0))
        XCTAssertEqual(result[0].id, result[0].day, "Section identity is the day")
    }

    func testRowOrderWithinASectionFollowsInputOrder() {
        let newest = entry(at: date(2026, 9, 10, 18, 0), cleaned: "newest")
        let oldest = entry(at: date(2026, 9, 10, 6, 0), cleaned: "oldest")

        let result = sections([newest, oldest], now: date(2026, 9, 10))

        XCTAssertEqual(result[0].rows.map(\.entry.cleaned), ["newest", "oldest"])
    }

    /// `@Query` delivers entries newest-first, but grouping must not silently
    /// fragment a day if that ever stops holding.
    func testOutOfOrderInputStillYieldsOneSectionPerDay() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0)),
            entry(at: date(2026, 9, 9, 9, 0)),
            entry(at: date(2026, 9, 10, 21, 0)),
            entry(at: date(2026, 9, 9, 21, 0))
        ]

        let result = sections(entries, now: date(2026, 9, 10))

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.rows.count), [2, 2])
    }

    // MARK: - Day boundaries

    func testMidnightBoundarySplitsDays() {
        let entries = [
            entry(at: date(2026, 9, 10, 0, 0)),
            entry(at: date(2026, 9, 9, 23, 59))
        ]

        let result = sections(entries, now: date(2026, 9, 10))

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].day, date(2026, 9, 10, 0, 0))
        XCTAssertEqual(result[1].day, date(2026, 9, 9, 0, 0))
    }

    /// The same instant belongs to different local days depending on the
    /// timezone — grouping must follow the supplied calendar, not UTC.
    func testDayBucketingFollowsTheSuppliedCalendarTimeZone() {
        let instant = date(2026, 9, 10, 2, 0)  // 02:00 UTC

        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!  // UTC-10

        let utcResult = HistoryGrouping.sections(
            from: [entry(at: instant)],
            calendar: utc,
            now: date(2026, 9, 10)
        )
        let honoluluResult = HistoryGrouping.sections(
            from: [entry(at: instant)],
            calendar: honolulu,
            now: date(2026, 9, 10)
        )

        XCTAssertNotEqual(
            utcResult[0].day,
            honoluluResult[0].day,
            "02:00 UTC on Sep 10 is 16:00 on Sep 9 in Honolulu"
        )
    }

    // MARK: - Titles

    func testTodayIsTitledToday() {
        let result = sections([entry(at: date(2026, 9, 10, 8, 0))], now: date(2026, 9, 10, 20, 0))

        XCTAssertEqual(result[0].title, "TODAY")
    }

    func testYesterdayIsTitledYesterday() {
        let result = sections([entry(at: date(2026, 9, 9, 8, 0))], now: date(2026, 9, 10, 20, 0))

        XCTAssertEqual(result[0].title, "YESTERDAY")
    }

    func testOlderDaysUseAFormattedDate() {
        let result = sections([entry(at: date(2026, 9, 8))], now: date(2026, 9, 10))

        let title = result[0].title
        XCTAssertNotEqual(title, "TODAY")
        XCTAssertNotEqual(title, "YESTERDAY")
        XCTAssertFalse(title.isEmpty)
        XCTAssertEqual(title, title.uppercased(), "Header titles are uppercased")
        XCTAssertTrue(title.contains("8"), "Formatted title should carry the day number: \(title)")
        XCTAssertTrue(title.contains("2026"), "Formatted title should carry the year: \(title)")
    }

    func testYesterdayAcrossAMonthBoundary() {
        let result = sections([entry(at: date(2026, 8, 31, 22, 0))], now: date(2026, 9, 1, 9, 0))

        XCTAssertEqual(result[0].title, "YESTERDAY")
    }

    func testYesterdayAcrossAYearBoundary() {
        let result = sections([entry(at: date(2025, 12, 31, 22, 0))], now: date(2026, 1, 1, 9, 0))

        XCTAssertEqual(result[0].title, "YESTERDAY")
    }

    func testLeapDayIsYesterdayOnMarchFirst() {
        let result = sections([entry(at: date(2024, 2, 29, 14, 0))], now: date(2024, 3, 1, 9, 0))

        XCTAssertEqual(result[0].title, "YESTERDAY")
    }

    func testFutureDayIsNotTitledTodayOrYesterday() {
        let result = sections([entry(at: date(2026, 9, 11))], now: date(2026, 9, 10))

        XCTAssertNotEqual(result[0].title, "TODAY")
        XCTAssertNotEqual(result[0].title, "YESTERDAY")
    }

    // MARK: - Row formatting

    func testRowTimeIsPreRendered() {
        let result = sections([entry(at: date(2026, 9, 10, 14, 35))], now: date(2026, 9, 10))

        let time = result[0].rows[0].time
        XCTAssertFalse(time.isEmpty, "Rows carry a formatted time so the view never formats one")
        XCTAssertTrue(time.contains("35"), "Formatted time should carry the minutes: \(time)")
    }

    /// The day a row is filed under and the time it prints must come from the
    /// same calendar — otherwise a row can sit under "SEP 10" showing a time
    /// that belongs to Sep 9.
    func testRowTimeFollowsTheSuppliedCalendarTimeZone() {
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!  // UTC-10
        let instant = date(2026, 9, 10, 14, 35)  // 04:35 in Honolulu

        let result = HistoryGrouping.sections(
            from: [entry(at: instant)],
            calendar: honolulu,
            now: date(2026, 9, 10)
        )

        let time = result[0].rows[0].time
        XCTAssertTrue(time.contains("4"), "14:35 UTC is 4:35 AM in Honolulu, got: \(time)")
        XCTAssertTrue(time.localizedCaseInsensitiveContains("AM"), "Expected a morning time: \(time)")
    }

    func testSectionTitleFollowsTheSuppliedCalendarTimeZone() {
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let instant = date(2026, 9, 10, 2, 0)  // Sep 9, 16:00 in Honolulu

        let result = HistoryGrouping.sections(
            from: [entry(at: instant)],
            calendar: honolulu,
            now: date(2026, 9, 12)
        )

        XCTAssertTrue(
            result[0].title.contains("9"),
            "The printed date must match the day the row is filed under, got: \(result[0].title)"
        )
    }

    func testRowRetainsItsEntry() {
        let subject = entry(at: date(2026, 9, 10), cleaned: "hello world")

        let result = sections([subject], now: date(2026, 9, 10))

        XCTAssertEqual(result[0].rows[0].entry.cleaned, "hello world")
    }

    // MARK: - Search

    func testEmptySearchReturnsEverything() {
        let entries = (0..<5).map { entry(at: date(2026, 9, 10, 9 + $0, 0)) }

        let result = sections(entries, search: "", now: date(2026, 9, 10))

        XCTAssertEqual(result[0].rows.count, 5)
    }

    func testSearchMatchesCleanedText() {
        let entries = [
            entry(at: date(2026, 9, 10, 10, 0), raw: "aaa", cleaned: "grocery list"),
            entry(at: date(2026, 9, 10, 9, 0), raw: "bbb", cleaned: "meeting notes")
        ]

        let result = sections(entries, search: "grocery", now: date(2026, 9, 10))

        XCTAssertEqual(result[0].rows.count, 1)
        XCTAssertEqual(result[0].rows[0].entry.cleaned, "grocery list")
    }

    func testSearchMatchesRawText() {
        let entries = [
            entry(at: date(2026, 9, 10, 10, 0), raw: "umm grocery", cleaned: "shopping"),
            entry(at: date(2026, 9, 10, 9, 0), raw: "bbb", cleaned: "meeting notes")
        ]

        let result = sections(entries, search: "grocery", now: date(2026, 9, 10))

        XCTAssertEqual(result[0].rows.count, 1)
        XCTAssertEqual(result[0].rows[0].entry.cleaned, "shopping")
    }

    func testSearchIsCaseInsensitive() {
        let entries = [entry(at: date(2026, 9, 10), raw: "x", cleaned: "Grocery List")]

        let result = sections(entries, search: "GROCERY", now: date(2026, 9, 10))

        XCTAssertEqual(result[0].rows.count, 1)
    }

    func testSearchDropsSectionsThatBecomeEmpty() {
        let entries = [
            entry(at: date(2026, 9, 10), raw: "x", cleaned: "grocery list"),
            entry(at: date(2026, 9, 9), raw: "y", cleaned: "meeting notes")
        ]

        let result = sections(entries, search: "grocery", now: date(2026, 9, 10))

        XCTAssertEqual(result.count, 1, "The day with no match must not appear as an empty section")
        XCTAssertEqual(result[0].day, date(2026, 9, 10, 0, 0))
    }

    func testSearchWithNoMatchesReturnsNoSections() {
        let entries = [entry(at: date(2026, 9, 10), raw: "x", cleaned: "grocery list")]

        let result = sections(entries, search: "zzzz", now: date(2026, 9, 10))

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Volume

    func testTenEntriesAcrossTenDays() {
        assertGrouping(entryCount: 10, perDay: 1, expectedSections: 10)
    }

    func testFiftyEntriesAcrossTenDays() {
        assertGrouping(entryCount: 50, perDay: 5, expectedSections: 10)
    }

    func testOneHundredTwentyEntriesAcrossTwelveDays() {
        assertGrouping(entryCount: 120, perDay: 10, expectedSections: 12)
    }

    func testEntriesSpanningMultipleMonthsAndYears() {
        let entries = [
            entry(at: date(2026, 1, 5)),
            entry(at: date(2025, 12, 20)),
            entry(at: date(2025, 6, 1)),
            entry(at: date(2024, 2, 29))
        ]

        let result = sections(entries, now: date(2026, 9, 10))

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map(\.rows.count), [1, 1, 1, 1])
    }

    // MARK: - Helpers

    private func assertGrouping(
        entryCount: Int,
        perDay: Int,
        expectedSections: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let now = date(2026, 9, 10)
        var entries: [DictationEntry] = []
        for index in 0..<entryCount {
            let dayOffset = index / perDay
            let hour = 23 - (index % perDay)
            entries.append(entry(at: date(2026, 9, 10 - dayOffset, hour, 0)))
        }

        let result = sections(entries, now: now)

        XCTAssertEqual(result.count, expectedSections, file: file, line: line)
        XCTAssertEqual(
            result.reduce(0) { $0 + $1.rows.count },
            entryCount,
            "Every entry must land in exactly one section",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(result.map(\.day)).count,
            expectedSections,
            "Section days must be unique",
            file: file,
            line: line
        )
    }
}
