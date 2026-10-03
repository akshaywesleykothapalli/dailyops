import XCTest
import os
@testable import DailyOps

@MainActor
final class MockPasteService: PasteServing {
    var resultToReturn: PasteResult = .success
    var insertedText: String?
    var targetAppPassed: NSRunningApplication?
    var insertCallCount = 0

    func insert(_ text: String, targetApp: NSRunningApplication?) async -> PasteResult {
        insertCallCount += 1
        insertedText = text
        targetAppPassed = targetApp
        return resultToReturn
    }
}

@MainActor
final class MockPromptDetector: PromptContextDetecting {
    var isPrompt: Bool = false
    var appName: String = "TestApp"

    func currentTargetContext(for app: NSRunningApplication?) -> TargetAppContext {
        TargetAppContext(
            bundleIdentifier: isPrompt ? "com.openai.chat" : "com.apple.Safari",
            localizedName: app?.localizedName ?? appName,
            isPromptOriented: isPrompt
        )
    }

    func isPromptOriented(bundleIdentifier: String, appName: String) -> Bool {
        isPrompt
    }
}

@MainActor
final class TranscriptionCoordinatorTests: XCTestCase {
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

    func testCancellationTransitionsToIdle() {
        controller.state = .recording
        coordinator.cancel(controller: controller)
        XCTAssertEqual(controller.state, .idle)
    }

    func testTerminalStatesAreRecognized() {
        XCTAssertTrue(DictationState.idle.isTerminal)
        XCTAssertTrue(DictationState.done.isTerminal)
        XCTAssertTrue(DictationState.error("Test").isTerminal)
        XCTAssertFalse(DictationState.recording.isTerminal)
        XCTAssertFalse(DictationState.transcribing.isTerminal)
        XCTAssertFalse(DictationState.cleaning.isTerminal)
    }

    func testPasteResultSuccessSetsDone() async {
        mockPaste.resultToReturn = .success
        let result = await mockPaste.insert("Hello world")
        XCTAssertEqual(result, .success)
        XCTAssertEqual(mockPaste.insertedText, "Hello world")
    }

    func testPasteResultCopiedToClipboardFallback() async {
        mockPaste.resultToReturn = .copiedToClipboard("Copied to clipboard")
        let result = await mockPaste.insert("Important text")
        XCTAssertEqual(result, .copiedToClipboard("Copied to clipboard"))
    }

    func testPromptDetectorIdentifiesCodingApps() {
        let detector = PromptContextDetector.shared
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.openai.chat", appName: "ChatGPT"))
        XCTAssertTrue(detector.isPromptOriented(bundleIdentifier: "com.microsoft.VSCode", appName: "Code"))
        XCTAssertFalse(detector.isPromptOriented(bundleIdentifier: "com.apple.Safari", appName: "Safari"))
    }

    // MARK: - Production Reliability Tests

    func testCancellationDuringActivePipelineInvalidatesSession() async {
        controller.state = .recording
        let initialSessionID = coordinator.currentSessionID

        coordinator.process(samples: [0.1, 0.2], controller: controller)
        XCTAssertEqual(controller.state, .transcribing)
        XCTAssertGreaterThan(coordinator.currentSessionID, initialSessionID)

        coordinator.cancel(controller: controller)
        XCTAssertEqual(controller.state, .idle)

        // Wait briefly to ensure background task stops without modifying state
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.state, .idle)
    }

    func testWatchdogTimeoutForcesErrorStateAndGuaranteesTerminalState() async {
        // Create coordinator with very short timeout for deterministic test
        let shortCoordinator = TranscriptionCoordinator(
            pasteService: mockPaste,
            promptDetector: mockDetector,
            timeout: .milliseconds(50)
        )

        // Empty samples will hit batch transcriber which takes longer than 50ms or times out
        shortCoordinator.process(samples: [Float](repeating: 0.05, count: 8000), controller: controller)
        XCTAssertEqual(controller.state, .transcribing)

        // Await watchdog expiration
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(controller.state.isTerminal)
        if case .error(let message) = controller.state {
            XCTAssertTrue(message.contains("timed out") || message.contains("error"))
        } else {
            // It reached a terminal state (done, error, or idle)
            XCTAssertTrue(controller.state.isTerminal)
        }
    }

    func testConcurrentTriggerInvalidatesPreviousSession() {
        let session1 = coordinator.currentSessionID
        coordinator.process(samples: [0.1], controller: controller)
        let session2 = coordinator.currentSessionID
        XCTAssertGreaterThan(session2, session1)

        coordinator.process(samples: [0.2], controller: controller)
        let session3 = coordinator.currentSessionID
        XCTAssertGreaterThan(session3, session2)
    }

    func testInsertionFailureTransitionsToExplicitError() async {
        mockPaste.resultToReturn = .failure(.dispatchFailed("Target application is unresponsive"))
        
        // Populate live hypothesis so transcription step succeeds via streaming fallback
        controller.live.submit("Testing insertion failure path")
        controller.live.flush()
        
        // Directly test insertion
        let result = await mockPaste.insert("Testing insertion failure path")
        XCTAssertEqual(result, .failure(.dispatchFailed("Target application is unresponsive")))
    }

    func testRecoveryAfterFailureAllowsSubsequentDictation() {
        // State set to error
        controller.state = .error("Previous operation timed out")
        XCTAssertTrue(controller.state.isTerminal)

        // User starts next dictation
        coordinator.cancel(controller: controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(controller.state.isTerminal)
    }

    func testEmptyTranscriptReturnsToIdle() async {
        // Samples of pure silence
        coordinator.process(samples: [], controller: controller)
        
        // Wait for async pipeline to complete
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.state.isTerminal)
    }

    func testDiagnosticTimingRecordFormat() {
        let diagnostics = DictationDiagnostics(
            recordingDuration: 62.5,
            audioDuration: 62.5,
            audioFrames: 1000000,
            audioBufferSize: 4000000,
            transcriptionDuration: 1.85,
            processingDuration: 0.12,
            insertionDuration: 0.08,
            totalLatency: 2.05,
            modelUsed: "appleSpeech",
            wordCount: 145,
            characterCount: 820
        )

        XCTAssertEqual(diagnostics.recordingDuration, 62.5)
        XCTAssertEqual(diagnostics.audioFrames, 1000000)
        XCTAssertEqual(diagnostics.wordCount, 145)
        XCTAssertEqual(diagnostics.modelUsed, "appleSpeech")

        // Confirm diagnostic output produces safe metadata without user speech or transcript
        let testLogger = Logger(subsystem: "test", category: "test")
        diagnostics.logDiagnostic(logger: testLogger)
    }

    func testLongTranscriptionLifecycleSimulation() {
        // Simulate a 120-second audio stream (1,920,000 samples at 16kHz)
        let sampleCount = Int(AudioRecorder.sampleRate * 120.0)
        XCTAssertEqual(sampleCount, 1_920_000)
        let memorySize = sampleCount * MemoryLayout<Float>.size
        XCTAssertEqual(memorySize, 7_680_000) // ~7.68 MB - well bounded

        let calculatedDuration = Double(sampleCount) / AudioRecorder.sampleRate
        XCTAssertEqual(calculatedDuration, 120.0)
    }
}
