import XCTest
import SwiftData
import AVFoundation
@testable import DailyOps

/// Covers the observable microphone authorization mirror: every native
/// authorization state maps correctly, refresh picks up external changes,
/// and prompting only happens when the user has not yet decided.
@MainActor
final class MicrophonePermissionTests: XCTestCase {
    func testPromptOnlyForUndeterminedAndRechecksBeforeRequest() async {
        var current = AVAuthorizationStatus.notDetermined
        var prompts = 0
        let mirror = MicrophonePermission(statusProvider: { current }, requestAccess: {
            prompts += 1
            current = .authorized
            return true
        })
        let granted = await mirror.requestIfNeeded()
        XCTAssertTrue(granted)
        XCTAssertEqual(prompts, 1)
        for status: AVAuthorizationStatus in [.denied, .restricted, .authorized] {
            current = status
            let result = await mirror.requestIfNeeded()
            XCTAssertEqual(result, status == .authorized)
        }
        XCTAssertEqual(prompts, 1, "Rechecks and settled states must never prompt")
    }

    func testAllAuthorizationStatesMapCorrectly() {
        let authorized = MicrophonePermission(statusProvider: { .authorized })
        let denied = MicrophonePermission(statusProvider: { .denied })
        let undetermined = MicrophonePermission(statusProvider: { .notDetermined })
        let restricted = MicrophonePermission(statusProvider: { .restricted })

        XCTAssertEqual(authorized.status, .authorized)
        XCTAssertEqual(denied.status, .denied)
        XCTAssertEqual(undetermined.status, .notDetermined)
        XCTAssertEqual(restricted.status, .restricted)
    }

    func testRefreshFollowsExternalAuthorizationChange() {
        var current = AVAuthorizationStatus.notDetermined
        let mirror = MicrophonePermission(statusProvider: { current })
        XCTAssertEqual(mirror.status, .notDetermined)

        current = .authorized
        mirror.refresh()
        XCTAssertEqual(mirror.status, .authorized)

        current = .denied
        mirror.refresh()
        XCTAssertEqual(mirror.status, .denied)
    }

    func testRequestWhenDeniedNeverPromptsAndReportsFailure() async {
        var current = AVAuthorizationStatus.denied
        let mirror = MicrophonePermission(statusProvider: { current })
        let granted = await mirror.requestIfNeeded()
        XCTAssertFalse(granted, "Denied state must not silently report success")
        current = .authorized
        mirror.refresh()
        XCTAssertTrue(mirror.status == .authorized)
    }

    func testRestrictedStateIsDistinctFromDenied() {
        let mirror = MicrophonePermission(statusProvider: { .restricted })
        XCTAssertFalse(mirror.status == .authorized)
        XCTAssertNotEqual(mirror.status, .denied)
    }

    func testControllerMicStatusFollowsMirror() {
        var current = AVAuthorizationStatus.denied
        let mirror = MicrophonePermission(statusProvider: { current })
        let controller = DictationController(
            history: Self.inMemoryHistory(),
            microphone: mirror
        )
        XCTAssertFalse(controller.hasMicPermission)
        current = .authorized
        controller.refreshPermissions()
        XCTAssertTrue(controller.hasMicPermission, "Displayed status must follow the live mirror")
        current = .denied
        controller.refreshPermissions()
        XCTAssertFalse(controller.hasMicPermission)
        XCTAssertFalse(controller.hotkeyArmed, "Recheck must not start an unstarted controller")
    }

    private static func inMemoryHistory() -> HistoryStore {
        let container = try! ModelContainer(
            for: DictationEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return HistoryStore(container: container)
    }
}
