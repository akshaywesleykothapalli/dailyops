import Foundation

/// The app-level actions commands are allowed to trigger. Deliberately a fixed
/// list of named operations rather than anything general-purpose: an executor
/// can only do what appears here, so widening the engine's reach into the app
/// requires adding a method and is visible in review.
@MainActor
protocol CommandHosting {
    func showSettings()
    func showHistory()
    func copyLastDictation()
    func clearClipboard()
    func reloadSpeechModel()
    func setWritingMode(_ mode: WritingMode)
}

/// Application control, kept separate from the host so launching and quitting
/// can be faked in tests without standing in for the whole app.
@MainActor
protocol ApplicationControlling {
    /// Throws `CommandExecutionError.operationFailed` when the reference has no
    /// bundle to launch.
    func launch(_ reference: ApplicationReference) throws
    /// Activates and switches to the running application, or launches it if not running.
    func activate(_ reference: ApplicationReference) throws
    /// Throws when the application is no longer running.
    func quit(_ reference: ApplicationReference) throws
    func hide(_ reference: ApplicationReference) throws
}
