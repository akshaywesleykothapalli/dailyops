import XCTest
@testable import DailyOps

/// Covers the presentation layer that sits between `UsageStatistics` and the
/// Insights views: window navigation, the detail back-stack, one-day
/// re-aggregation, and the rendered detail reports.
///
/// Like `UsageStatisticsTests`, nothing here touches SwiftData — `DictationEntry`
/// values are constructed and passed straight to the view model, never inserted
/// into a context.
///
/// Every calendar is pinned (identifier, timezone, locale, `firstWeekday`) so
/// bucketing and weekday ordering are deterministic. Assertions on composed
/// strings are written against `InsightsFormat` rather than against literal
/// digits wherever a number could be grouped or localised, so the templates and
/// pluralisation are tested without the host's region settings deciding the
/// outcome. The hand-composed formatters — durations, clock hours, bands,
/// percentages — are locale-free by construction and are asserted literally.
@MainActor
final class InsightsViewModelTests: XCTestCase {

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
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)!
    }

    /// `n` three-letter words, so a fixture's word count is `n` and its
    /// character count is `4n - 1` without having to count by hand.
    private func words(_ n: Int) -> String {
        guard n > 0 else { return "" }
        return Array(repeating: "abc", count: n).joined(separator: " ")
    }

    private func entry(
        _ date: Date,
        words wordCount: Int,
        duration: TimeInterval,
        app: String
    ) -> DictationEntry {
        let text = words(wordCount)
        return DictationEntry(date: date, raw: text, cleaned: text, duration: duration, appName: app)
    }

    private func model(
        anchor: Date = Date(timeIntervalSinceReferenceDate: 0),
        calendar: Calendar? = nil
    ) -> InsightsViewModel {
        InsightsViewModel(calendar: calendar ?? utc, anchor: anchor)
    }

    /// A model anchored inside September 2026.
    private func septemberModel(firstWeekday: Int = 1) -> InsightsViewModel {
        InsightsViewModel(
            calendar: makeCalendar(firstWeekday: firstWeekday),
            anchor: date(2026, 9, 15)
        )
    }

    /// Six dictations inside September 2026, plus one on either side of it.
    ///
    /// Shaped so that every figure the report tests assert on has a unique
    /// maximum — busiest day, busiest hour, longest day, wordiest day and the
    /// per-app ordering all resolve without relying on tie-breaking.
    ///
    /// In-window totals: 6 dictations, 13 words, 46 characters, 135s, 5 timed,
    /// 3 active days (Sep 1 Tue, Sep 4 Fri, Sep 11 Fri).
    private var september: [DictationEntry] {
        [
            entry(date(2026, 9, 1, 9, 0), words: 2, duration: 10, app: "Notes"),
            entry(date(2026, 9, 1, 9, 30), words: 1, duration: 20, app: "Mail"),
            entry(date(2026, 9, 4, 19, 0), words: 3, duration: 30, app: "Notes"),
            entry(date(2026, 9, 11, 9, 15), words: 3, duration: 25, app: "Notes"),
            entry(date(2026, 9, 11, 19, 45), words: 3, duration: 50, app: "Mail"),
            entry(date(2026, 9, 11, 20, 30), words: 1, duration: 0, app: "Safari"),
            // Outside the window, to prove scoping.
            entry(date(2026, 8, 31, 12, 0), words: 1, duration: 5, app: "Other"),
            entry(date(2026, 10, 1, 12, 0), words: 1, duration: 5, app: "Other")
        ]
    }

    private var sep1: Date { date(2026, 9, 1, 0, 0) }
    private var sep11: Date { date(2026, 9, 11, 0, 0) }

    // MARK: - InsightsFormat.duration

    func testDurationRendersSecondsMinutesAndHours() {
        XCTAssertEqual(InsightsFormat.duration(0), "0s")
        XCTAssertEqual(InsightsFormat.duration(45), "45s")
        XCTAssertEqual(InsightsFormat.duration(60), "1m")
        XCTAssertEqual(InsightsFormat.duration(135), "2m 15s")
        XCTAssertEqual(InsightsFormat.duration(3600), "1h")
        XCTAssertEqual(InsightsFormat.duration(3660), "1h 1m")
        XCTAssertEqual(InsightsFormat.duration(5040), "1h 24m")
    }

    func testDurationRoundsToNearestSecond() {
        XCTAssertEqual(InsightsFormat.duration(59.6), "1m")
        XCTAssertEqual(InsightsFormat.duration(0.4), "0s")
    }

    /// A negative duration is a data error, not a display case — it reads as
    /// zero rather than as an empty string or a minus sign.
    func testDurationTreatsNegativeAsZero() {
        XCTAssertEqual(InsightsFormat.duration(-90), "0s")
    }

    /// Hours drop the seconds: "1h 24m" is the useful reading, "1h 24m 7s" is
    /// noise at that scale.
    func testDurationOmitsSecondsOnceHoursAppear() {
        XCTAssertEqual(InsightsFormat.duration(5047), "1h 24m")
    }

    // MARK: - InsightsFormat clock labels

    func testHourUsesTwelveHourClockWithMidnightAndNoon() {
        XCTAssertEqual(InsightsFormat.hour(0), "12 AM")
        XCTAssertEqual(InsightsFormat.hour(9), "9 AM")
        XCTAssertEqual(InsightsFormat.hour(11), "11 AM")
        XCTAssertEqual(InsightsFormat.hour(12), "12 PM")
        XCTAssertEqual(InsightsFormat.hour(18), "6 PM")
        XCTAssertEqual(InsightsFormat.hour(23), "11 PM")
    }

    /// 24 is the exclusive end of the last band, so it has to wrap rather than
    /// render as "12 PM" or overflow.
    func testHourWrapsOutOfRangeValues() {
        XCTAssertEqual(InsightsFormat.hour(24), "12 AM")
        XCTAssertEqual(InsightsFormat.hour(25), "1 AM")
        XCTAssertEqual(InsightsFormat.hour(-1), "11 PM")
    }

    func testBandJoinsStartAndExclusiveEnd() {
        XCTAssertEqual(InsightsFormat.band(startHour: 18, endHour: 21), "6 PM – 9 PM")
        XCTAssertEqual(InsightsFormat.band(startHour: 0, endHour: 3), "12 AM – 3 AM")
        XCTAssertEqual(InsightsFormat.band(startHour: 21, endHour: 24), "9 PM – 12 AM")
    }

    // MARK: - InsightsFormat counts

    func testDictationsPluralises() {
        XCTAssertEqual(InsightsFormat.dictations(0), "0 dictations")
        XCTAssertEqual(InsightsFormat.dictations(1), "1 dictation")
        XCTAssertEqual(InsightsFormat.dictations(2), "2 dictations")
    }

    func testPercentRoundsToWholePercent() {
        XCTAssertEqual(InsightsFormat.percent(0), "0%")
        XCTAssertEqual(InsightsFormat.percent(0.5), "50%")
        XCTAssertEqual(InsightsFormat.percent(1), "100%")
        XCTAssertEqual(InsightsFormat.percent(0.375), "38%")
    }

    /// Fractions arrive from divisions that can overshoot or divide by zero, so
    /// clamping and non-finite handling are part of the contract.
    func testPercentClampsAndRejectsNonFinite() {
        XCTAssertEqual(InsightsFormat.percent(1.4), "100%")
        XCTAssertEqual(InsightsFormat.percent(-0.3), "0%")
        XCTAssertEqual(InsightsFormat.percent(.nan), "0%")
        XCTAssertEqual(InsightsFormat.percent(.infinity), "0%")
    }

    func testCountAndDecimalRenderPlainWholeNumbers() {
        XCTAssertEqual(InsightsFormat.count(0), "0")
        XCTAssertEqual(InsightsFormat.count(42), "42")
        XCTAssertEqual(InsightsFormat.decimal(2), "2")
    }

    // MARK: - Weekday rotation

    func testWeekdaySymbolsStartAtSunday() {
        let model = septemberModel(firstWeekday: 1)
        XCTAssertEqual(model.weekdaySymbols.count, 7)
        XCTAssertEqual(model.weekdaySymbols.first, "Sun")
        XCTAssertEqual(model.weekdaySymbols.last, "Sat")
        XCTAssertEqual(model.weekdayNames.first, "Sunday")
        XCTAssertEqual(model.weekdayNames.last, "Saturday")
    }

    /// `Calendar` hands back Sunday-indexed symbols whatever `firstWeekday` is,
    /// so the rotation has to happen explicitly — this is the test that would
    /// fail if it were dropped.
    func testWeekdaySymbolsRotateForMondayFirst() {
        let model = septemberModel(firstWeekday: 2)
        XCTAssertEqual(model.weekdaySymbols.first, "Mon")
        XCTAssertEqual(model.weekdaySymbols.last, "Sun")
        XCTAssertEqual(model.weekdayNames.first, "Monday")
        XCTAssertEqual(model.weekdayNames.last, "Sunday")
    }

    // MARK: - Window

    func testMonthWindowCoversTheAnchorsMonth() {
        let model = septemberModel()
        XCTAssertEqual(model.window.start, date(2026, 9, 1, 0, 0))
        XCTAssertEqual(model.window.end, date(2026, 10, 1, 0, 0))
    }

    func testYearWindowCoversTheAnchorsYear() {
        let model = septemberModel()
        model.select(scope: .year)
        XCTAssertEqual(model.window.start, date(2026, 1, 1, 0, 0))
        XCTAssertEqual(model.window.end, date(2027, 1, 1, 0, 0))
    }

    func testStepMovesTheWindowByScope() {
        let model = septemberModel()

        model.step(by: -1)
        XCTAssertEqual(model.window.start, date(2026, 8, 1, 0, 0))

        model.step(by: 2)
        XCTAssertEqual(model.window.start, date(2026, 10, 1, 0, 0))

        model.select(scope: .year)
        model.step(by: -1)
        XCTAssertEqual(model.window.start, date(2025, 1, 1, 0, 0))
    }

    func testCanStepForwardOnlyOnceTheWindowHasElapsed() {
        let model = septemberModel()
        XCTAssertFalse(model.canStepForward(now: date(2026, 9, 20)))
        XCTAssertTrue(model.canStepForward(now: date(2026, 10, 5)))
    }

    func testShowYearKeepsTheMonthAndMovesTheYear() {
        let model = septemberModel()
        model.show(year: 2024)
        XCTAssertEqual(model.window.start, date(2024, 9, 1, 0, 0))
        XCTAssertEqual(model.window.end, date(2024, 10, 1, 0, 0))
    }

    func testYearsSpanFirstToLastDayInclusive() {
        let model = septemberModel()
        let entries = [
            entry(date(2024, 3, 2, 10, 0), words: 1, duration: 5, app: "Notes"),
            entry(date(2026, 9, 11, 10, 0), words: 1, duration: 5, app: "Notes")
        ]
        XCTAssertEqual(model.years(in: model.statistics(for: entries)), [2024, 2025, 2026])
    }

    func testYearsIsEmptyWithoutHistory() {
        let model = septemberModel()
        XCTAssertEqual(model.years(in: model.statistics(for: [])), [])
    }

    // MARK: - Granularity

    func testAvailableGranularitiesExcludeUnreadableBucketSizes() {
        let model = septemberModel()
        XCTAssertEqual(model.availableGranularities, [.daily, .weekly])

        model.select(scope: .year)
        XCTAssertEqual(model.availableGranularities, [.weekly, .monthly])
    }

    /// Daily inside a year would be 365 bars, so switching scope has to correct
    /// a now-illegal bucket size rather than leave the picker in a state the
    /// chart cannot draw.
    func testSelectingYearScopeCorrectsAnIllegalGranularity() {
        let model = septemberModel()
        model.granularity = .daily
        model.select(scope: .year)
        XCTAssertEqual(model.granularity, .weekly)
    }

    func testUsesWindowOnlyForBucketsFinerThanTheScope() {
        let model = septemberModel()
        XCTAssertTrue(model.usesWindow(for: .daily))
        XCTAssertTrue(model.usesWindow(for: .weekly))
        XCTAssertFalse(model.usesWindow(for: .monthly))
        XCTAssertFalse(model.usesWindow(for: .yearly))

        model.select(scope: .year)
        XCTAssertTrue(model.usesWindow(for: .monthly))
        XCTAssertFalse(model.usesWindow(for: .yearly))
    }

    // MARK: - Navigation

    func testOpeningADetailFromTheOverviewLeavesAnEmptyStack() {
        let model = septemberModel()
        model.open(.metric(.dictations))

        XCTAssertEqual(model.detail, .metric(.dictations))
        XCTAssertTrue(model.detailStack.isEmpty)
        XCTAssertEqual(model.backTitle, "Insights")
    }

    func testOpeningADetailFromADetailPushesTheCurrentOne() {
        let model = septemberModel()
        model.open(.metric(.dictations))
        model.open(.day(sep11))

        XCTAssertEqual(model.detail, .day(sep11))
        XCTAssertEqual(model.detailStack, [.metric(.dictations)])
        XCTAssertEqual(model.backTitle, "Dictations")
    }

    func testClosingStepsBackOneLevelAtATime() {
        let model = septemberModel()
        model.open(.metric(.dictations))
        model.open(.day(sep11))

        model.closeDetail()
        XCTAssertEqual(model.detail, .metric(.dictations))
        XCTAssertTrue(model.detailStack.isEmpty)

        model.closeDetail()
        XCTAssertNil(model.detail)
        XCTAssertEqual(model.backTitle, "Insights")
    }

    func testClosingPastTheOverviewIsHarmless() {
        let model = septemberModel()
        model.closeDetail()
        XCTAssertNil(model.detail)
        XCTAssertTrue(model.detailStack.isEmpty)
    }

    /// A double-click must not make the back button need pressing twice.
    func testReopeningTheSameDetailDoesNotGrowTheStack() {
        let model = septemberModel()
        model.open(.metric(.words))
        model.open(.metric(.words))

        XCTAssertEqual(model.detail, .metric(.words))
        XCTAssertTrue(model.detailStack.isEmpty)
    }

    func testDismissDetailsClearsTheWholeStack() {
        let model = septemberModel()
        model.open(.metric(.dictations))
        model.open(.timeBand(startHour: 18))
        model.open(.day(sep11))

        model.dismissDetails()
        XCTAssertNil(model.detail)
        XCTAssertTrue(model.detailStack.isEmpty)
    }

    /// Moving the window changes the numbers a detail is explaining, so the
    /// detail cannot survive the move.
    func testMovingTheWindowDismissesOpenDetails() {
        let stepped = septemberModel()
        stepped.open(.metric(.dictations))
        stepped.step(by: -1)
        XCTAssertNil(stepped.detail)

        let yearShown = septemberModel()
        yearShown.open(.metric(.dictations))
        yearShown.show(year: 2024)
        XCTAssertNil(yearShown.detail)

        let rescoped = septemberModel()
        rescoped.open(.metric(.dictations))
        rescoped.select(scope: .year)
        XCTAssertNil(rescoped.detail)
    }

    /// `select` is a no-op for the scope already showing, which must not take
    /// a detail down with it.
    func testSelectingTheCurrentScopeKeepsTheOpenDetail() {
        let model = septemberModel()
        model.open(.metric(.dictations))
        model.select(scope: .month)
        XCTAssertEqual(model.detail, .metric(.dictations))
    }

    func testDetailTitles() {
        let model = septemberModel()
        XCTAssertEqual(model.title(for: .metric(.speakingTime)), "Speaking Time")
        XCTAssertEqual(model.title(for: .metric(.activeDays)), "Active Days")
        XCTAssertEqual(model.title(for: .timeBand(startHour: 18)), "6 PM – 9 PM")
        XCTAssertEqual(model.title(for: .day(sep11)), model.dayLabel(sep11))
    }

    /// A day detail can be opened from a cell holding any instant in the day,
    /// so the title has to normalise before formatting.
    func testDayTitleNormalisesToStartOfDay() {
        let model = septemberModel()
        XCTAssertEqual(
            model.title(for: .day(date(2026, 9, 11, 23, 45))),
            model.title(for: .day(sep11))
        )
    }

    // MARK: - Day statistics

    func testDayStatisticsCoversOnlyThatDay() {
        let model = septemberModel()
        let day = model.dayStatistics(for: september, day: sep11)

        XCTAssertEqual(day.totalDictations, 3)
        XCTAssertEqual(day.totalWords, 7)
        XCTAssertEqual(day.totalSeconds, 75)
        XCTAssertEqual(day.activeDays, 1)
        XCTAssertEqual(day.firstDay, sep11)
    }

    func testDayStatisticsAcceptsAnyInstantInTheDay() {
        let model = septemberModel()
        let fromMidnight = model.dayStatistics(for: september, day: sep11)
        let fromEvening = model.dayStatistics(for: september, day: date(2026, 9, 11, 23, 59))
        XCTAssertEqual(fromMidnight, fromEvening)
    }

    /// The day cache is keyed on the day as well as on the history — a cache
    /// that ignored the day would hand the second call the first day's numbers.
    func testDayStatisticsDistinguishesConsecutiveLookups() {
        let model = septemberModel()
        let eleventh = model.dayStatistics(for: september, day: sep11)
        let first = model.dayStatistics(for: september, day: sep1)
        let eleventhAgain = model.dayStatistics(for: september, day: sep11)

        XCTAssertEqual(eleventh.totalDictations, 3)
        XCTAssertEqual(first.totalDictations, 2)
        XCTAssertEqual(eleventhAgain, eleventh)
    }

    func testDayStatisticsIsEmptyForAQuietDay() {
        let model = septemberModel()
        let day = model.dayStatistics(for: september, day: date(2026, 9, 2))
        XCTAssertTrue(day.isEmpty)
        XCTAssertEqual(day.totalDictations, 0)
    }

    // MARK: - Window scoping

    func testWindowStatisticsExcludeEntriesOutsideTheWindow() {
        let model = septemberModel()
        XCTAssertEqual(model.statistics(for: september).totalDictations, 8)
        XCTAssertEqual(model.windowStatistics(for: september).totalDictations, 6)
    }

    func testWindowStatisticsAreStableAcrossRepeatCalls() {
        let model = septemberModel()
        let first = model.windowStatistics(for: september)
        let second = model.windowStatistics(for: september)
        XCTAssertEqual(first, second)
    }

    func testWindowStatisticsFollowTheWindow() {
        let model = septemberModel()
        XCTAssertEqual(model.windowStatistics(for: september).totalDictations, 6)

        model.step(by: -1)
        XCTAssertEqual(model.windowStatistics(for: september).totalDictations, 1)
    }

    // MARK: - Metric reports

    func testDictationsReport() {
        let model = septemberModel()
        let report = model.report(for: .metric(.dictations), entries: september)

        XCTAssertEqual(report.title, "Dictations")
        XCTAssertEqual(report.scope, model.windowTitle)
        XCTAssertEqual(report.value, InsightsFormat.count(6))
        XCTAssertEqual(
            report.caption,
            "\(InsightsFormat.dictations(6)) across \(InsightsFormat.count(3)) active days"
        )

        XCTAssertEqual(
            report.highlights.first { $0.label == "Busiest day" }?.value,
            "\(model.dayLabel(sep11)) · \(InsightsFormat.count(3))"
        )
        XCTAssertEqual(
            report.highlights.first { $0.label == "Peak hour" }?.value,
            "9 AM · \(InsightsFormat.count(3))"
        )
        XCTAssertEqual(
            report.highlights.first { $0.label == "Per active day" }?.value,
            InsightsFormat.decimal(2)
        )
    }

    func testDictationsReportBreaksDownByApp() {
        let model = septemberModel()
        let breakdown = model.report(for: .metric(.dictations), entries: september).breakdown

        XCTAssertEqual(breakdown?.title, "By App")
        XCTAssertEqual(breakdown?.items.map(\.label), ["Notes", "Mail", "Safari"])
        XCTAssertEqual(breakdown?.items.map(\.value), [
            InsightsFormat.count(3), InsightsFormat.count(2), InsightsFormat.count(1)
        ])

        // Fractions are measured against the largest row, not the total.
        let fractions = breakdown?.items.map(\.fraction) ?? []
        XCTAssertEqual(fractions.count, 3)
        XCTAssertEqual(fractions[0], 1.0, accuracy: 0.0001)
        XCTAssertEqual(fractions[1], 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(fractions[2], 1.0 / 3.0, accuracy: 0.0001)
    }

    func testSpeakingTimeReport() {
        let model = septemberModel()
        let report = model.report(for: .metric(.speakingTime), entries: september)
        let statistics = model.windowStatistics(for: september)

        XCTAssertEqual(report.title, "Speaking Time")
        XCTAssertEqual(report.value, "2m 15s")
        XCTAssertEqual(report.caption, "\(InsightsFormat.dictations(5)) with a measured duration")
        XCTAssertEqual(report.highlights.first { $0.label == "Average" }?.value, "27s")
        XCTAssertEqual(
            report.highlights.first { $0.label == "Longest day" }?.value,
            "\(model.dayLabel(sep11)) · 1m 15s"
        )
        XCTAssertEqual(
            report.highlights.first { $0.label == "Words per minute" }?.value,
            InsightsFormat.decimal(statistics.wordsPerMinute)
        )
    }

    /// Safari recorded a dictation with no measured duration, so it has no row
    /// in a breakdown weighted by seconds — an empty bar would claim it was
    /// timed at zero.
    func testSpeakingTimeBreakdownDropsUntimedApps() {
        let model = septemberModel()
        let breakdown = model.report(for: .metric(.speakingTime), entries: september).breakdown

        XCTAssertEqual(breakdown?.title, "By App")
        XCTAssertEqual(breakdown?.items.map(\.label), ["Mail", "Notes"])
        XCTAssertEqual(breakdown?.items.map(\.value), ["1m 10s", "1m 5s"])
        XCTAssertEqual(breakdown?.items.first?.fraction ?? 0, 1.0, accuracy: 0.0001)
    }

    func testSpeakingTimeReportWhenNothingWasTimed() {
        let model = septemberModel()
        let untimed = [
            entry(date(2026, 9, 3, 10, 0), words: 2, duration: 0, app: "Notes"),
            entry(date(2026, 9, 5, 10, 0), words: 2, duration: 0, app: "Notes")
        ]
        let report = model.report(for: .metric(.speakingTime), entries: untimed)

        XCTAssertEqual(report.value, "0s")
        XCTAssertEqual(report.caption, "no dictation in this period was timed")
        XCTAssertEqual(report.highlights.first { $0.label == "Average" }?.value, "0s")
        XCTAssertNil(report.highlights.first { $0.label == "Longest day" })
        XCTAssertNil(report.highlights.first { $0.label == "Words per minute" })
        XCTAssertNil(report.breakdown)
    }

    func testWordsReport() {
        let model = septemberModel()
        let report = model.report(for: .metric(.words), entries: september)
        let statistics = model.windowStatistics(for: september)

        XCTAssertEqual(report.title, "Words")
        XCTAssertEqual(report.value, InsightsFormat.count(13))
        XCTAssertEqual(report.caption, "\(InsightsFormat.count(46)) characters written")
        XCTAssertEqual(
            report.highlights.first { $0.label == "Per dictation" }?.value,
            InsightsFormat.decimal(statistics.averageWords)
        )
        XCTAssertEqual(
            report.highlights.first { $0.label == "Most words" }?.value,
            "\(model.dayLabel(sep11)) · \(InsightsFormat.count(7))"
        )
        XCTAssertEqual(
            report.highlights.first { $0.label == "Most used in" }?.value,
            "Notes · \(InsightsFormat.count(8))"
        )
    }

    func testWordsBreakdownOrdersAppsByWords() {
        let model = septemberModel()
        let breakdown = model.report(for: .metric(.words), entries: september).breakdown

        XCTAssertEqual(breakdown?.items.map(\.label), ["Notes", "Mail", "Safari"])
        XCTAssertEqual(breakdown?.items.map(\.value), [
            InsightsFormat.count(8), InsightsFormat.count(4), InsightsFormat.count(1)
        ])
    }

    func testActiveDaysReport() {
        let model = septemberModel()
        let report = model.report(for: .metric(.activeDays), entries: september)

        XCTAssertEqual(report.title, "Active Days")
        XCTAssertEqual(report.value, InsightsFormat.count(3))
        XCTAssertEqual(
            report.caption,
            "active on \(InsightsFormat.count(3)) of \(InsightsFormat.count(30)) days"
        )
        XCTAssertEqual(
            report.highlights.first { $0.label == "Longest streak" }?.value,
            "\(InsightsFormat.count(1))d"
        )
        XCTAssertEqual(report.highlights.first { $0.label == "First" }?.value, model.dayLabel(sep1))
        XCTAssertEqual(report.highlights.first { $0.label == "Last" }?.value, model.dayLabel(sep11))
    }

    /// Sep 1 2026 is a Tuesday; Sep 4 and Sep 11 are Fridays. Quiet weekdays
    /// keep their rows — the gaps are the shape being described.
    func testActiveDaysBreaksDownByWeekdayKeepingZeroes() {
        let model = septemberModel(firstWeekday: 1)
        let breakdown = model.report(for: .metric(.activeDays), entries: september).breakdown

        XCTAssertEqual(breakdown?.title, "By Weekday")
        XCTAssertEqual(breakdown?.items.count, 7)
        XCTAssertEqual(breakdown?.items.map(\.label), model.weekdayNames)

        let fractions = breakdown?.items.map(\.fraction) ?? []
        XCTAssertEqual(fractions.count, 7)
        XCTAssertEqual(fractions[2], 0.5, accuracy: 0.0001)   // Tuesday: 1 of 2
        XCTAssertEqual(fractions[5], 1.0, accuracy: 0.0001)   // Friday: 2 of 2
        for index in [0, 1, 3, 4, 6] {
            XCTAssertEqual(fractions[index], 0, accuracy: 0.0001)
        }
    }

    /// The weekday rows are laid out in the calendar's grid order, so a
    /// Monday-first calendar moves Friday from index 5 to index 4.
    func testWeekdayBreakdownFollowsFirstWeekday() {
        let model = septemberModel(firstWeekday: 2)
        let breakdown = model.report(for: .metric(.activeDays), entries: september).breakdown
        let fractions = breakdown?.items.map(\.fraction) ?? []

        XCTAssertEqual(breakdown?.items.map(\.label), model.weekdayNames)
        XCTAssertEqual(fractions.count, 7)
        XCTAssertEqual(fractions[1], 0.5, accuracy: 0.0001)   // Tuesday
        XCTAssertEqual(fractions[4], 1.0, accuracy: 0.0001)   // Friday
    }

    /// Metric details chart the window day by day, zero-filled, so a quiet
    /// stretch reads as quiet rather than being compressed out of the chart.
    func testMetricReportsCarryAZeroFilledDailySeries() {
        let model = septemberModel()
        let series = model.report(for: .metric(.dictations), entries: september).series

        XCTAssertEqual(series.count, 30)
        XCTAssertEqual(series.first?.day, sep1)
        XCTAssertEqual(series.first?.dictations, 2)
        XCTAssertEqual(series.first { $0.day == date(2026, 9, 2, 0, 0) }?.dictations, 0)
    }

    // MARK: - Time band reports

    func testTimeBandReport() {
        let model = septemberModel()
        let report = model.report(for: .timeBand(startHour: 18), entries: september)

        XCTAssertEqual(report.title, "6 PM – 9 PM")
        XCTAssertEqual(report.scope, model.windowTitle)
        XCTAssertEqual(report.value, InsightsFormat.count(3))
        XCTAssertEqual(report.caption, InsightsFormat.dictations(3))

        XCTAssertEqual(report.highlights.first { $0.label == "Speaking time" }?.value, "1m 20s")
        XCTAssertEqual(
            report.highlights.first { $0.label == "Words" }?.value,
            InsightsFormat.count(7)
        )
        XCTAssertEqual(report.highlights.first { $0.label == "Most active hour" }?.value, "7 PM")
        XCTAssertEqual(report.highlights.first { $0.label == "Share of month" }?.value, "50%")
    }

    /// Hour-of-day usage is summed across every day in the window, so a per-day
    /// chart underneath it would be charting something else.
    func testTimeBandReportHasNoDailySeries() {
        let model = septemberModel()
        XCTAssertTrue(model.report(for: .timeBand(startHour: 18), entries: september).series.isEmpty)
    }

    func testTimeBandBreaksDownByHourKeepingQuietHours() {
        let model = septemberModel()
        let breakdown = model.report(for: .timeBand(startHour: 18), entries: september).breakdown

        XCTAssertEqual(breakdown?.title, "By Hour")
        XCTAssertEqual(breakdown?.items.map(\.label), ["6 PM", "7 PM", "8 PM"])
        XCTAssertEqual(breakdown?.items.map(\.value), [
            InsightsFormat.count(0), InsightsFormat.count(2), InsightsFormat.count(1)
        ])

        let fractions = breakdown?.items.map(\.fraction) ?? []
        XCTAssertEqual(fractions.count, 3)
        XCTAssertEqual(fractions[0], 0, accuracy: 0.0001)
        XCTAssertEqual(fractions[1], 1.0, accuracy: 0.0001)
        XCTAssertEqual(fractions[2], 0.5, accuracy: 0.0001)
    }

    /// An unused band is still a band the reader can click, so it reports zeroes
    /// rather than a panel full of empty bars.
    func testEmptyTimeBandReportsZeroes() {
        let model = septemberModel()
        let report = model.report(for: .timeBand(startHour: 0), entries: september)

        XCTAssertEqual(report.title, "12 AM – 3 AM")
        XCTAssertEqual(report.value, InsightsFormat.count(0))
        XCTAssertEqual(report.caption, "0 dictations")
        XCTAssertEqual(report.highlights.first { $0.label == "Speaking time" }?.value, "0s")
        XCTAssertNil(report.highlights.first { $0.label == "Most active hour" })
        XCTAssertEqual(report.highlights.first { $0.label == "Share of month" }?.value, "0%")
        XCTAssertNil(report.breakdown)
    }

    /// With no history at all there is no denominator, so the share highlight is
    /// omitted rather than shown as a made-up zero.
    func testTimeBandOmitsShareWithoutHistory() {
        let model = septemberModel()
        let report = model.report(for: .timeBand(startHour: 18), entries: [])
        XCTAssertNil(report.highlights.first { $0.label == "Share of month" })
    }

    func testTimeBandShareFollowsScope() {
        let model = septemberModel()
        model.select(scope: .year)
        let report = model.report(for: .timeBand(startHour: 18), entries: september)
        XCTAssertNotNil(report.highlights.first { $0.label == "Share of year" })
    }

    // MARK: - Day reports

    func testDayReport() {
        let model = septemberModel()
        let report = model.report(for: .day(sep11), entries: september)

        XCTAssertEqual(report.title, model.fullDayLabel(sep11))
        XCTAssertEqual(report.scope, model.windowTitle)
        XCTAssertEqual(report.value, InsightsFormat.count(3))
        XCTAssertEqual(report.caption, InsightsFormat.dictations(3))
        XCTAssertTrue(report.series.isEmpty)

        XCTAssertEqual(report.highlights.first { $0.label == "Speaking time" }?.value, "1m 15s")
        XCTAssertEqual(report.highlights.first { $0.label == "Words" }?.value, InsightsFormat.count(7))
        XCTAssertEqual(
            report.highlights.first { $0.label == "Characters" }?.value,
            InsightsFormat.count(25)
        )
        XCTAssertEqual(report.highlights.first { $0.label == "Busiest hour" }?.value, "9 AM")
    }

    /// The day panel re-aggregates that day rather than reading the window's
    /// `apps`, which are summed across the whole month — this is the assertion
    /// that would fail if it read the window instead.
    func testDayReportAttributesAppsToThatDayOnly() {
        let model = septemberModel()
        let breakdown = model.report(for: .day(sep11), entries: september).breakdown

        XCTAssertEqual(breakdown?.title, "By App")
        XCTAssertEqual(Set(breakdown?.items.map(\.label) ?? []), ["Notes", "Mail", "Safari"])
        // One dictation each on this day, so every bar is full — the month-wide
        // 3/2/1 split must not leak in here.
        for item in breakdown?.items ?? [] {
            XCTAssertEqual(item.value, InsightsFormat.count(1))
            XCTAssertEqual(item.fraction, 1.0, accuracy: 0.0001)
        }
    }

    func testQuietDayReport() {
        let model = septemberModel()
        let report = model.report(for: .day(date(2026, 9, 2)), entries: september)

        XCTAssertEqual(report.value, InsightsFormat.count(0))
        XCTAssertEqual(report.caption, "0 dictations")
        XCTAssertEqual(report.highlights.first { $0.label == "Speaking time" }?.value, "0s")
        XCTAssertNil(report.highlights.first { $0.label == "Busiest hour" })
        XCTAssertNil(report.breakdown)
    }

    // MARK: - Empty history

    func testMetricReportsWithoutHistory() {
        let model = septemberModel()

        let dictations = model.report(for: .metric(.dictations), entries: [])
        XCTAssertEqual(dictations.value, InsightsFormat.count(0))
        XCTAssertEqual(
            dictations.caption,
            "\(InsightsFormat.dictations(0)) across \(InsightsFormat.count(0)) active days"
        )
        XCTAssertNil(dictations.highlights.first { $0.label == "Busiest day" })
        XCTAssertNil(dictations.highlights.first { $0.label == "Peak hour" })
        XCTAssertEqual(
            dictations.highlights.first { $0.label == "Per active day" }?.value,
            InsightsFormat.count(0)
        )
        XCTAssertNil(dictations.breakdown)
        // The chart still spans the window, so an empty month reads as a month.
        XCTAssertEqual(dictations.series.count, 30)

        let activeDays = model.report(for: .metric(.activeDays), entries: [])
        XCTAssertEqual(activeDays.value, InsightsFormat.count(0))
        XCTAssertNil(activeDays.breakdown)
        XCTAssertNil(activeDays.highlights.first { $0.label == "First" })

        let words = model.report(for: .metric(.words), entries: [])
        XCTAssertEqual(words.value, InsightsFormat.count(0))
        XCTAssertNil(words.highlights.first { $0.label == "Most used in" })
    }

    // MARK: - Summary tiles

    func testSummaryTilesReportTheWindow() {
        let model = septemberModel()
        let tiles = model.summary(for: model.windowStatistics(for: september))

        XCTAssertEqual(tiles.map(\.metric), [.dictations, .speakingTime, .words, .activeDays])
        XCTAssertEqual(tiles[0].value, InsightsFormat.count(6))
        XCTAssertEqual(tiles[1].value, "2m 15s")
        XCTAssertEqual(tiles[2].value, InsightsFormat.count(13))
        XCTAssertEqual(tiles[3].value, InsightsFormat.count(3))
        XCTAssertEqual(tiles[3].caption, "of 30")
    }

    /// One September dictation was never timed, so the tile says how many were
    /// rather than implying the total is fully measured.
    func testDictationsTileFlagsUntimedEntries() {
        let model = septemberModel()
        let tiles = model.summary(for: model.windowStatistics(for: september))
        XCTAssertEqual(tiles[0].caption, "\(InsightsFormat.count(5)) timed")
    }

    func testSummaryTilesWithoutHistory() {
        let model = septemberModel()
        let tiles = model.summary(for: model.windowStatistics(for: []))

        XCTAssertEqual(tiles[0].caption, "in \(model.windowTitle)")
        XCTAssertEqual(tiles[1].value, "0s")
        XCTAssertEqual(tiles[1].caption, "nothing timed yet")
        XCTAssertEqual(tiles[2].caption, "no words yet")
    }

    // MARK: - Activity cell descriptions

    func testActivityDescriptionFormatsQuietAndActiveDays() {
        let model = septemberModel()

        let outOfRangeCell = ActivityCell(
            day: sep1,
            dictations: 0,
            seconds: 0,
            words: 0,
            level: .none,
            isInRange: false
        )
        XCTAssertEqual(model.activityDescription(outOfRangeCell), "")

        let quietCell = ActivityCell(
            day: sep1,
            dictations: 0,
            seconds: 0,
            words: 0,
            level: .none,
            isInRange: true
        )
        XCTAssertEqual(model.activityDescription(quietCell), "\(model.fullDayLabel(sep1)): No dictations")

        let activeCell = ActivityCell(
            day: sep11,
            dictations: 3,
            seconds: 75,
            words: 7,
            level: .high,
            isInRange: true
        )
        let description = model.activityDescription(activeCell)
        XCTAssertTrue(description.contains(model.fullDayLabel(sep11)))
        XCTAssertTrue(description.contains("3 dictations"))
        XCTAssertTrue(description.contains("1m 15s"))
        XCTAssertTrue(description.contains("7 words"))
    }

    // MARK: - Year Summary

    func testYearSummaryCalculatesMonthlyAggregates() {
        let model = septemberModel()
        model.select(scope: .year)
        let stats = model.windowStatistics(for: september)
        let summary = model.yearSummary(for: stats)

        XCTAssertEqual(summary.totalMonthsInYear, 12)
        XCTAssertEqual(summary.months.count, 12)
        XCTAssertEqual(summary.activeMonths, 3) // August, September, and October have entries in 2026

        guard let mostActive = summary.mostActiveMonth else {
            XCTFail("Expected most active month to be present")
            return
        }
        XCTAssertEqual(mostActive.monthName, "Sep")
        XCTAssertEqual(mostActive.dictations, 6)
        XCTAssertEqual(mostActive.words, 13)
        XCTAssertEqual(summary.averageMonthlyDictations, 8.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.averageMonthlyWords, 5.0, accuracy: 0.001)
    }

    func testYearSummaryEmptyHistory() {
        let model = septemberModel()
        model.select(scope: .year)
        let stats = model.windowStatistics(for: [])
        let summary = model.yearSummary(for: stats)

        XCTAssertEqual(summary.totalMonthsInYear, 12)
        XCTAssertEqual(summary.months.count, 12)
        XCTAssertEqual(summary.activeMonths, 0)
        XCTAssertNil(summary.mostActiveMonth)
        XCTAssertEqual(summary.averageMonthlyDictations, 0.0)
        XCTAssertEqual(summary.averageMonthlyWords, 0.0)
    }

    // MARK: - App Color Provider & Day Cells

    func testAppColorProviderDeterministicAndDistinct() {
        let whatsapp1 = AppColorProvider.color(for: "WhatsApp")
        let whatsapp2 = AppColorProvider.color(for: "whatsapp")
        XCTAssertEqual(whatsapp1, whatsapp2, "App colors must be case-insensitive and deterministic")

        let safari = AppColorProvider.color(for: "Safari")
        XCTAssertNotEqual(whatsapp1, safari, "WhatsApp and Safari must have distinct brand colors")

        let unknown1 = AppColorProvider.color(for: "SomeCustomApp", index: 0)
        let unknown2 = AppColorProvider.color(for: "SomeCustomApp", index: 0)
        XCTAssertEqual(unknown1, unknown2, "Fallback colors must be deterministic across calls")

        let adjacentUnknown = AppColorProvider.color(for: "SomeCustomApp", index: 1)
        XCTAssertNotEqual(unknown1, adjacentUnknown, "Adjacent index must shift fallback color to prevent visual collision")
    }

    func testYearSummaryPopulatesDayCellsWithCorrectUsage() {
        let model = septemberModel()
        model.select(scope: .year)
        let stats = model.windowStatistics(for: september)
        let summary = model.yearSummary(for: stats)

        // September is month index 8 (0-indexed: Jan=0, Feb=1, ..., Sep=8)
        let sepSummary = summary.months[8]
        XCTAssertEqual(sepSummary.monthName, "Sep")
        XCTAssertEqual(sepSummary.days.count, 30)

        // Sep 11 has 3 dictations
        let sep11Cell = sepSummary.days.first { model.calendar.isDate($0.day, inSameDayAs: sep11) }
        XCTAssertNotNil(sep11Cell)
        XCTAssertEqual(sep11Cell?.dictations, 3)
        XCTAssertEqual(sep11Cell?.words, 7)
        XCTAssertNotEqual(sep11Cell?.level, ActivityLevel.none)

        // Quiet day (Sep 2) has 0 dictations
        let sep2Date = date(2026, 9, 2)
        let sep2Cell = sepSummary.days.first { model.calendar.isDate($0.day, inSameDayAs: sep2Date) }
        XCTAssertEqual(sep2Cell?.dictations, 0)
        XCTAssertEqual(sep2Cell?.level, ActivityLevel.none)
    }
}

