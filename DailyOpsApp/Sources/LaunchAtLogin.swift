import Foundation
import Observation
import os
import ServiceManagement

private let loginLog = Logger(subsystem: AppBrand.bundleIdentifier, category: "loginItem")

/// Observable wrapper around the native `SMAppService` login item.
/// The Settings toggle binds to the real service status, and registration or
/// unregistration failures surface as `lastErrorMessage` instead of being
/// silently swallowed. All operations stay inside SMAppService — no launchctl,
/// shell scripts or plist edits.
@MainActor
@Observable
final class LaunchAtLoginManager {
    private(set) var status: SMAppService.Status
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private let readStatus: () -> SMAppService.Status
    @ObservationIgnored private let performRegister: () throws -> Void
    @ObservationIgnored private let performUnregister: () throws -> Void

    /// - Parameters: real `SMAppService.mainApp` by default; injectable so
    ///   tests can exercise success, failure and approval states without
    ///   touching the user's actual login items.
    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        self.readStatus = readStatus
        self.performRegister = register
        self.performUnregister = unregister
        self.status = readStatus()
    }

    var isEnabled: Bool { status == .enabled }

    /// The user must approve the login item in System Settings before it
    /// becomes enabled; the UI should point there rather than claim success.
    var requiresApproval: Bool { status == .requiresApproval }

    /// Re-reads the actual service state, e.g. after the user approves in
    /// System Settings → General → Login Items, or removes the item there.
    func refresh() {
        status = readStatus()
    }

    /// Attempts the requested change and then always adopts the service's
    /// real status, so the toggle never reports success the system disagrees with.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try performRegister()
            } else {
                try performUnregister()
            }
            lastErrorMessage = nil
        } catch {
            let message = Self.errorMessage(for: error, operation: enabled ? "enable" : "disable")
            loginLog.error("Login item update failed: \(message, privacy: .public)")
            lastErrorMessage = message
        }
        status = readStatus()
    }

    static func errorMessage(for error: Error, operation: String) -> String {
        "Could not \(operation) Launch at Login: \(error.localizedDescription)"
    }
}
