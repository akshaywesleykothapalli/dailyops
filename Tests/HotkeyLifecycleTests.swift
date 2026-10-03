import XCTest
import AppKit
import CoreGraphics
import AVFoundation
@testable import DailyOps

@MainActor
final class HotkeyLifecycleTests: XCTestCase {
    func testFirstPressEntersRecordingStateImmediately() {
        let controller = DictationController()
        XCTAssertEqual(controller.state, .idle)

        // Simulate first hotkeyDown
        controller.hotkeyDownForTesting()
        XCTAssertEqual(controller.state, .recording, "First Fn press must transition to .recording immediately so HUD shows up without delay")

        // Cleanup
        controller.cancelPendingForTesting()
    }

    func testAccidentalTapBelowThresholdTransitionsToIdle() async {
        let controller = DictationController()
        controller.hotkeyDownForTesting()
        XCTAssertEqual(controller.state, .recording)

        // Key released under threshold (< 150ms)
        controller.hotkeyUpForTesting(simulatedHoldDuration: .milliseconds(50))
        XCTAssertEqual(controller.state, .idle, "Press under 150ms should be treated as accidental tap and return to .idle")
    }

    func testValidHoldAboveThresholdDoesNotDiscardAccidentalTap() {
        let controller = DictationController()
        controller.hotkeyDownForTesting()
        XCTAssertEqual(controller.state, .recording)

        // Hold >= 150ms is treated as a valid dictation hold (not discarded to .idle)
        controller.hotkeyUpForTesting(simulatedHoldDuration: .milliseconds(300))
        XCTAssertNotEqual(controller.state, .idle, "Press >= 150ms must not be discarded to .idle as an accidental tap")
    }

    func testAudioRecorderPrewarmIsSafeAndIdempotent() {
        let recorder = AudioRecorder()
        // Prewarm before any recording
        recorder.prewarm()
        recorder.prewarm()
        XCTAssertFalse(recorder.isRecording, "Prewarm should prepare engine without setting isRecording to true")
    }

    func testHotkeyChoiceModifierFlagMatches() {
        // Fn key
        XCTAssertTrue(HotkeyChoice.fn.isPressed(in: .maskSecondaryFn))
        XCTAssertFalse(HotkeyChoice.fn.isPressed(in: .maskAlternate))
        XCTAssertTrue(HotkeyChoice.fn.isPressed(in: [.function]))

        // Option keys
        XCTAssertTrue(HotkeyChoice.rightOption.isPressed(in: .maskAlternate))
        XCTAssertTrue(HotkeyChoice.leftOption.isPressed(in: [.option]))

        // Command keys
        XCTAssertTrue(HotkeyChoice.rightCommand.isPressed(in: .maskCommand))
        XCTAssertTrue(HotkeyChoice.leftCommand.isPressed(in: [.command]))

        // Control key
        XCTAssertTrue(HotkeyChoice.control.isPressed(in: .maskControl))
        XCTAssertTrue(HotkeyChoice.control.isPressed(in: [.control]))

        // Shift key
        XCTAssertTrue(HotkeyChoice.shift.isPressed(in: .maskShift))
        XCTAssertTrue(HotkeyChoice.shift.isPressed(in: [.shift]))
    }
}
