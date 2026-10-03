import XCTest
import ServiceManagement
@testable import DailyOps

/// Covers the observable SMAppService login-item wrapper: real status wins,
/// failures surface instead of being swallowed, and success never lies about
/// the service state.
@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private func makeManager(
        initial: SMAppService.Status,
        register: @escaping () throws -> Void = {},
        unregister: @escaping () throws -> Void = {}
    ) -> LaunchAtLoginManager {
        var current = initial
        return LaunchAtLoginManager(
            readStatus: { current },
            register: {
                try register()
                current = .enabled
            },
            unregister: {
                try unregister()
                current = .notRegistered
            }
        )
    }

    func testInitialStatusReflectsRealService() {
        let manager = makeManager(initial: .enabled)
        XCTAssertTrue(manager.isEnabled)
        let manager2 = makeManager(initial: .notRegistered)
        XCTAssertFalse(manager2.isEnabled)
    }

    func testFailedRegisterSurfacesErrorAndKeepsDisabled() {
        let manager = makeManager(
            initial: .notRegistered,
            register: { throw NSError(domain: "test", code: 1) }
        )
        manager.setEnabled(true)
        XCTAssertFalse(manager.isEnabled, "Failed registration must not claim success")
        XCTAssertNotNil(manager.lastErrorMessage)
        XCTAssertTrue(manager.lastErrorMessage?.contains("enable") == true)
    }

    func testFailedUnregisterSurfacesErrorAndKeepsEnabled() {
        let manager = makeManager(
            initial: .enabled,
            unregister: { throw NSError(domain: "test", code: 2) }
        )
        manager.setEnabled(false)
        XCTAssertTrue(manager.isEnabled, "Failed unregistration must leave the item enabled")
        XCTAssertNotNil(manager.lastErrorMessage)
        XCTAssertTrue(manager.lastErrorMessage?.contains("disable") == true)
    }

    func testSuccessfulRegisterAndUnregisterClearErrors() {
        let manager = makeManager(initial: .notRegistered)
        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertNil(manager.lastErrorMessage)
        manager.setEnabled(false)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testRequiresApprovalStateIsExposed() {
        let manager = makeManager(initial: .requiresApproval)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(manager.requiresApproval)
    }

    func testRegistrationRequiringApprovalDoesNotClaimEnabled() {
        var current = SMAppService.Status.notRegistered
        let manager = LaunchAtLoginManager(readStatus: { current }, register: {
            current = .requiresApproval
        }, unregister: { current = .notRegistered })
        manager.setEnabled(true)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(manager.requiresApproval)
        current = .enabled
        manager.refresh()
        XCTAssertTrue(manager.isEnabled)
        manager.setEnabled(false)
        XCTAssertEqual(manager.status, .notRegistered)
    }

    func testFailedRegistrationCanBeRetriedAndClearsError() {
        var fail = true
        let manager = makeManager(initial: .notRegistered, register: {
            if fail { throw NSError(domain: "test", code: 3) }
        })
        manager.setEnabled(true)
        XCTAssertNotNil(manager.lastErrorMessage)
        fail = false
        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testRefreshAdoptsActualServiceState() {
        var current = SMAppService.Status.notRegistered
        let manager = LaunchAtLoginManager(readStatus: { current }, register: {}, unregister: {})
        current = .enabled
        manager.refresh()
        XCTAssertTrue(manager.isEnabled)
    }
}
