import AVFoundation
import Foundation
import Observation

/// Observable mirror of the system microphone authorization state.
/// Reads state only — it never triggers the system permission prompt itself.
/// `refresh()` re-reads `AVCaptureDevice.authorizationStatus` so the UI can
/// follow changes made in System Settings without restarting the app.
@MainActor
@Observable
final class MicrophonePermission {
    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    private(set) var status: AuthorizationStatus
    @ObservationIgnored private let statusProvider: () -> AVAuthorizationStatus
    @ObservationIgnored private let requestAccess: () async -> Bool

    var statusDescription: String {
        switch status {
        case .authorized: "Allowed"
        case .denied: "Denied — enable in System Settings → Privacy & Security → Microphone"
        case .restricted: "Restricted by system policy"
        case .notDetermined: "Not yet requested"
        }
    }

    /// - Parameter statusProvider: Native status source by default; injectable
    ///   so tests can exercise every authorization state without TCC.
    init(statusProvider: @escaping () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }, requestAccess: @escaping () async -> Bool = {
        await AVCaptureDevice.requestAccess(for: .audio)
    }) {
        self.requestAccess = requestAccess
        self.statusProvider = statusProvider
        status = Self.map(statusProvider())
    }

    /// Re-reads the native authorization state without prompting.
    func refresh() {
        status = Self.map(statusProvider())
    }

    /// Prompts only when the user has not yet decided; otherwise reports the
    /// current state without a prompt. Returns true only when authorized.
    @discardableResult
    func requestIfNeeded() async -> Bool {
        refresh()
        switch status {
        case .notDetermined:
            _ = await requestAccess()
            refresh()
            return status == .authorized
        case .restricted, .denied, .authorized:
            return status == .authorized
        }
    }

    private static func map(_ native: AVAuthorizationStatus) -> AuthorizationStatus {
        switch native {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
