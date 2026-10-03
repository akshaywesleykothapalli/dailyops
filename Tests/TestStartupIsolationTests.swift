import XCTest
import SwiftData
@testable import DailyOps

/// Guards test-safe composition: the XCTest host must not register the global
/// hotkey, warm speech models, or perform production startup.
@MainActor
final class TestStartupIsolationTests: XCTestCase {
    func testTestHostIsDetected() {
        XCTAssertTrue(AppStartup.isTestHost, "These tests run inside the XCTest host app")
    }

    func testSharedControllerIsNotStartedInTestHost() {
        // applicationDidFinishLaunching guards production startup with
        // AppStartup.isTestHost; the shared controller must therefore still be
        // idle and unstarted here.
        XCTAssertFalse(DictationController.shared.hasStarted)
    }

    func testCommandHostDoesNotRetainController() throws {
        let container = try ModelContainer(for: DictationEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var controller: DictationController? = DictationController(history: HistoryStore(container: container))
        weak let released = controller
        let host = SystemCommandHost(controller: try XCTUnwrap(controller))
        controller = nil
        XCTAssertNil(released)
        host.copyLastDictation()
    }

    func testControllersConstructibleForTestsRemainIsolated() {
        let container = try! ModelContainer(
            for: DictationEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let controller = DictationController(
            history: HistoryStore(container: container),
            commandEngine: nil
        )
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.hasStarted)
        XCTAssertFalse(controller.hotkeyArmed)
        XCTAssertFalse(controller.recorder.isRecording)
        XCTAssertEqual(controller.sttState, .notLoaded)
    }
}
