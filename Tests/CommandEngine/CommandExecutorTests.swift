import XCTest
@testable import DailyOps

/// Executors are checked against fakes only. Nothing in this file may launch,
/// quit or hide a real application, or touch the pasteboard.
@MainActor
final class CommandExecutorTests: XCTestCase {

    // MARK: - Applications

    func testOpenLaunchesTheResolvedApplication() throws {
        let control = FakeApplicationControl()
        let executor = ApplicationCommandExecutor(control: control)
        let reference = ApplicationReference(displayName: "Calculator")

        let feedback = try executor.execute(
            CommandIntent(identifier: .appOpen, arguments: .application(reference)),
            context: .test()
        )

        XCTAssertEqual(feedback, "Opened Calculator")
        XCTAssertEqual(control.launched, [reference])
        XCTAssertTrue(control.quit.isEmpty)
        XCTAssertTrue(control.hidden.isEmpty)
    }

    func testQuitAndHideRouteToTheirOwnOperations() throws {
        let control = FakeApplicationControl()
        let executor = ApplicationCommandExecutor(control: control)
        let reference = ApplicationReference(displayName: "Safari")

        let quitFeedback = try executor.execute(
            CommandIntent(identifier: .appQuit, arguments: .application(reference)),
            context: .test()
        )
        let hideFeedback = try executor.execute(
            CommandIntent(identifier: .appHide, arguments: .application(reference)),
            context: .test()
        )

        XCTAssertEqual(quitFeedback, "Quit Safari")
        XCTAssertEqual(hideFeedback, "Hidden Safari")
        XCTAssertEqual(control.quit, [reference])
        XCTAssertEqual(control.hidden, [reference])
        XCTAssertTrue(control.launched.isEmpty)
    }

    func testApplicationExecutorRejectsMissingArguments() {
        let executor = ApplicationCommandExecutor(control: FakeApplicationControl())
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .appOpen), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .malformedArguments(.appOpen))
        }
    }

    func testApplicationExecutorSurfacesControlFailures() {
        let control = FakeApplicationControl()
        control.errorToThrow = .operationFailed("Safari is not running.")
        let executor = ApplicationCommandExecutor(control: control)
        let intent = CommandIntent(
            identifier: .appQuit,
            arguments: .application(ApplicationReference(displayName: "Safari"))
        )

        XCTAssertThrowsError(try executor.execute(intent, context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Safari is not running."))
        }
    }

    func testApplicationExecutorClaimsOnlyApplicationCommands() {
        let executor = ApplicationCommandExecutor(control: FakeApplicationControl())
        XCTAssertEqual(executor.supportedIdentifiers, [.appOpen, .appQuit, .appHide, .appSwitch])
    }

    // MARK: - Navigation

    func testNavigationExecutorShowsSettingsAndHistory() throws {
        let host = FakeCommandHost()
        let executor = NavigationCommandExecutor(host: host)

        let settings = try executor.execute(CommandIntent(identifier: .settingsOpen), context: .test())
        let history = try executor.execute(CommandIntent(identifier: .historyOpen), context: .test())

        XCTAssertEqual(settings, "Opened Settings")
        XCTAssertEqual(history, "Opened History")
        XCTAssertEqual(host.calls, ["showSettings", "showHistory"])
    }

    // MARK: - Dictation and clipboard

    func testDictationExecutorHandlesClipboardAndModel() throws {
        let host = FakeCommandHost()
        let executor = DictationCommandExecutor(host: host)

        let copied = try executor.execute(CommandIntent(identifier: .clipboardCopyLast), context: .test())
        let cleared = try executor.execute(CommandIntent(identifier: .clipboardClear), context: .test())
        let reloaded = try executor.execute(CommandIntent(identifier: .speechModelReload), context: .test())

        XCTAssertEqual(copied, "Copied Last Dictation")
        XCTAssertEqual(cleared, "Cleared Clipboard")
        XCTAssertEqual(reloaded, "Reloading Speech Model")
        XCTAssertEqual(host.calls, ["copyLastDictation", "clearClipboard", "reloadSpeechModel"])
    }

    func testDictationExecutorSwitchesWritingMode() throws {
        let host = FakeCommandHost()
        let executor = DictationCommandExecutor(host: host)

        let formal = try executor.execute(
            CommandIntent(identifier: .dictationModeFormal, arguments: .writingMode(.formal)),
            context: .test()
        )
        let standard = try executor.execute(
            CommandIntent(identifier: .dictationModeStandard, arguments: .writingMode(.standard)),
            context: .test()
        )

        XCTAssertEqual(formal, "Switched to Formal Mode")
        XCTAssertEqual(standard, "Switched to Standard Mode")
        XCTAssertEqual(host.writingModes, [.formal, .standard])
    }

    func testWritingModeCommandRejectsMissingMode() {
        let executor = DictationCommandExecutor(host: FakeCommandHost())
        let intent = CommandIntent(identifier: .dictationModeFormal)
        XCTAssertThrowsError(try executor.execute(intent, context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .malformedArguments(.dictationModeFormal))
        }
    }

    /// Every shipped command must be claimed by exactly one executor, or the
    /// router would report it unavailable at runtime.
    func testShippedCommandsAreCoveredByExactlyOneExecutor() {
        let executors: [CommandExecuting] = [
            ApplicationCommandExecutor(control: FakeApplicationControl()),
            NavigationCommandExecutor(host: FakeCommandHost()),
            DictationCommandExecutor(host: FakeCommandHost()),
            BrowserCommandExecutor(control: FakeBrowserControl()),
            WhatsAppCommandExecutor(control: FakeWhatsAppControl()),
            CalendarCommandExecutor(control: FakeCalendarControl()),
            RemindersCommandExecutor(control: FakeRemindersControl()),
            NotesCommandExecutor(control: FakeNotesControl()),
            FinderCommandExecutor(control: FakeFinderControl()),
            ContextCommandExecutor(control: FakeContextControl()),
            ContactsCommandExecutor(control: FakeContactsControl()),
            MailCommandExecutor(control: FakeMailControl()),
            ClipboardCommandExecutor(control: FakeClipboardControl()),
            SystemInformationCommandExecutor(control: FakeSystemInformationControl()),
            SystemAudioCommandExecutor(control: FakeSystemAudioControl()),
            SystemPowerCommandExecutor(control: FakeSystemPowerControl()),
        ]
        for identifier in CommandRegistry.standard().registeredIdentifiers {
            let claiming = executors.filter { $0.supportedIdentifiers.contains(identifier) }
            XCTAssertEqual(claiming.count, 1, "\(identifier.rawValue) claimed by \(claiming.count) executors")
        }
    }
}
