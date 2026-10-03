import XCTest
@testable import DailyOps

/// Aggregation is pure, so these tests never touch SwiftData: `DictationEntry`
/// instances are constructed but never inserted into a context, and nothing
/// here reads `.id`/`persistentModelID` — only `date`, `cleaned`, `duration`
/// and `appName`.
///
/// Every calendar is pinned — identifier, timezone, locale and `firstWeekday`
/// — so day bucketing, hour bucketing, week boundaries, month/year rollups and
/// streaks are deterministic regardless of the host's clock, timezone or
/// region settings.
final class UsageStatisticsTests: XCTestCase {

    // MARK: - Fixtures

    private func makeCalendar(
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!,
        firstWeekday: Int = 1
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private var utc: Calendar { makeCalendar() }

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

    /// Default fixture: three words, thirteen characters, ten seconds.
    private func entry(
        at date: Date,
        cleaned: String = "one two three",
        duration: TimeInterval = 10,
        appName: String = "TestApp"
    ) -> DictationEntry {
        DictationEntry(date: date, raw: cleaned, cleaned: cleaned, duration: duration, appName: appName)
    }

    private func stats(_ entries: [DictationEntry], calendar: Calendar? = nil) -> UsageStatistics {
        UsageStatisticsService.statistics(for: entries, calendar: calendar ?? utc)
    }

    private func month(_ year: Int, _ month: Int, calendar: Calendar? = nil) -> DateInterval {
        let calendar = calendar ?? utc
        return calendar.dateInterval(of: .month, for: date(year, month, 15))!
    }

    // MARK: - Empty history

    func testEmptyHistoryProducesZeroedStatistics() {
        let result = stats([])

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.totalDictations, 0)
        XCTAssertEqual(result.totalSeconds, 0)
        XCTAssertEqual(result.totalWords, 0)
        XCTAssertEqual(result.totalCharacters, 0)
        XCTAssertEqual(result.timedDictations, 0)
        XCTAssertEqual(result.activeDays, 0)
        XCTAssertTrue(result.days.isEmpty)
        XCTAssertTrue(result.apps.isEmpty)
    }

    func testEmptyHistoryStillHasTwentyFourHourBuckets() {
        let result = stats([])

        XCTAssertEqual(result.hours.count, 24)
        XCTAssertEqual(result.hours.map(\.hour), Array(0..<24))
        XCTAssertTrue(result.hours.allSatisfy { $0.dictations == 0 })
    }

    func testEmptyHistoryHasNoBusiestDayOrHour() {
        let result = stats([])

        XCTAssertNil(result.busiestDay)
        XCTAssertNil(result.busiestHour)
        XCTAssertNil(result.firstDay)
        XCTAssertNil(result.lastDay)
    }

    func testEmptyHistoryAveragesAreZeroRatherThanNaN() {
        let result = stats([])

        XCTAssertEqual(result.averageSeconds, 0)
        XCTAssertEqual(result.averageWords, 0)
        XCTAssertEqual(result.wordsPerMinute, 0)
    }

    func testEmptyHistoryHasNoStreaks() {
        let result = stats([])

        XCTAssertEqual(result.longestStreak, 0)
        XCTAssertEqual(result.currentStreak(asOf: date(2026, 9, 10)), 0)
    }

    // MARK: - Command history is not dictation

    func testCommandHistoryDoesNotInflateDictationStatistics() {
        let dictation = entry(at: date(2026, 9, 10, 14), appName: "Notes")
        // Legacy entries have no stored discriminator and remain dictations.
        dictation.isCommandStored = nil
        let command = DictationEntry(
            date: date(2026, 9, 11, 18),
            raw: "Open Safari",
            cleaned: "Opened Safari",
            duration: 0,
            appName: "Safari",
            isCommand: true,
            commandSummary: "Opened Safari"
        )
        let result = stats([dictation, command])

        XCTAssertEqual(result, stats([dictation]))
        XCTAssertEqual(result.totalDictations, 1)
        XCTAssertEqual(result.totalWords, 3)
        XCTAssertEqual(result.activeDays, 1)
        XCTAssertEqual(result.apps.map(\.name), ["Notes"])
        XCTAssertEqual(result.hours[18].dictations, 0)
        XCTAssertEqual(
            UsageStatisticsService.statistics(for: [dictation, command], in: month(2026, 9), calendar: utc),
            stats([dictation])
        )
    }

    func testCommandOnlyHistoryProducesEmptyDictationInsights() {
        let command = DictationEntry(
            date: date(2026, 9, 10), raw: "Open Safari", cleaned: "Opened Safari",
            duration: 0, appName: "Safari", isCommand: true
        )
        XCTAssertEqual(stats([command]), stats([]))
    }

    // MARK: - Single entry

    func testSingleEntryTotals() {
        let result = stats([entry(at: date(2026, 9, 10, 14, 0), duration: 30)])

        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.totalDictations, 1)
        XCTAssertEqual(result.totalSeconds, 30)
        XCTAssertEqual(result.totalWords, 3)
        XCTAssertEqual(result.totalCharacters, 13)
        XCTAssertEqual(result.timedDictations, 1)
        XCTAssertEqual(result.activeDays, 1)
    }

    func testSingleEntryLandsInItsLocalDayAndHour() {
        let result = stats([entry(at: date(2026, 9, 10, 14, 35))])

        XCTAssertEqual(result.days.map(\.day), [date(2026, 9, 10, 0, 0)])
        XCTAssertEqual(result.busiestHour?.hour, 14)
        XCTAssertEqual(result.hours[14].dictations, 1)
    }

    // MARK: - Word and character counting

    func testWordCountSplitsOnAnyWhitespace() {
        XCTAssertEqual(UsageStatisticsService.wordCount(of: "hello  world\nagain"), 3)
    }

    func testWordCountIgnoresLeadingAndTrailingWhitespace() {
        XCTAssertEqual(UsageStatisticsService.wordCount(of: "  hello world  "), 2)
    }

    func testWordCountOfEmptyAndWhitespaceOnlyTextIsZero() {
        XCTAssertEqual(UsageStatisticsService.wordCount(of: ""), 0)
        XCTAssertEqual(UsageStatisticsService.wordCount(of: "   \n\t "), 0)
    }

    func testTotalsUseTheCleanedTextForWordsAndCharacters() {
        let subject = DictationEntry(
            date: date(2026, 9, 10),
            raw: "um one um two um three um four",
            cleaned: "one  two\nthree",
            duration: 5,
            appName: "TestApp"
        )

        let result = stats([subject])

        XCTAssertEqual(result.totalWords, 3, "Words come from the cleaned text, not the raw hypothesis")
        XCTAssertEqual(result.totalCharacters, 14)
    }

    func testBlankTranscriptContributesADictationButNoWords() {
        let result = stats([entry(at: date(2026, 9, 10), cleaned: "")])

        XCTAssertEqual(result.totalDictations, 1)
        XCTAssertEqual(result.totalWords, 0)
        XCTAssertEqual(result.totalCharacters, 0)
    }

    // MARK: - Durations

    func testZeroDurationEntriesCountAsDictationsButNotAsTimed() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), duration: 20),
            entry(at: date(2026, 9, 10, 10, 0), duration: 0),
            entry(at: date(2026, 9, 10, 11, 0), duration: 0)
        ]

        let result = stats(entries)

        XCTAssertEqual(result.totalDictations, 3)
        XCTAssertEqual(result.timedDictations, 1)
        XCTAssertEqual(result.totalSeconds, 20)
    }

    /// Command confirmations, Writing Tools polishes and imported command history
    /// imports are all stored with `duration == 0`. Dividing speaking time by
    /// every entry would understate it, so averages use the timed entries.
    func testAverageDurationExcludesZeroDurationEntries() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), duration: 20),
            entry(at: date(2026, 9, 10, 10, 0), duration: 40),
            entry(at: date(2026, 9, 10, 11, 0), duration: 0)
        ]

        let result = stats(entries)

        XCTAssertEqual(result.averageSeconds, 30, accuracy: 0.0001)
    }

    func testAverageDurationIsZeroWhenNothingWasTimed() {
        let result = stats([entry(at: date(2026, 9, 10), duration: 0)])

        XCTAssertEqual(result.timedDictations, 0)
        XCTAssertEqual(result.averageSeconds, 0)
    }

    func testAverageWordsCountsEveryEntry() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), cleaned: "one two"),
            entry(at: date(2026, 9, 10, 10, 0), cleaned: "one two three four")
        ]

        let result = stats(entries)

        XCTAssertEqual(result.averageWords, 3, accuracy: 0.0001)
    }

    func testWordsPerMinuteUsesTotalSpeakingTime() {
        // 120 words over 120 seconds is 60 wpm.
        let text = Array(repeating: "word", count: 120).joined(separator: " ")
        let result = stats([entry(at: date(2026, 9, 10), cleaned: text, duration: 120)])

        XCTAssertEqual(result.wordsPerMinute, 60, accuracy: 0.0001)
    }

    func testWordsPerMinuteIsZeroWithoutSpeakingTime() {
        let result = stats([entry(at: date(2026, 9, 10), duration: 0)])

        XCTAssertEqual(result.wordsPerMinute, 0)
    }

    func testNegativeDurationsAreClampedRatherThanSubtracted() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), duration: 30),
            entry(at: date(2026, 9, 10, 10, 0), duration: -10)
        ]

        let result = stats(entries)

        XCTAssertEqual(result.totalSeconds, 30)
        XCTAssertEqual(result.timedDictations, 1)
    }

    // MARK: - Day bucketing

    func testEntriesOnTheSameDayMergeIntoOneBucket() {
        let entries = [
            entry(at: date(2026, 9, 10, 8, 0), duration: 5),
            entry(at: date(2026, 9, 10, 13, 0), duration: 7),
            entry(at: date(2026, 9, 10, 23, 59), duration: 3)
        ]

        let result = stats(entries)

        XCTAssertEqual(result.days.count, 1)
        XCTAssertEqual(result.days[0].dictations, 3)
        XCTAssertEqual(result.days[0].seconds, 15)
        XCTAssertEqual(result.days[0].words, 9)
        XCTAssertEqual(result.days[0].characters, 39)
    }

    func testDaysAreAscendingRegardlessOfInputOrder() {
        // `@Query` delivers newest-first; the aggregate must still be ordered.
        let entries = [
            entry(at: date(2026, 9, 12)),
            entry(at: date(2026, 9, 8)),
            entry(at: date(2026, 9, 10))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.days.map(\.day), [
            date(2026, 9, 8, 0, 0),
            date(2026, 9, 10, 0, 0),
            date(2026, 9, 12, 0, 0)
        ])
        XCTAssertEqual(result.firstDay, date(2026, 9, 8, 0, 0))
        XCTAssertEqual(result.lastDay, date(2026, 9, 12, 0, 0))
    }

    func testMidnightBoundarySplitsDays() {
        let entries = [
            entry(at: date(2026, 9, 9, 23, 59)),
            entry(at: date(2026, 9, 10, 0, 0))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.activeDays, 2)
        XCTAssertEqual(result.days.map(\.dictations), [1, 1])
    }

    /// The same instant belongs to different local days depending on the
    /// timezone — bucketing must follow the supplied calendar, not UTC.
    func testDayBucketingFollowsTheSuppliedCalendarTimeZone() {
        let instant = date(2026, 9, 10, 2, 0)  // 16:00 on Sep 9 in Honolulu
        let honolulu = makeCalendar(timeZone: TimeZone(identifier: "Pacific/Honolulu")!)

        let utcDay = stats([entry(at: instant)]).days[0].day
        let honoluluDay = stats([entry(at: instant)], calendar: honolulu).days[0].day

        XCTAssertNotEqual(utcDay, honoluluDay)
        XCTAssertEqual(
            honolulu.dateComponents([.year, .month, .day], from: honoluluDay).day,
            9
        )
    }

    func testDaysSpanningMonthsAndYearsAreAllRetained() {
        let entries = [
            entry(at: date(2024, 2, 29)),
            entry(at: date(2025, 6, 1)),
            entry(at: date(2025, 12, 20)),
            entry(at: date(2026, 1, 5))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.activeDays, 4)
        XCTAssertEqual(result.firstDay, date(2024, 2, 29, 0, 0))
        XCTAssertEqual(result.lastDay, date(2026, 1, 5, 0, 0))
    }

    // MARK: - Hour bucketing

    func testHoursAlwaysCoverTheWholeDay() {
        let result = stats([entry(at: date(2026, 9, 10, 7, 0))])

        XCTAssertEqual(result.hours.count, 24)
        XCTAssertEqual(result.hours.map(\.hour), Array(0..<24))
    }

    func testHoursAccumulateAcrossDays() {
        let entries = [
            entry(at: date(2026, 9, 10, 21, 0), duration: 4),
            entry(at: date(2026, 9, 11, 21, 30), duration: 6),
            entry(at: date(2026, 9, 12, 9, 0), duration: 1)
        ]

        let result = stats(entries)

        XCTAssertEqual(result.hours[21].dictations, 2)
        XCTAssertEqual(result.hours[21].seconds, 10)
        XCTAssertEqual(result.hours[9].dictations, 1)
        XCTAssertEqual(result.hours[0].dictations, 0)
    }

    func testHourBucketingFollowsTheSuppliedCalendarTimeZone() {
        let instant = date(2026, 9, 10, 14, 0)  // 04:00 in Honolulu
        let honolulu = makeCalendar(timeZone: TimeZone(identifier: "Pacific/Honolulu")!)

        XCTAssertEqual(stats([entry(at: instant)]).busiestHour?.hour, 14)
        XCTAssertEqual(stats([entry(at: instant)], calendar: honolulu).busiestHour?.hour, 4)
    }

    // MARK: - App breakdown

    func testAppsAreOrderedByWordsDescending() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), cleaned: "a", appName: "Notes"),
            entry(at: date(2026, 9, 10, 10, 0), cleaned: "a b c d", appName: "Mail"),
            entry(at: date(2026, 9, 10, 11, 0), cleaned: "a b", appName: "Xcode")
        ]

        let result = stats(entries)

        XCTAssertEqual(result.apps.map(\.name), ["Mail", "Xcode", "Notes"])
        XCTAssertEqual(result.apps.map(\.words), [4, 2, 1])
    }

    func testAppUsageMergesRepeatedApps() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), cleaned: "a b", duration: 3, appName: "Mail"),
            entry(at: date(2026, 9, 11, 9, 0), cleaned: "c", duration: 4, appName: "Mail")
        ]

        let result = stats(entries)

        XCTAssertEqual(result.apps.count, 1)
        XCTAssertEqual(result.apps[0].dictations, 2)
        XCTAssertEqual(result.apps[0].words, 3)
        XCTAssertEqual(result.apps[0].seconds, 7)
    }

    /// A nameless row cannot honestly be attributed to an app, so it stays out
    /// of the breakdown — but it must still count towards the totals.
    func testBlankAppNamesAreExcludedFromTheBreakdownButCountedInTotals() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), cleaned: "a b", appName: "Mail"),
            entry(at: date(2026, 9, 10, 10, 0), cleaned: "c d", appName: ""),
            entry(at: date(2026, 9, 10, 11, 0), cleaned: "e f", appName: "   ")
        ]

        let result = stats(entries)

        XCTAssertEqual(result.apps.map(\.name), ["Mail"])
        XCTAssertEqual(result.totalDictations, 3)
        XCTAssertEqual(result.totalWords, 6)
    }

    func testAppOrderingIsStableForTiedWordCounts() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), cleaned: "a b", appName: "Zed"),
            entry(at: date(2026, 9, 10, 10, 0), cleaned: "c d", appName: "Mail")
        ]

        let result = stats(entries)

        XCTAssertEqual(result.apps.map(\.name), ["Mail", "Zed"], "Ties resolve alphabetically")
    }

    // MARK: - Busiest day and hour

    func testBusiestDayIsTheOneWithMostDictations() {
        let entries = [
            entry(at: date(2026, 9, 8, 9, 0)),
            entry(at: date(2026, 9, 9, 9, 0)),
            entry(at: date(2026, 9, 9, 10, 0)),
            entry(at: date(2026, 9, 9, 11, 0)),
            entry(at: date(2026, 9, 10, 9, 0))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.busiestDay?.day, date(2026, 9, 9, 0, 0))
        XCTAssertEqual(result.busiestDay?.dictations, 3)
    }

    func testBusiestDayTieResolvesToTheEarlierDay() {
        let entries = [
            entry(at: date(2026, 9, 8, 9, 0)),
            entry(at: date(2026, 9, 10, 9, 0))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.busiestDay?.day, date(2026, 9, 8, 0, 0))
    }

    func testBusiestHourTieResolvesToTheEarlierHour() {
        let entries = [
            entry(at: date(2026, 9, 10, 20, 0)),
            entry(at: date(2026, 9, 10, 7, 0))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.busiestHour?.hour, 7)
    }

    // MARK: - Streaks

    func testCurrentStreakCountsConsecutiveDaysEndingToday() {
        let entries = [
            entry(at: date(2026, 9, 8)),
            entry(at: date(2026, 9, 9)),
            entry(at: date(2026, 9, 10))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.currentStreak(asOf: date(2026, 9, 10, 22, 0)), 3)
    }

    /// Matches the behaviour the app already shipped: a streak that has not
    /// been extended today reads as zero.
    func testCurrentStreakIsZeroWhenTodayHasNoDictation() {
        let entries = [
            entry(at: date(2026, 9, 8)),
            entry(at: date(2026, 9, 9))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.currentStreak(asOf: date(2026, 9, 10, 9, 0)), 0)
    }

    func testCurrentStreakStopsAtAGap() {
        let entries = [
            entry(at: date(2026, 9, 5)),
            entry(at: date(2026, 9, 6)),
            // Sep 7 missing.
            entry(at: date(2026, 9, 9)),
            entry(at: date(2026, 9, 10))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.currentStreak(asOf: date(2026, 9, 10, 9, 0)), 2)
    }

    func testLongestStreakFindsTheBestRunAnywhereInHistory() {
        let entries = [
            entry(at: date(2026, 9, 1)),
            entry(at: date(2026, 9, 2)),
            entry(at: date(2026, 9, 3)),
            entry(at: date(2026, 9, 4)),
            // gap
            entry(at: date(2026, 9, 9)),
            entry(at: date(2026, 9, 10))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.longestStreak, 4)
    }

    func testLongestStreakOfASingleDayIsOne() {
        XCTAssertEqual(stats([entry(at: date(2026, 9, 10))]).longestStreak, 1)
    }

    func testStreakCrossesAMonthBoundary() {
        let entries = [
            entry(at: date(2026, 8, 30)),
            entry(at: date(2026, 8, 31)),
            entry(at: date(2026, 9, 1))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.longestStreak, 3)
        XCTAssertEqual(result.currentStreak(asOf: date(2026, 9, 1, 20, 0)), 3)
    }

    func testStreakCrossesAYearBoundary() {
        let entries = [
            entry(at: date(2025, 12, 31)),
            entry(at: date(2026, 1, 1))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.longestStreak, 2)
    }

    func testStreakCrossesTheLeapDay() {
        let entries = [
            entry(at: date(2024, 2, 28)),
            entry(at: date(2024, 2, 29)),
            entry(at: date(2024, 3, 1))
        ]

        let result = stats(entries)

        XCTAssertEqual(result.longestStreak, 3)
    }

    /// 2025 is not a leap year, so Feb 28 and Mar 1 are consecutive.
    func testNonLeapYearFebruaryRollsStraightIntoMarch() {
        let entries = [
            entry(at: date(2025, 2, 28)),
            entry(at: date(2025, 3, 1))
        ]

        XCTAssertEqual(stats(entries).longestStreak, 2)
    }

    // MARK: - Granularity buckets

    func testDailyBucketsMirrorTheDays() {
        let entries = [
            entry(at: date(2026, 9, 8), duration: 5),
            entry(at: date(2026, 9, 10), duration: 7)
        ]

        let result = stats(entries)
        let buckets = result.buckets(.daily)

        XCTAssertEqual(buckets.map(\.start), result.days.map(\.day))
        XCTAssertEqual(buckets.map(\.seconds), [5, 7])
        XCTAssertTrue(buckets.allSatisfy { $0.granularity == .daily })
    }

    func testMonthlyBucketsRollDaysUp() {
        let entries = [
            entry(at: date(2026, 8, 5), duration: 5),
            entry(at: date(2026, 8, 20), duration: 5),
            entry(at: date(2026, 9, 2), duration: 10)
        ]

        let buckets = stats(entries).buckets(.monthly)

        XCTAssertEqual(buckets.map(\.start), [date(2026, 8, 1, 0, 0), date(2026, 9, 1, 0, 0)])
        XCTAssertEqual(buckets.map(\.dictations), [2, 1])
        XCTAssertEqual(buckets.map(\.seconds), [10, 10])
    }

    func testYearlyBucketsRollMonthsUp() {
        let entries = [
            entry(at: date(2024, 2, 29)),
            entry(at: date(2025, 6, 1)),
            entry(at: date(2025, 12, 20)),
            entry(at: date(2026, 1, 5))
        ]

        let buckets = stats(entries).buckets(.yearly)

        XCTAssertEqual(buckets.map(\.start), [
            date(2024, 1, 1, 0, 0),
            date(2025, 1, 1, 0, 0),
            date(2026, 1, 1, 0, 0)
        ])
        XCTAssertEqual(buckets.map(\.dictations), [1, 2, 1])
    }

    func testBucketsAreAscending() {
        let entries = [
            entry(at: date(2026, 9, 2)),
            entry(at: date(2026, 7, 2)),
            entry(at: date(2026, 8, 2))
        ]

        let buckets = stats(entries).buckets(.monthly)

        XCTAssertEqual(buckets.map(\.start), buckets.map(\.start).sorted())
    }

    /// Sep 6 2026 is a Sunday and Sep 7 a Monday, so whether they share a week
    /// depends entirely on the calendar's `firstWeekday`.
    func testWeeklyBucketsRespectFirstWeekday() {
        let entries = [
            entry(at: date(2026, 9, 6)),
            entry(at: date(2026, 9, 7))
        ]

        let sundayFirst = stats(entries, calendar: makeCalendar(firstWeekday: 1)).buckets(.weekly)
        let mondayFirst = stats(entries, calendar: makeCalendar(firstWeekday: 2)).buckets(.weekly)

        XCTAssertEqual(sundayFirst.count, 1, "Sunday-first puts Sep 6 and Sep 7 in one week")
        XCTAssertEqual(sundayFirst[0].dictations, 2)
        XCTAssertEqual(mondayFirst.count, 2, "Monday-first starts a new week on Sep 7")
    }

    func testBucketTotalsAlwaysSumToTheOverallTotals() {
        let entries = (0..<40).map { index in
            entry(at: date(2026, 7 + index / 15, 1 + index % 15, 9, 0), duration: TimeInterval(index))
        }
        let result = stats(entries)

        for granularity in UsageGranularity.allCases {
            let buckets = result.buckets(granularity)
            XCTAssertEqual(
                buckets.reduce(0) { $0 + $1.dictations },
                result.totalDictations,
                "\(granularity) dictations must sum to the total"
            )
            XCTAssertEqual(
                buckets.reduce(0) { $0 + $1.words },
                result.totalWords,
                "\(granularity) words must sum to the total"
            )
            XCTAssertEqual(
                buckets.reduce(0) { $0 + $1.seconds },
                result.totalSeconds,
                accuracy: 0.0001,
                "\(granularity) seconds must sum to the total"
            )
        }
    }

    // MARK: - Scoped aggregation

    func testScopedStatisticsExcludeEntriesOutsideTheInterval() {
        let entries = [
            entry(at: date(2026, 8, 31, 23, 59)),
            entry(at: date(2026, 9, 15, 12, 0)),
            entry(at: date(2026, 10, 1, 0, 1))
        ]

        let result = UsageStatisticsService.statistics(
            for: entries,
            in: month(2026, 9),
            calendar: utc
        )

        XCTAssertEqual(result.totalDictations, 1)
        XCTAssertEqual(result.days.map(\.day), [date(2026, 9, 15, 0, 0)])
    }

    /// The interval is half-open, matching `Calendar.dateInterval(of:for:)`:
    /// the first instant is in, the last instant belongs to the next month.
    func testScopedStatisticsTreatTheIntervalAsHalfOpen() {
        let september = month(2026, 9)
        let entries = [
            entry(at: september.start),
            entry(at: september.end)
        ]

        let result = UsageStatisticsService.statistics(for: entries, in: september, calendar: utc)

        XCTAssertEqual(result.totalDictations, 1)
        XCTAssertEqual(result.days.map(\.day), [date(2026, 9, 1, 0, 0)])
    }

    func testScopedStatisticsOnAnEmptyWindowAreZeroed() {
        let result = UsageStatisticsService.statistics(
            for: [entry(at: date(2026, 9, 15))],
            in: month(2026, 3),
            calendar: utc
        )

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.hours.count, 24)
    }

    func testMonthlyScopesPartitionAYearWithoutOverlap() {
        let entries = (1...12).map { entry(at: date(2026, $0, 15)) }

        let scoped = (1...12).map { index in
            UsageStatisticsService.statistics(for: entries, in: month(2026, index), calendar: utc)
        }

        XCTAssertEqual(scoped.map(\.totalDictations), Array(repeating: 1, count: 12))
        XCTAssertEqual(scoped.reduce(0) { $0 + $1.totalDictations }, entries.count)
    }

    // MARK: - Daily series

    func testDailySeriesZeroFillsTheWholeMonth() {
        let entries = [
            entry(at: date(2026, 9, 1)),
            entry(at: date(2026, 9, 30))
        ]

        let series = stats(entries).dailySeries(in: month(2026, 9))

        XCTAssertEqual(series.count, 30)
        XCTAssertEqual(series.first?.day, date(2026, 9, 1, 0, 0))
        XCTAssertEqual(series.last?.day, date(2026, 9, 30, 0, 0))
        XCTAssertEqual(series.filter { $0.dictations > 0 }.count, 2)
        XCTAssertEqual(series[1].dictations, 0, "Sep 2 has no usage and must be zero-filled")
    }

    func testDailySeriesLengthFollowsTheMonthLength() {
        let result = stats([entry(at: date(2024, 2, 10))])

        XCTAssertEqual(result.dailySeries(in: month(2024, 2)).count, 29, "2024 is a leap year")
        XCTAssertEqual(result.dailySeries(in: month(2025, 2)).count, 28)
    }

    func testDailySeriesCarriesRealUsageForActiveDays() {
        let entries = [
            entry(at: date(2026, 9, 4, 9, 0), duration: 5),
            entry(at: date(2026, 9, 4, 10, 0), duration: 7)
        ]

        let series = stats(entries).dailySeries(in: month(2026, 9))
        let fourth = series.first { $0.day == date(2026, 9, 4, 0, 0) }

        XCTAssertEqual(fourth?.dictations, 2)
        XCTAssertEqual(fourth?.seconds, 12)
        XCTAssertEqual(fourth?.words, 6)
    }

    func testDailySeriesExcludesDaysOutsideTheWindow() {
        let entries = [
            entry(at: date(2026, 8, 31)),
            entry(at: date(2026, 9, 1))
        ]

        let series = stats(entries).dailySeries(in: month(2026, 9))

        XCTAssertEqual(series.reduce(0) { $0 + $1.dictations }, 1)
    }

    // MARK: - Time bands

    func testThereAreEightThreeHourBands() {
        let result = stats([entry(at: date(2026, 9, 10, 7, 0))])

        XCTAssertEqual(result.timeBands.count, 8)
        XCTAssertEqual(result.timeBands.map(\.startHour), [0, 3, 6, 9, 12, 15, 18, 21])
        XCTAssertEqual(result.timeBands.map(\.endHour), [3, 6, 9, 12, 15, 18, 21, 24])
    }

    func testTimeBandsSumToTheHourBuckets() {
        let entries = [
            entry(at: date(2026, 9, 10, 7, 0), duration: 4),
            entry(at: date(2026, 9, 10, 8, 0), duration: 6),
            entry(at: date(2026, 9, 10, 8, 30), duration: 2),
            entry(at: date(2026, 9, 10, 20, 0), duration: 8)
        ]

        let result = stats(entries)

        XCTAssertEqual(result.timeBands.reduce(0) { $0 + $1.dictations }, result.totalDictations)
        XCTAssertEqual(
            result.timeBands.reduce(0) { $0 + $1.seconds },
            result.totalSeconds,
            accuracy: 0.0001
        )
    }

    func testTimeBandReportsItsBusiestHour() {
        let entries = [
            entry(at: date(2026, 9, 10, 7, 0)),
            entry(at: date(2026, 9, 10, 8, 0)),
            entry(at: date(2026, 9, 10, 8, 30))
        ]

        let morning = stats(entries).timeBands.first { $0.startHour == 6 }

        XCTAssertEqual(morning?.dictations, 3)
        XCTAssertEqual(morning?.busiestHour, 8)
    }

    func testEmptyTimeBandsHaveNoBusiestHour() {
        let result = stats([entry(at: date(2026, 9, 10, 20, 0))])

        XCTAssertNil(result.timeBands.first { $0.startHour == 0 }?.busiestHour)
        XCTAssertEqual(result.timeBands.first { $0.startHour == 18 }?.busiestHour, 20)
    }

    func testTimeBandBusiestHourTieResolvesToTheEarlierHour() {
        let entries = [
            entry(at: date(2026, 9, 10, 19, 0)),
            entry(at: date(2026, 9, 10, 20, 0))
        ]

        let evening = stats(entries).timeBands.first { $0.startHour == 18 }

        XCTAssertEqual(evening?.busiestHour, 19)
    }

    // MARK: - Activity scale

    func testActivityScaleOfNoUsageIsEmpty() {
        XCTAssertEqual(ActivityScale.quartiles(of: []), .empty)
        XCTAssertEqual(ActivityScale.quartiles(of: [0, 0, 0]), .empty)
    }

    func testZeroCountsAreAlwaysLevelNone() {
        XCTAssertEqual(ActivityScale.quartiles(of: [1, 2, 3, 4]).level(for: 0), .none)
    }

    /// When every active day looks the same, no day stands out, so they all
    /// sit on the lowest active step rather than being spread over four
    /// arbitrary shades.
    func testUniformUsageProducesASingleActiveLevel() {
        let scale = ActivityScale.quartiles(of: [1, 1, 1, 1])

        XCTAssertEqual(scale.level(for: 1), .low)
    }

    func testGradedUsageProducesAllFourActiveLevels() {
        let scale = ActivityScale.quartiles(of: [1, 2, 3, 4, 5, 6, 7, 8])

        XCTAssertEqual(scale.level(for: 1), .low)
        XCTAssertEqual(scale.level(for: 3), .medium)
        XCTAssertEqual(scale.level(for: 5), .high)
        XCTAssertEqual(scale.level(for: 8), .veryHigh)
    }

    func testASingleOutlierSitsAtTheTopOfTheScale() {
        let scale = ActivityScale.quartiles(of: [1, 1, 1, 10])

        XCTAssertEqual(scale.level(for: 1), .low)
        XCTAssertEqual(scale.level(for: 10), .veryHigh)
    }

    func testActivityLevelsAreOrdered() {
        XCTAssertLessThan(ActivityLevel.none, .low)
        XCTAssertLessThan(ActivityLevel.low, .medium)
        XCTAssertLessThan(ActivityLevel.medium, .high)
        XCTAssertLessThan(ActivityLevel.high, .veryHigh)
    }

    func testActivityScaleIsMonotonic() {
        let scale = ActivityScale.quartiles(of: [1, 2, 3, 4, 5, 6, 7, 8])

        for count in 1..<20 {
            XCTAssertLessThanOrEqual(
                scale.level(for: count).rawValue,
                scale.level(for: count + 1).rawValue,
                "A busier day can never render lighter than a quieter one"
            )
        }
    }

    // MARK: - Activity calendar

    /// September 2026 starts on a Tuesday and ends on a Wednesday, so a
    /// Sunday-first grid runs from Aug 30 to Oct 3: five columns of seven.
    func testActivityCalendarCoversWholeWeeks() {
        let grid = stats([entry(at: date(2026, 9, 10))]).activityCalendar(in: month(2026, 9))

        XCTAssertEqual(grid.weeks.count, 5)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.cells.count == 7 })
        XCTAssertEqual(grid.weeks[0].start, date(2026, 8, 30, 0, 0))
    }

    func testActivityCalendarPadsToTheWeekBoundary() throws {
        let grid = stats([entry(at: date(2026, 9, 10))]).activityCalendar(in: month(2026, 9))

        let first = try XCTUnwrap(grid.weeks.first)
        let last = try XCTUnwrap(grid.weeks.last)

        // There is no `suffix(while:)` to mirror `prefix(while:)`, so the
        // trailing pad is counted from the reversed tail.
        let leading = first.cells.prefix { !$0.isInRange }
        let trailing = last.cells.reversed().prefix { !$0.isInRange }

        XCTAssertEqual(leading.count, 2, "Aug 30 and Aug 31 pad the first column")
        XCTAssertEqual(trailing.count, 3, "Oct 1 to Oct 3 pad the last column")
        XCTAssertTrue(leading.allSatisfy { $0.level == .none })
        XCTAssertTrue(trailing.allSatisfy { $0.level == .none })
    }

    func testActivityCalendarCoversEveryDayOfTheWindowExactlyOnce() {
        let window = month(2026, 9)
        let grid = stats([entry(at: date(2026, 9, 10))]).activityCalendar(in: window)

        let inRange = grid.weeks.flatMap(\.cells).filter(\.isInRange).map(\.day)

        XCTAssertEqual(inRange.count, 30)
        XCTAssertEqual(Set(inRange).count, 30, "No day may appear in two columns")
        XCTAssertEqual(inRange.min(), window.start)
        XCTAssertEqual(inRange, inRange.sorted(), "Cells read chronologically down each column")
    }

    func testActivityCalendarCellsCarryRealCounts() {
        let entries = [
            entry(at: date(2026, 9, 10, 9, 0), duration: 5),
            entry(at: date(2026, 9, 10, 10, 0), duration: 7)
        ]

        let grid = stats(entries).activityCalendar(in: month(2026, 9))
        let tenth = grid.weeks.flatMap(\.cells).first { $0.day == date(2026, 9, 10, 0, 0) }

        XCTAssertEqual(tenth?.dictations, 2)
        XCTAssertEqual(tenth?.seconds, 12)
        XCTAssertEqual(tenth?.words, 6)
        XCTAssertNotEqual(tenth?.level, ActivityLevel.none)
    }

    func testActivityCalendarLabelsEachMonthOnce() {
        let entries = [entry(at: date(2026, 9, 10)), entry(at: date(2026, 10, 10))]
        let window = DateInterval(start: month(2026, 9).start, end: month(2026, 10).end)

        let grid = stats(entries).activityCalendar(in: window)

        XCTAssertEqual(grid.monthLabels.count, 2)
        XCTAssertEqual(grid.monthLabels[0].weekIndex, 0)
        XCTAssertEqual(grid.monthLabels.map(\.month), [date(2026, 9, 1, 0, 0), date(2026, 10, 1, 0, 0)])
    }

    /// The scale is built from the whole history, so paging between months
    /// cannot silently re-shade the same amount of work.
    func testActivityCalendarScaleComesFromTheWholeHistoryNotTheWindow() {
        var entries = (0..<20).map { entry(at: date(2026, 8, 1, 9 + $0 % 10, 0)) }
        entries.append(entry(at: date(2026, 9, 4, 9, 0)))

        let result = stats(entries)
        let september = result.activityCalendar(in: month(2026, 9))
        let august = result.activityCalendar(in: month(2026, 8))

        XCTAssertEqual(september.scale, august.scale)
        XCTAssertEqual(september.scale, ActivityScale.quartiles(of: result.days.map(\.dictations)))
    }

    func testActivityCalendarRetainsItsWindow() {
        let window = month(2026, 9)
        let grid = stats([entry(at: date(2026, 9, 10))]).activityCalendar(in: window)

        XCTAssertEqual(grid.interval, window)
    }

    func testActivityCalendarOfAQuietMonthIsAllZero() {
        let grid = stats([entry(at: date(2026, 3, 10))]).activityCalendar(in: month(2026, 9))

        let inRange = grid.weeks.flatMap(\.cells).filter(\.isInRange)
        XCTAssertEqual(inRange.count, 30)
        XCTAssertTrue(inRange.allSatisfy { $0.dictations == 0 && $0.level == .none })
    }

    // MARK: - Volume

    func testLargeHistoryAggregatesConsistently() {
        // 12 months × 20 days × 3 dictations.
        var entries: [DictationEntry] = []
        for monthIndex in 1...12 {
            for day in 1...20 {
                for hour in [9, 14, 21] {
                    entries.append(entry(at: date(2026, monthIndex, day, hour, 0), duration: 6))
                }
            }
        }

        let result = stats(entries)

        XCTAssertEqual(result.totalDictations, 720)
        XCTAssertEqual(result.timedDictations, 720)
        XCTAssertEqual(result.totalSeconds, 4320)
        XCTAssertEqual(result.totalWords, 2160)
        XCTAssertEqual(result.activeDays, 240)
        XCTAssertEqual(result.buckets(.monthly).count, 12)
        XCTAssertEqual(result.buckets(.yearly).count, 1)
        XCTAssertEqual(result.days.reduce(0) { $0 + $1.dictations }, result.totalDictations)
        XCTAssertEqual(result.hours.reduce(0) { $0 + $1.dictations }, result.totalDictations)
    }
}
