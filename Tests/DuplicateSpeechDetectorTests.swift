import XCTest
@testable import DailyOps

final class DuplicateSpeechDetectorTests: XCTestCase {
    func testDeduplicatesIdenticalAdjacentSentences() {
        let input = "Create a SwiftUI settings view. Create a SwiftUI settings view."
        let result = DuplicateSpeechDetector.process(input, mode: .conservative)
        XCTAssertEqual(result, "Create a SwiftUI settings view.")
    }

    func testDeduplicatesWithDifferentPunctuationAndCasing() {
        let input = "open settings. Open Settings!"
        let result = DuplicateSpeechDetector.process(input, mode: .conservative)
        XCTAssertEqual(result, "open settings.")
    }

    func testPreservesIntentionalRepetition() {
        let input = "Repeat after me: hello world. Repeat after me: hello world."
        let result = DuplicateSpeechDetector.process(input, mode: .conservative)
        XCTAssertEqual(result, input)
    }

    func testOffModePreservesAllText() {
        let input = "hello world. hello world."
        let result = DuplicateSpeechDetector.process(input, mode: .off)
        XCTAssertEqual(result, input)
    }

    func testAutomaticModeDeduplicatesNearIdenticalPhrases() {
        let input = "Please create a new swift file. Please create a swift file."
        let result = DuplicateSpeechDetector.process(input, mode: .automatic)
        XCTAssertEqual(result, "Please create a new swift file.")
    }

    func testPreservesDistinctSentences() {
        let input = "Open Xcode. Now build the application."
        let result = DuplicateSpeechDetector.process(input, mode: .conservative)
        XCTAssertEqual(result, input)
    }

    func testNormalizationStripsPunctuationAndWhitespace() {
        let norm1 = DuplicateSpeechDetector.normalizeForComparison("Hello, World!")
        let norm2 = DuplicateSpeechDetector.normalizeForComparison("hello   world")
        XCTAssertEqual(norm1, norm2)
    }
}
