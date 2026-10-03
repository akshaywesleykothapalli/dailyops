import XCTest
@testable import DailyOps

@MainActor
final class PromptContextDetectorTests: XCTestCase {
    func testRecognizesDeveloperToolsAndAIApps() {
        let detector = PromptContextDetector.shared

        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.openai.chat", appName: "ChatGPT"))
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.anthropic.claude", appName: "Claude"))
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.todesktop.230313mzl4w4u92", appName: "Cursor"))
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.microsoft.VSCode", appName: "Code"))
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.apple.Terminal", appName: "Terminal"))
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.apple.dt.Xcode", appName: "Xcode"))
    }

    func testRejectsStandardProductivityApps() {
        let detector = PromptContextDetector.shared

        XCTAssertFalse(detector.isPromptOriented(bundleIdentifier: "com.apple.Safari", appName: "Safari"))
        XCTAssertFalse(detector.isPromptOriented(bundleIdentifier: "com.apple.mail", appName: "Mail"))
        XCTAssertFalse(detector.isPromptOriented(bundleIdentifier: "com.apple.Notes", appName: "Notes"))
        XCTAssertFalse(detector.isPromptOriented(bundleIdentifier: "com.apple.finder", appName: "Finder"))
    }

    func testPromptInputProcessorPreservesCodeStructures() {
        let input = "write a function calculate total with parameter x and y"
        let output = PromptInputProcessor.processPromptText(input)
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("calculate"))
    }
}
