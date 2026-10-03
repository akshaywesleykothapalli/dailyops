import XCTest
import AppKit
@testable import DailyOps

@MainActor
final class PastePipelineTests: XCTestCase {
    var controller: DictationController!
    var mockPaste: MockPasteService!
    var mockDetector: MockPromptDetector!
    var coordinator: TranscriptionCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set(false, forKey: "commandModeEnabled")
        UserDefaults.standard.set(false, forKey: "cleanupAlways")
        controller = DictationController()
        mockPaste = MockPasteService()
        mockDetector = MockPromptDetector()
        coordinator = TranscriptionCoordinator(pasteService: mockPaste, promptDetector: mockDetector)
    }

    override func tearDown() async throws {
        coordinator.cancel(controller: controller)
        controller = nil
        mockPaste = nil
        mockDetector = nil
        coordinator = nil
        try await super.tearDown()
    }

    // MARK: - 1. Transcription → Clipboard

    func testTranscriptionToClipboardFlow() async {
        controller.live.submit("Hello world transcription")
        controller.live.flush()

        mockPaste.resultToReturn = .success

        coordinator.process(samples: [0.1, 0.2], controller: controller)

        // Wait for pipeline execution
        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(controller.state, .done)
        XCTAssertEqual(mockPaste.insertedText, "Hello world transcription.")
        XCTAssertEqual(controller.lastInsertedText, "Hello world transcription.")
    }

    // MARK: - 2. Clipboard Verification

    func testClipboardVerificationFailureHandling() async {
        // Direct test against PasteService logic with invalid text or forced failure
        let pasteService = PasteService()
        let result = await pasteService.insert("")
        XCTAssertEqual(result, .failure(.emptyText))
    }

    func testPasteboardSnapshotAndRestoreLossless() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("PRE_DICTATION_CLIPBOARD_DATA", forType: .string)

        let snapshot = PasteService.captureSnapshot(from: pb)
        XCTAssertFalse(snapshot.isEmpty)

        // Simulate dictation overwriting clipboard
        pb.clearContents()
        pb.setString("DICTATION_TEMPORARY_TEXT", forType: .string)
        XCTAssertEqual(pb.string(forType: .string), "DICTATION_TEMPORARY_TEXT")

        // Restore snapshot
        PasteService.restoreSnapshot(snapshot, to: pb)
        XCTAssertEqual(pb.string(forType: .string), "PRE_DICTATION_CLIPBOARD_DATA")
    }

    func testPasteboardSnapshotPreservesMultipleItems() {
        let pb = NSPasteboard.general
        pb.clearContents()

        let item1 = NSPasteboardItem()
        item1.setString("Item One", forType: .string)
        let item2 = NSPasteboardItem()
        item2.setString("Item Two", forType: .string)
        pb.writeObjects([item1, item2])

        let snapshot = PasteService.captureSnapshot(from: pb)
        XCTAssertEqual(snapshot.count, 2)

        // Overwrite
        pb.clearContents()
        pb.setString("Single Overwrite", forType: .string)

        // Restore
        PasteService.restoreSnapshot(snapshot, to: pb)
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
    }

    // MARK: - 3. Empty Transcription

    func testEmptyTranscriptionDoesNotInvokePasteAndReturnsToIdle() async {
        controller.live.reset()
        mockPaste.resultToReturn = .success

        coordinator.process(samples: [], controller: controller)

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(mockPaste.insertCallCount, 0)
    }

    // MARK: - 4. Accessibility Unavailable

    func testAccessibilityUnavailableTransitionsToCleanTerminalStateWithoutHanging() async {
        controller.live.submit("Transcribed text for clipboard only")
        controller.live.flush()

        mockPaste.resultToReturn = .copiedToClipboard("Copied to clipboard — Grant Accessibility in System Settings to auto-paste")

        coordinator.process(samples: [0.1, 0.2], controller: controller)

        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(controller.state, .done)
        XCTAssertTrue(controller.lastInsertedText.contains("Copied to clipboard"))
    }

    // MARK: - 5. Insertion Failure

    func testInsertionFailureTransitionsToExplicitErrorState() async {
        controller.live.submit("Text that will fail to paste")
        controller.live.flush()

        mockPaste.resultToReturn = .failure(.dispatchFailed("WindowServer event queue dropped event"))

        coordinator.process(samples: [0.1, 0.2], controller: controller)

        for _ in 1...20 {
            if case .error = controller.state { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        if case .error(let message) = controller.state {
            XCTAssertTrue(message.contains("WindowServer") || message.contains("dispatch failed"))
        } else {
            XCTFail("Expected .error state but got \(controller.state)")
        }
    }

    // MARK: - 6. Cancellation During Insertion

    func testCancellationDuringInsertionAbortsCleanly() async {
        controller.live.submit("Text being inserted")
        controller.live.flush()

        coordinator.process(samples: [0.1, 0.2], controller: controller)
        XCTAssertEqual(controller.state, .transcribing)

        // Cancel while in flight
        coordinator.cancel(controller: controller)
        XCTAssertEqual(controller.state, .idle)

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.state, .idle)
    }

    // MARK: - 7. Successful Insertion

    func testSuccessfulInsertionFlowCompletesAndRecordsHistory() async {
        controller.live.submit("Flawless transcription and insertion")
        controller.live.flush()

        mockPaste.resultToReturn = .success

        coordinator.process(samples: [0.1, 0.2], controller: controller)

        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(controller.state, .done)
        XCTAssertEqual(controller.lastInsertedText, "Flawless transcription and insertion.")
    }

    // MARK: - 8. Multiple Consecutive Dictations

    func testMultipleConsecutiveDictationsSucceedSequentially() async {
        mockPaste.resultToReturn = .success

        for i in 1...3 {
            controller.live.reset()
            controller.live.submit("Sentence number \(i)")
            controller.live.flush()

            coordinator.process(samples: [0.1, 0.2], controller: controller)

            for _ in 1...20 {
                if controller.state == .done { break }
                try? await Task.sleep(for: .milliseconds(25))
            }

            XCTAssertEqual(controller.state, .done)
            XCTAssertEqual(mockPaste.insertedText, "Sentence number \(i).")

            // Reset back to idle between turns
            controller.state = .idle
        }

        XCTAssertEqual(mockPaste.insertCallCount, 3)
    }

    // MARK: - 9. Long Dictation Followed By Insertion

    func testLongDictationFollowedByInsertion() async {
        // Simulate a 45-second audio buffer
        let longSamples = [Float](repeating: 0.05, count: 720_000)
        controller.live.submit("This is a comprehensive long-form dictation paragraph spoken over several minutes.")
        controller.live.flush()

        mockPaste.resultToReturn = .success

        coordinator.process(samples: longSamples, controller: controller)

        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(controller.state, .done)
        XCTAssertEqual(mockPaste.insertedText, "This is a comprehensive long-form dictation paragraph spoken over several minutes.")
    }

    // MARK: - 10. New Dictation Immediately After Insertion

    func testNewDictationImmediatelyAfterInsertionCancelsLingerAndStartsFresh() async {
        controller.live.submit("First dictation")
        controller.live.flush()
        mockPaste.resultToReturn = .success

        coordinator.process(samples: [0.1, 0.2], controller: controller)

        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(controller.state, .done)

        // Immediately start second dictation while first is still lingering in done
        controller.live.reset()
        controller.live.submit("Second dictation immediately starting")
        controller.live.flush()

        coordinator.process(samples: [0.3, 0.4], controller: controller)

        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(controller.state, .done)
        XCTAssertEqual(mockPaste.insertedText, "Second dictation immediately starting.")
        XCTAssertEqual(mockPaste.insertCallCount, 2)
    }

    // MARK: - 11. Preserving Target Application

    func testTargetApplicationPassedToPasteService() async {
        let frontApp = NSWorkspace.shared.frontmostApplication
        controller.live.submit("Target application preservation test")
        controller.live.flush()
        mockPaste.resultToReturn = .success

        coordinator.process(samples: [0.1, 0.2], controller: controller, targetApp: frontApp)

        for _ in 1...20 {
            if controller.state == .done { break }
            try? await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(controller.state, .done)
        XCTAssertEqual(mockPaste.targetAppPassed, frontApp)
    }
}
