import XCTest
@testable import DailyOps

@MainActor
final class DeterministicCommandRegressionTests: XCTestCase {
    private var appResolver: FakeApplicationResolver!
    private var appControl: FakeApplicationControl!
    private var host: FakeCommandHost!
    private var browserControl: FakeBrowserControl!
    private var whatsAppControl: FakeWhatsAppControl!
    private var contactResolver: FakeWhatsAppContactResolver!
    private var engine: CommandEngine!

    override func setUp() async throws {
        try await super.setUp()
        appResolver = FakeApplicationResolver(
            installed: ["Notes", "Safari", "Calculator", "Slack", "Visual Studio Code"],
            running: ["Calculator"]
        )
        appControl = FakeApplicationControl()
        host = FakeCommandHost()
        browserControl = FakeBrowserControl()
        whatsAppControl = FakeWhatsAppControl()
        contactResolver = FakeWhatsAppContactResolver(responses: [
            "Tarun": .resolved(WhatsAppContact(name: "Tarun Wesley", phoneNumber: "+15550199")),
            "Sarah Connor": .resolved(WhatsAppContact(name: "Sarah Connor", phoneNumber: "+15550144")),
            "Alexander": .resolved(WhatsAppContact(name: "Alexander Wright", phoneNumber: "+15550177"))
        ])

        let whatsAppParser = WhatsAppCommandParser(contactResolver: contactResolver)
        let deterministicParser = DeterministicCommandParser(applications: appResolver)
        let multiStepParser = MultiStepCommandParser(parsers: [whatsAppParser, deterministicParser])

        let router = CommandRouter(
            parsers: [
                multiStepParser,
                whatsAppParser,
                deterministicParser
            ],
            validator: CommandValidator(
                registry: .standard(),
                contactResolver: contactResolver,
                applications: appResolver
            ),
            executors: [
                ApplicationCommandExecutor(control: appControl),
                NavigationCommandExecutor(host: host),
                DictationCommandExecutor(host: host),
                BrowserCommandExecutor(control: browserControl),
                WhatsAppCommandExecutor(control: whatsAppControl)
            ]
        )
        engine = CommandEngine(router: router)
    }

    // MARK: - Regression: Zero-Configuration Supported Commands

    func testSupportedCommandsExecuteWithoutAnyAPIOrLLMConfiguration() {
        // 1. Open app
        let openResult = engine.process("open Notes", context: .test())
        XCTAssertEqual(openResult, .executed(feedback: "Opened Notes"))
        XCTAssertEqual(appControl.launched.map(\.displayName), ["Notes"])

        // 2. Browser search
        let searchResult = engine.process("search YouTube for swift tutorials", context: .test())
        XCTAssertEqual(searchResult, .executed(feedback: "Searched YouTube for 'swift tutorials'"))
        XCTAssertEqual(browserControl.openedURLs.count, 1)
        XCTAssertTrue(browserControl.openedURLs.first?.absoluteString.contains("youtube.com") == true)

        // 3. Navigation / System command
        let settingsResult = engine.process("open settings", context: .test())
        XCTAssertEqual(settingsResult, .executed(feedback: "Opened Settings"))
        XCTAssertEqual(host.calls, ["showSettings"])
    }

    // MARK: - Regression: Unsupported Commands Fall Back to Dictation (.ignored)

    func testUnsupportedNaturalLanguageDoesNotTriggerNetworkAndFallsBackToDictation() async {
        let unsupportedPhrases = [
            "what is the weather today in San Francisco",
            "write an email to Bob explaining why I will be late",
            "can you summarize the document for me",
            "who was the first person to walk on the moon",
            "create a python script to parse logs",
            "tell me a funny joke about programming"
        ]

        for phrase in unsupportedPhrases {
            // Synchronous process
            let outcome = engine.process(phrase, context: .test())
            XCTAssertEqual(outcome, .ignored, "Phrase '\(phrase)' must be ignored and fall back to dictation")

            // Asynchronous process
            let asyncOutcome = await engine.processAsync(phrase, context: .test())
            XCTAssertEqual(asyncOutcome, .ignored, "Async phrase '\(phrase)' must be ignored and fall back to dictation")

            // handle() and handleAsync() return nil to signal normal dictation continuation
            let handleFeedback = engine.handle(phrase, context: .test())
            XCTAssertNil(handleFeedback, "handle() should return nil for dictation fallback")

            let asyncHandleFeedback = await engine.handleAsync(phrase, context: .test())
            XCTAssertNil(asyncHandleFeedback, "handleAsync() should return nil for dictation fallback")
        }
    }

    // MARK: - Regression: Dynamic WhatsApp Contacts Resolution Without AI

    func testWhatsAppDynamicContactResolutionRemainsFullyLocal() {
        // Open chat for dynamic contact (safe action, executes immediately)
        let openChatOutcome = engine.process("open Sarah Connor's WhatsApp chat", context: .test())
        XCTAssertEqual(openChatOutcome, .executed(feedback: "Opened WhatsApp chat with Sarah Connor"))
        XCTAssertEqual(whatsAppControl.openedURLs.count, 1)
        XCTAssertTrue(whatsAppControl.openedURLs.first?.absoluteString.contains("5550144") == true)

        // Stage message (sensitive action, requires confirmation)
        let msgOutcome = engine.process("message Tarun that I am on my way", context: .test())
        guard case .confirmationRequired(let msgRequest) = msgOutcome else {
            return XCTFail("Messaging requires confirmation")
        }
        XCTAssertTrue(msgRequest.details.contains("Tarun Wesley"))

        let msgConfirmResult = engine.confirm(id: msgRequest.id, context: .test())
        XCTAssertEqual(msgConfirmResult, .success(message: "Prepared WhatsApp message for Tarun Wesley"))
        XCTAssertEqual(whatsAppControl.openedURLs.count, 2)
    }

    // MARK: - Regression: Multi-Step Execution & Confirmation

    func testMultiStepCommandExecutesDeterministically() {
        let transcript = "open Notes and message Alexander that dinner is ready"
        let outcome = engine.process(transcript, context: .test())

        // Notes should open immediately (safe step), but messaging requires confirmation
        XCTAssertEqual(appControl.launched.map(\.displayName), ["Notes"])

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Remaining sensitive step requires confirmation")
        }
        XCTAssertTrue(request.details.contains("Alexander Wright"))

        // Complete the remaining step
        let confirmResult = engine.confirm(id: request.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Prepared WhatsApp message for Alexander Wright"))
        XCTAssertEqual(whatsAppControl.openedURLs.count, 1)
    }

    // MARK: - Regression: Deterministic Text Cleanup & Formatting

    func testDeterministicCleanupWorksWithoutAnyLLMOrNetwork() async {
        let raw = "um hello world comma this is the the test period"
        let cleaned = await CleanupService.clean(raw)

        // Fillers removed ("um" removed)
        XCTAssertFalse(cleaned.lowercased().hasPrefix("um"))
        // Stutter repeat removed ("the the" -> "the")
        XCTAssertFalse(cleaned.contains("the the"))
        // Spoken punctuation formatted ("comma" -> ",", "period" -> ".")
        XCTAssertTrue(cleaned.contains(","))
        XCTAssertTrue(cleaned.contains("."))
        // CleanupService is available on-device
        XCTAssertTrue(CleanupService.isAvailable)
    }
    func testDeterministicCleanupRespectsDisabledSpeechAndPunctuationPreferences() {
        let defaults = UserDefaults.standard
        let keys = ["speechCleanupEnabled", "formatSpellCheck", "formatSpokenPunctuation", "formatAutoPeriod", "formatCapitalization"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: "speechCleanupEnabled")
        defaults.set(false, forKey: "formatSpellCheck")
        defaults.set(false, forKey: "formatSpokenPunctuation")
        defaults.set(false, forKey: "formatAutoPeriod")
        defaults.set("preserve", forKey: "formatCapitalization")
        let raw = "um hello hello comma world"
        XCTAssertEqual(CleanupService.cleanDeterministically(raw), raw)
    }

}
