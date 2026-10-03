import AppKit

/// Binds the host protocol to the live dictation controller and main window.
/// Every method here is one of the operations the app already performed for
/// these commands; nothing new is reachable through the engine.
@MainActor
struct SystemCommandHost: CommandHosting {
    private weak var controller: DictationController?

    init(controller: DictationController) {
        self.controller = controller
    }

    func showSettings() {
        guard let controller else { return }
        MainWindow.show(controller: controller, selectedTab: .general)
    }

    func showHistory() {
        guard let controller else { return }
        MainWindow.show(controller: controller, selectedTab: .dictation)
    }

    func copyLastDictation() {
        controller?.copyLastInsertedText()
    }

    func clearClipboard() {
        NSPasteboard.general.clearContents()
    }

    func reloadSpeechModel() {
        controller?.reloadModel()
    }

    func setWritingMode(_ mode: WritingMode) {
        controller?.writingMode = mode
    }
}

/// Application control through `NSWorkspace` and `NSRunningApplication`.
/// Resolution is delegated to the resolver that produced the reference, so the
/// process a quit acts on is the one the parser actually matched.
@MainActor
struct SystemApplicationControl: ApplicationControlling {
    private let resolver: SystemApplicationResolver

    init(resolver: SystemApplicationResolver) {
        self.resolver = resolver
    }

    func launch(_ reference: ApplicationReference) throws {
        guard let url = reference.bundleURL else {
            throw CommandExecutionError.operationFailed("\(reference.displayName) could not be found.")
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func activate(_ reference: ApplicationReference) throws {
        if let app = resolver.process(for: reference) {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
            return
        }
        try launch(reference)
    }

    // `terminate()` and `hide()` report whether the request was accepted. A
    // refusal is surfaced rather than reported as success, because the user
    // would otherwise be told an application quit while it is still open.
    func quit(_ reference: ApplicationReference) throws {
        let app = try process(for: reference)
        guard app.terminate() else {
            throw CommandExecutionError.operationFailed("\(reference.displayName) would not quit.")
        }
    }

    func hide(_ reference: ApplicationReference) throws {
        let app = try process(for: reference)
        guard app.hide() else {
            throw CommandExecutionError.operationFailed("\(reference.displayName) would not hide.")
        }
    }

    /// A running process for the reference, or a failure the user can act on.
    /// The application can exit between parsing and execution, so this is a
    /// real case rather than a defensive check.
    private func process(for reference: ApplicationReference) throws -> NSRunningApplication {
        guard let app = resolver.process(for: reference) else {
            throw CommandExecutionError.operationFailed("\(reference.displayName) is not running.")
        }
        return app
    }
}
