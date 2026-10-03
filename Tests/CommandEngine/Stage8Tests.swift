import XCTest
import SwiftData
@testable import DailyOps

@MainActor
final class Stage8Tests: XCTestCase {

    // MARK: - 1. Command History Tagging Tests

    func testDictationEntryDefaultValues() {
        let entry = DictationEntry(
            raw: "Hello world",
            cleaned: "Hello world.",
            duration: 2.0,
            appName: "TextEdit"
        )

        XCTAssertFalse(entry.isCommand, "Default isCommand must be false for normal dictations")
        XCTAssertNil(entry.commandSummary, "Default commandSummary must be nil for normal dictations")
        XCTAssertEqual(entry.raw, "Hello world")
        XCTAssertEqual(entry.cleaned, "Hello world.")
        XCTAssertEqual(entry.appName, "TextEdit")
        XCTAssertEqual(entry.duration, 2.0)
    }

    func testRecordCommandInHistoryStore() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationEntry.self, configurations: config)
        let store = HistoryStore(container: container)

        store.recordCommand(
            spoken: "open safari",
            summary: "Opened Safari",
            appName: "Finder"
        )

        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try store.container.mainContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 1)
        let commandEntry = try XCTUnwrap(entries.first)
        XCTAssertTrue(commandEntry.isCommand, "Entry recorded via recordCommand must have isCommand == true")
        XCTAssertEqual(commandEntry.commandSummary, "Opened Safari")
        XCTAssertEqual(commandEntry.raw, "open safari")
        XCTAssertEqual(commandEntry.cleaned, "Opened Safari")
        XCTAssertEqual(commandEntry.appName, "Finder")
        XCTAssertEqual(commandEntry.duration, 0, "Voice commands should record duration == 0")
    }

    func testHistoryStoreMixedDictationAndCommandEntries() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationEntry.self, configurations: config)
        let store = HistoryStore(container: container)

        store.record(raw: "dictation one", cleaned: "Dictation one.", duration: 3.5, appName: "Notes")
        store.recordCommand(spoken: "clear clipboard", summary: "Clipboard cleared", appName: "Notes")

        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try store.container.mainContext.fetch(descriptor)

        XCTAssertEqual(entries.count, 2)
        let dictation = entries.first(where: { !$0.isCommand })
        let command = entries.first(where: { $0.isCommand })

        XCTAssertNotNil(dictation)
        XCTAssertNil(dictation?.commandSummary)
        XCTAssertEqual(dictation?.duration, 3.5)

        XCTAssertNotNil(command)
        XCTAssertEqual(command?.commandSummary, "Clipboard cleared")
        XCTAssertEqual(command?.duration, 0)
    }

    // MARK: - 2. Browser Qualifier Suffix Normalization Tests

    func testBrowserQualifierSuffixStripping() {
        let resolver = FakeApplicationResolver(installed: [])
        let parser = DeterministicCommandParser(applications: resolver)

        let cases = [
            "open YouTube in my browser",
            "open YouTube in the browser",
            "open YouTube in my default browser",
            "open YouTube on my browser",
            "open YouTube in browser",
            "open YouTube in a browser",
            "go to github.com in my browser",
            "visit wikipedia.org in the browser"
        ]

        for input in cases {
            let plan = parser.parse(input, context: .test())
            XCTAssertNotNil(plan, "Should parse '\(input)' as a browser command")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenURL, "Expected browserOpenURL for '\(input)'")

            if case .url(let url) = plan?.steps.first?.intent.arguments {
                XCTAssertTrue(
                    url.absoluteString.contains("youtube") ||
                    url.absoluteString.contains("github") ||
                    url.absoluteString.contains("wikipedia"),
                    "URL for '\(input)' should resolve to correct host, got \(url.absoluteString)"
                )
            } else {
                XCTFail("Arguments must be .url for '\(input)'")
            }
        }
    }

    // MARK: - 3. CommandConfirmationBar Icon Mapping Tests

    func testConfirmationBarIconMappings() {
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .calendarCreateEvent), "calendar.badge.plus")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .calendarListEvents), "calendar.badge.plus")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .calendarOpen), "calendar.badge.plus")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .remindersCreate), "checklist")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .remindersList), "checklist")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .remindersOpen), "checklist")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .notesCreate), "note.text.badge.plus")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .notesOpen), "note.text.badge.plus")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .finderOpenLocation), "folder.fill")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .finderFindFiles), "folder.fill")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .browserOpenPrivate), "lock.shield.fill")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .browserOpenURL), "globe")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .browserSearch), "globe")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .browserOpenDefault), "globe")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .whatsAppSendMessage), "message.fill")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .whatsAppOpenChat), "message")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .appQuit), "xmark.circle.fill")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .appOpen), "app.badge")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .appSwitch), "app.badge")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .appHide), "eye.slash.fill")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: .clipboardClear), "trash.fill")
        XCTAssertEqual(CommandConfirmationBar.iconName(for: .clipboardCopyLast), "doc.on.doc.fill")

        XCTAssertEqual(CommandConfirmationBar.iconName(for: nil), "questionmark.circle.fill")
    }

    // MARK: - 4. Reminders Command Executor Error Message Tests

    func testRemindersCreateErrorContainsHelpfulMessage() {
        let fake = FakeRemindersControl()
        fake.shouldFailWithAccessDenied = true
        let executor = RemindersCommandExecutor(control: fake)
        let intent = CommandIntent(
            identifier: .remindersCreate,
            arguments: .reminder(ReminderRequest(title: "Buy milk"))
        )

        XCTAssertThrowsError(try executor.execute(intent, context: .test())) { error in
            guard case let CommandExecutionError.operationFailed(message) = error else {
                XCTFail("Expected CommandExecutionError.operationFailed, got \(error)")
                return
            }
            XCTAssertEqual(message, "Reminders access is required to create reminders.")
        }
    }

    // MARK: - 5. Deterministic Non-Regression Tests

    func testDeterministicCommandParserExactMatchesUnchanged() {
        let resolver = FakeApplicationResolver(installed: ["Safari", "Slack"], running: ["Slack"])
        let parser = DeterministicCommandParser(applications: resolver)

        let clearPlan = parser.parse("clear clipboard", context: .test())
        XCTAssertEqual(clearPlan?.steps.first?.intent.identifier, .clipboardClear)

        let copyPlan = parser.parse("copy last dictation", context: .test())
        XCTAssertEqual(copyPlan?.steps.first?.intent.identifier, .clipboardCopyLast)

        let safariPlan = parser.parse("open safari", context: .test())
        XCTAssertEqual(safariPlan?.steps.first?.intent.identifier, .appOpen)

        let quitPlan = parser.parse("quit slack", context: .test())
        XCTAssertEqual(quitPlan?.steps.first?.intent.identifier, .appQuit)
    }
}
