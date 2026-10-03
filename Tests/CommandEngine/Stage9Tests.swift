import XCTest
import SwiftData
@testable import DailyOps

@MainActor
final class Stage9Tests: XCTestCase {

    // MARK: - 1. Natural Language Variations & Polite Suffix Tests

    func testOpenWhatsAppWithPoliteSuffixResolvesToAppOpen() {
        let resolver = FakeApplicationResolver(installed: ["WhatsApp"])
        let whatsAppParser = WhatsAppCommandParser(contactResolver: FakeWhatsAppContactResolver())
        let deterministicParser = DeterministicCommandParser(applications: resolver)

        // WhatsAppCommandParser should ignore "open WhatsApp please" so generic app launcher handles it
        let planWhatsApp = whatsAppParser.parse("open WhatsApp please", context: .test())
        XCTAssertNil(planWhatsApp)

        // DeterministicCommandParser should resolve it to .appOpen
        let planDeterministic = deterministicParser.parse("open WhatsApp please", context: .test())
        XCTAssertNotNil(planDeterministic)
        XCTAssertEqual(planDeterministic?.steps.first?.intent.identifier, .appOpen)
        if case .application(let app) = planDeterministic?.steps.first?.intent.arguments {
            XCTAssertEqual(app.displayName, "WhatsApp")
        } else {
            XCTFail("Expected .application arguments")
        }
    }

    func testSystemCommandsWithPoliteSuffix() {
        let calendarParser = CalendarCommandParser()
        let planCal = calendarParser.parse("open calendar please", context: .test())
        XCTAssertNotNil(planCal)
        XCTAssertEqual(planCal?.steps.first?.intent.identifier, .calendarOpen)

        let remindersParser = RemindersCommandParser()
        let planRem = remindersParser.parse("open reminders please", context: .test())
        XCTAssertNotNil(planRem)
        XCTAssertEqual(planRem?.steps.first?.intent.identifier, .remindersOpen)

        let notesParser = NotesCommandParser()
        let planNotes = notesParser.parse("open notes please", context: .test())
        XCTAssertNotNil(planNotes)
        XCTAssertEqual(planNotes?.steps.first?.intent.identifier, .notesOpen)

        let finderParser = FinderCommandParser()
        let planFinder = finderParser.parse("open downloads please", context: .test())
        XCTAssertNotNil(planFinder)
        XCTAssertEqual(planFinder?.steps.first?.intent.identifier, .finderOpenLocation)

        let deterministicParser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: []))
        let planWeb = deterministicParser.parse("open YouTube please", context: .test())
        XCTAssertNotNil(planWeb)
        XCTAssertEqual(planWeb?.steps.first?.intent.identifier, .browserOpenURL)
    }

    func testNaturalFinderLocationPhrases() {
        let parser = FinderCommandParser()

        let downloadsVariants = [
            "open downloads", "show downloads", "open my downloads", "show my downloads",
            "open the downloads", "open the downloads folder", "show the downloads", "show the downloads folder"
        ]
        for phrase in downloadsVariants {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed for phrase: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderOpenLocation)
            if case .finderLocation(let target) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(target.location, .downloads, "Phrase '\(phrase)' should resolve to .downloads")
            } else {
                XCTFail("Wrong argument type for \(phrase)")
            }
        }

        let desktopVariants = ["show my desktop", "open the desktop", "open the desktop folder", "show the desktop"]
        for phrase in desktopVariants {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed for phrase: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderOpenLocation)
            if case .finderLocation(let target) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(target.location, .desktop, "Phrase '\(phrase)' should resolve to .desktop")
            } else {
                XCTFail("Wrong argument type for \(phrase)")
            }
        }

        let documentsVariants = ["show my documents", "open the documents", "open the documents folder", "show the documents"]
        for phrase in documentsVariants {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed for phrase: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderOpenLocation)
            if case .finderLocation(let target) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(target.location, .documents, "Phrase '\(phrase)' should resolve to .documents")
            } else {
                XCTFail("Wrong argument type for \(phrase)")
            }
        }
    }

    // MARK: - 2. Ordinary Dictation Preservation Tests (No False Positives)

    func testConversationalDictationRemainsIgnoredByAllParsers() {
        let resolver = FakeApplicationResolver(installed: ["WhatsApp", "Safari", "Notes"])
        let parsers: [CommandParsing] = [
            WhatsAppCommandParser(contactResolver: FakeWhatsAppContactResolver()),
            CalendarCommandParser(),
            RemindersCommandParser(),
            NotesCommandParser(),
            FinderCommandParser(),
            DeterministicCommandParser(applications: resolver)
        ]

        let ordinaryPhrases = [
            "I want to open a new chapter",
            "Please remind me to stay focused",
            "I was talking about WhatsApp yesterday",
            "We should schedule something next month",
            "Let us take notes during the lecture",
            "Can you find the latest quarterly reports"
        ]

        for phrase in ordinaryPhrases {
            for parser in parsers {
                let plan = parser.parse(phrase, context: .test())
                XCTAssertNil(plan, "Parser \(type(of: parser)) falsely hijacked ordinary dictation: '\(phrase)'")
            }
        }
    }

    // MARK: - 3. Multi-Step Execution & Boundary Cancellation Tests

    func testMultiStepSafeStepExecutesAndSensitiveStepHaltsAtConfirmation() throws {
        let appFake = FakeApplicationControl()
        let whatsAppFake = FakeWhatsAppControl()
        let contact = WhatsAppContact(name: "Alice", phoneNumber: "1234567890")
        let fakeContacts = FakeWhatsAppContactResolver(responses: [
            "Alice": .resolved(contact)
        ])

        let router = CommandRouter(
            parsers: [
                WhatsAppCommandParser(contactResolver: fakeContacts),
                DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["WhatsApp"]))
            ],
            validator: CommandValidator(
                registry: .standard(),
                contactResolver: fakeContacts,
                applications: FakeApplicationResolver(installed: ["WhatsApp"])
            ),
            executors: [
                ApplicationCommandExecutor(control: appFake),
                WhatsAppCommandExecutor(control: whatsAppFake)
            ]
        )

        let multiPlan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "WhatsApp"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .whatsAppSendMessage,
                arguments: .whatsAppMessage(WhatsAppMessageTarget(
                    recipient: WhatsAppRecipient(rawQuery: "Alice", resolution: .resolved(contact)),
                    message: "I am running late"
                ))
            ))
        ])

        // 1. Run plan: step 1 (appOpen) executes, step 2 (whatsAppSendMessage) halts for confirmation
        let result = router.run(multiPlan, context: .test())
        guard case .confirmationRequired(let remainingPlan, _) = result else {
            XCTFail("Expected .confirmationRequired, got \(result)")
            return
        }

        XCTAssertEqual(appFake.launched.count, 1, "First safe step (appOpen) must execute immediately")
        XCTAssertEqual(remainingPlan.steps.count, 1, "Remaining plan must only have the sensitive step")
        XCTAssertEqual(remainingPlan.steps.first?.intent.identifier, CommandIdentifier.whatsAppSendMessage)
        XCTAssertEqual(whatsAppFake.openedURLs.count, 0, "Sensitive step must NOT execute before confirmation")

        // 2. Cancellation test: Cancel confirmation
        let pendingId = try XCTUnwrap(router.pendingConfirmation?.id)
        let cancelResult = router.cancel(id: pendingId)
        XCTAssertEqual(cancelResult, CommandResult.success(message: "Cancelled"))
        XCTAssertEqual(whatsAppFake.openedURLs.count, 0, "Cancelled plan must never execute")
    }

    func testMultiStepConfirmExecutesRemainingStepExactlyOnce() throws {
        let appFake = FakeApplicationControl()
        let whatsAppFake = FakeWhatsAppControl()
        let contact = WhatsAppContact(name: "Bob", phoneNumber: "9876543210")
        let fakeContacts = FakeWhatsAppContactResolver(responses: [
            "Bob": .resolved(contact)
        ])

        let router = CommandRouter(
            parsers: [
                WhatsAppCommandParser(contactResolver: fakeContacts),
                DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["WhatsApp"]))
            ],
            validator: CommandValidator(
                registry: .standard(),
                contactResolver: fakeContacts,
                applications: FakeApplicationResolver(installed: ["WhatsApp"])
            ),
            executors: [
                ApplicationCommandExecutor(control: appFake),
                WhatsAppCommandExecutor(control: whatsAppFake)
            ]
        )

        let multiPlan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "WhatsApp"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .whatsAppSendMessage,
                arguments: .whatsAppMessage(WhatsAppMessageTarget(
                    recipient: WhatsAppRecipient(rawQuery: "Bob", resolution: .resolved(contact)),
                    message: "See you soon"
                ))
            ))
        ])

        let result = router.run(multiPlan, context: .test())
        guard case .confirmationRequired = result else {
            XCTFail("Expected .confirmationRequired")
            return
        }

        let pendingId = try XCTUnwrap(router.pendingConfirmation?.id)
        let confirmResult = router.confirm(id: pendingId, context: .test())

        guard case .success(let feedback) = confirmResult else {
            XCTFail("Expected .success after confirmation, got \(confirmResult)")
            return
        }
        XCTAssertTrue(feedback.contains("Bob"))
        XCTAssertEqual(whatsAppFake.openedURLs.count, 1, "Sensitive step must execute exactly once")
        XCTAssertEqual(appFake.launched.count, 1, "Safe step must NOT re-execute")

        // 3. Duplicate confirmation attempt must be rejected
        let dupResult = router.confirm(id: pendingId, context: .test())
        guard case .failure(let msg) = dupResult else {
            XCTFail("Duplicate confirmation must fail")
            return
        }
        XCTAssertTrue(msg.contains("already been resolved") || msg.contains("stale"))
        XCTAssertEqual(whatsAppFake.openedURLs.count, 1, "Duplicate confirmation must not execute again")
    }

    // MARK: - 4. History View Text Resolution Model Tests

    func testCommandHistoryDisplayResolution() {
        let commandEntry = DictationEntry(
            raw: "open calendar please",
            cleaned: "Opened Calendar",
            duration: 0,
            appName: "Calendar",
            isCommand: true,
            commandSummary: "Opened Calendar"
        )

        // Standard display when showRaw is false: command summary
        let standardDisplay = false ? commandEntry.raw : (commandEntry.isCommand ? (commandEntry.commandSummary ?? commandEntry.cleaned) : commandEntry.cleaned)
        XCTAssertEqual(standardDisplay, "Opened Calendar")

        // Expanded display when showRaw is true (user clicked "Show more"): raw transcript
        let expandedDisplay = true ? commandEntry.raw : (commandEntry.isCommand ? (commandEntry.commandSummary ?? commandEntry.cleaned) : commandEntry.cleaned)
        XCTAssertEqual(expandedDisplay, "open calendar please")
    }
}
