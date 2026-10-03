import XCTest
@testable import DailyOps

/// Deterministic time source. `LiveTranscript` reads the clock only when a
/// candidate actually differs from the last one submitted, so `callCount`
/// doubles as a probe for "did this submission do any work at all?".
@MainActor
private final class ManualClock {
    private(set) var callCount = 0
    private var instant = ContinuousClock.now

    func advance(by duration: Duration) {
        instant = instant.advanced(by: duration)
    }

    func now() -> ContinuousClock.Instant {
        callCount += 1
        return instant
    }
}

@MainActor
final class LiveTranscriptTests: XCTestCase {
    private let interval: Duration = .milliseconds(60)

    private func makeSubject() -> (LiveTranscript, ManualClock) {
        let clock = ManualClock()
        let live = LiveTranscript(minimumInterval: interval, now: { clock.now() })
        return (live, clock)
    }

    // MARK: - Publishing

    func testFirstSubmitPublishesImmediately() {
        let (live, _) = makeSubject()

        live.submit("hello")

        XCTAssertEqual(live.text, "hello")
        XCTAssertTrue(live.hasText)
    }

    func testInitialStateIsEmpty() {
        let (live, _) = makeSubject()

        XCTAssertEqual(live.text, "")
        XCTAssertFalse(live.hasText)
    }

    func testSubmitAfterIntervalPublishesWithoutFlush() {
        let (live, clock) = makeSubject()

        live.submit("one")
        clock.advance(by: interval)
        live.submit("one two")

        XCTAssertEqual(live.text, "one two")
    }

    func testSubmitAtExactlyIntervalPublishes() {
        let (live, clock) = makeSubject()

        live.submit("a")
        clock.advance(by: .milliseconds(60))
        live.submit("a b")

        XCTAssertEqual(live.text, "a b", "Elapsed == minimumInterval is not 'too soon'")
    }

    // MARK: - Duplicate suppression

    func testIdenticalSubmitDoesNoWork() {
        let (live, clock) = makeSubject()

        live.submit("hello")
        let afterFirst = clock.callCount
        clock.advance(by: .seconds(1))
        live.submit("hello")

        XCTAssertEqual(
            clock.callCount,
            afterFirst,
            "A byte-identical partial must not even reach the clock"
        )
        XCTAssertEqual(live.text, "hello")
    }

    func testRepeatedIdenticalSubmitsCollapse() {
        let (live, clock) = makeSubject()

        live.submit("steady")
        let afterFirst = clock.callCount
        for _ in 0..<50 {
            clock.advance(by: .milliseconds(20))
            live.submit("steady")
        }

        XCTAssertEqual(clock.callCount, afterFirst)
        XCTAssertEqual(live.text, "steady")
    }

    // MARK: - Coalescing

    func testBurstWithinIntervalIsWithheld() {
        let (live, _) = makeSubject()

        live.submit("a")
        live.submit("a b")
        live.submit("a b c")

        XCTAssertEqual(live.text, "a", "Values inside the coalescing window must not publish")
    }

    func testFlushPublishesNewestWithheldValue() {
        let (live, _) = makeSubject()

        live.submit("a")
        live.submit("a b")
        live.submit("a b c")
        live.flush()

        XCTAssertEqual(live.text, "a b c", "The trailing partial must never be lost")
        XCTAssertTrue(live.hasText)
    }

    func testFlushWithNothingPendingIsNoOp() {
        let (live, _) = makeSubject()

        live.submit("a")
        live.flush()
        live.flush()

        XCTAssertEqual(live.text, "a")
    }

    func testFlushOnUntouchedTranscriptIsNoOp() {
        let (live, _) = makeSubject()

        live.flush()

        XCTAssertEqual(live.text, "")
        XCTAssertFalse(live.hasText)
    }

    func testCoalescingWindowRestartsFromEachPublish() {
        let (live, clock) = makeSubject()

        live.submit("a")            // publishes at t0
        clock.advance(by: .milliseconds(60))
        live.submit("a b")          // publishes at t0+60
        clock.advance(by: .milliseconds(30))
        live.submit("a b c")        // only 30 ms since the last publish

        XCTAssertEqual(live.text, "a b")
        live.flush()
        XCTAssertEqual(live.text, "a b c")
    }

    /// The withheld value must reach the UI on its own, without anyone calling
    /// `flush()` — otherwise a speaker who pauses mid-sentence sees stale text.
    func testWithheldValueAutoFlushes() async {
        let live = LiveTranscript(minimumInterval: .milliseconds(30))

        live.submit("a")
        live.submit("a b")

        let arrived = await waitForText("a b", on: live)
        XCTAssertTrue(arrived, "Trailing flush never fired; text was '\(live.text)'")
    }

    // MARK: - hasText

    func testHasTextStaysFalseForEmptySubmission() {
        let (live, _) = makeSubject()

        live.submit("")

        XCTAssertEqual(live.text, "")
        XCTAssertFalse(live.hasText)
    }

    func testHasTextClearsWhenEnginePublishesEmptyString() {
        let (live, clock) = makeSubject()

        live.submit("something")
        XCTAssertTrue(live.hasText)

        clock.advance(by: interval)
        live.submit("")

        XCTAssertEqual(live.text, "")
        XCTAssertFalse(live.hasText)
    }

    // MARK: - Reset

    func testResetClearsPublishedAndPendingState() {
        let (live, _) = makeSubject()

        live.submit("a")
        live.submit("a b")   // withheld
        live.reset()

        XCTAssertEqual(live.text, "")
        XCTAssertFalse(live.hasText)

        live.flush()
        XCTAssertEqual(live.text, "", "reset() must discard the withheld value, not defer it")
    }

    func testResetAllowsTheSameValueToBeSubmittedAgain() {
        let (live, _) = makeSubject()

        live.submit("a")
        live.reset()
        live.submit("a")

        XCTAssertEqual(live.text, "a", "A new dictation may legitimately start with the same words")
        XCTAssertTrue(live.hasText)
    }

    func testResetClearsTheCoalescingWindow() {
        let (live, _) = makeSubject()

        live.submit("first take")
        live.reset()
        live.submit("second take")

        XCTAssertEqual(
            live.text,
            "second take",
            "After reset the next partial must publish immediately, not wait out the old window"
        )
    }

    // MARK: - Helpers

    private func waitForText(
        _ expected: String,
        on live: LiveTranscript,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if live.text == expected { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return live.text == expected
    }
}
