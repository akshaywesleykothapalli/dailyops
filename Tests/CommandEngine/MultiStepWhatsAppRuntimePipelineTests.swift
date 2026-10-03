import XCTest
@testable import DailyOps

@MainActor
final class MultiStepWhatsAppRuntimePipelineTests: XCTestCase {
    private var appControl: FakeApplicationControl!
    private var whatsAppControl: FakeWhatsAppControl!
    private var browserControl: FakeBrowserControl!
    private var contactResolver: FakeWhatsAppContactResolver!
    private var router: CommandRouter!
    private var engine: CommandEngine!

    override func setUp() async throws {
        try await super.setUp()
        appControl = FakeApplicationControl()
        whatsAppControl = FakeWhatsAppControl()
        browserControl = FakeBrowserControl()

        contactResolver = FakeWhatsAppContactResolver(responses: [
            "Tarun": .resolved(WhatsAppContact(name: "Tarun", phoneNumber: "14155553333")),
            "John": .resolved(WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")),
            "Rahul": .resolved(WhatsAppContact(name: "Rahul", phoneNumber: "14155556666")),
            "David": .ambiguous([
                WhatsAppContact(name: "David Miller", phoneNumber: "14155557777"),
                WhatsAppContact(name: "David Wilson", phoneNumber: "14155558888")
            ]),
            "SomeoneWhoDoesNotExist": .notFound(query: "SomeoneWhoDoesNotExist")
        ])

        // Use real ApplicationRegistry so standard applications (WhatsApp, Safari, Finder, Settings) are registered
        let appResolver = SystemApplicationResolver(
            discovery: ApplicationDiscovery.shared,
            registry: ApplicationRegistry()
        )

        let whatsAppParser = WhatsAppCommandParser(contactResolver: contactResolver)
        let deterministicParser = DeterministicCommandParser(applications: appResolver)
        let multiStepParser = MultiStepCommandParser(parsers: [whatsAppParser, deterministicParser])

        router = CommandRouter(
            parsers: [
                multiStepParser,
                whatsAppParser,
                deterministicParser
            ],
            validator: CommandValidator(registry: .standard()),
            executors: [
                ApplicationCommandExecutor(control: appControl),
                WhatsAppCommandExecutor(control: whatsAppControl),
                BrowserCommandExecutor(control: browserControl)
            ]
        )
        engine = CommandEngine(router: router)
    }

    // MARK: - Core Reproduction & Test A

    func testExactCommandExecutesStepOneAndHaltsAtConfirmationForStepTwo() {
        let transcript = "Open WhatsApp and message Tarun that I'm running late."
        let outcome = engine.process(transcript, context: .test())

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired but got: \(outcome)")
        }

        // Step 1: WhatsApp was launched
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(appControl.launched.first?.displayName, "WhatsApp")

        // Step 2: Message action NOT executed yet
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)

        // Confirmation details verification
        XCTAssertEqual(request.title, "Send WhatsApp message?")
        XCTAssertTrue(request.details.contains("Tarun"))
        XCTAssertTrue(request.details.contains("I'm running late"))
        XCTAssertEqual(request.confirmActionLabel, "Send")
        XCTAssertEqual(request.cancelActionLabel, "Cancel")
        XCTAssertEqual(request.risk, .sensitive)

        // Router pendingConfirmation must match
        XCTAssertEqual(router.pendingConfirmation?.id, request.id)
    }

    // MARK: - Test B: Confirming Pending Step

    func testConfirmingPendingStepExecutesExactWhatsAppActionWithoutReparsing() {
        let transcript = "Open WhatsApp and message Tarun that I'm running late."
        let outcome = engine.process(transcript, context: .test())

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired")
        }

        let confirmResult = engine.confirm(id: request.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Prepared WhatsApp message for Tarun"))

        // WhatsApp message action executed
        XCTAssertEqual(whatsAppControl.openedURLs.count, 1)
        let openedURL = whatsAppControl.openedURLs.first?.absoluteString ?? ""
        XCTAssertTrue(openedURL.contains("14155553333"))
        XCTAssertTrue(openedURL.contains("I'm%20running%20late"))

        // Confirmation is resolved and cleared
        XCTAssertNil(engine.pendingConfirmation)
    }

    // MARK: - Test C: Cancelling Pending Step

    func testCancellingPendingStepLeavesStepOneDoneAndDropsStepTwo() {
        let transcript = "Open WhatsApp and message Tarun that I'm running late."
        let outcome = engine.process(transcript, context: .test())

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired")
        }

        let cancelResult = engine.cancel(id: request.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))

        // Step 1 remains executed
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(appControl.launched.first?.displayName, "WhatsApp")

        // Step 2 was never executed
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)
        XCTAssertNil(engine.pendingConfirmation)
    }

    // MARK: - Test D: Unknown Contact

    func testUnknownContactFailsValidationUpfrontWithoutCreatingConfirmationOrExecuting() {
        let transcript = "Open WhatsApp and message SomeoneWhoDoesNotExist saying hello"
        let outcome = engine.process(transcript, context: .test())

        guard case .failed(let message) = outcome else {
            return XCTFail("Expected .failed for unknown contact, got: \(outcome)")
        }

        XCTAssertTrue(message.contains("SomeoneWhoDoesNotExist"))
        // Neither step 1 nor step 2 executed
        XCTAssertEqual(appControl.launched.count, 0)
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)
        XCTAssertNil(engine.pendingConfirmation)
    }

    // MARK: - Test E: Ambiguous Contacts

    func testAmbiguousContactFailsValidationUpfrontWithoutExecuting() {
        let transcript = "Open WhatsApp and message David saying hello"
        let outcome = engine.process(transcript, context: .test())

        guard case .failed(let message) = outcome else {
            return XCTFail("Expected .failed for ambiguous contact, got: \(outcome)")
        }

        XCTAssertTrue(message.contains("David"))
        XCTAssertEqual(appControl.launched.count, 0)
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)
        XCTAssertNil(engine.pendingConfirmation)
    }

    // MARK: - Transcript Variations

    func testTranscriptVariationJohn() {
        let transcript = "Open WhatsApp and message John that I'm running late."
        let outcome = engine.process(transcript, context: .test())

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired for John variation")
        }

        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(request.title, "Send WhatsApp message?")
        XCTAssertTrue(request.details.contains("John Appleseed"))
    }

    func testTranscriptVariationRahul() {
        let transcript = "Open WhatsApp and message Rahul saying I'll call you later."
        let outcome = engine.process(transcript, context: .test())

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired for Rahul variation")
        }

        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(request.title, "Send WhatsApp message?")
        XCTAssertTrue(request.details.contains("Rahul"))
        XCTAssertTrue(request.details.contains("I'll call you later"))
    }

    // MARK: - Single-Step Regressions

    func testSingleStepOpenWhatsAppExecutesNormally() {
        let transcript = "Open WhatsApp"
        let outcome = engine.process(transcript, context: .test())

        guard case .executed(let feedback) = outcome else {
            return XCTFail("Expected .executed for single-step 'Open WhatsApp', got: \(outcome)")
        }

        XCTAssertTrue(feedback == "Opened WhatsApp" || feedback == "Opened Whatsapp")
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)
        XCTAssertNil(engine.pendingConfirmation)
    }

    func testSingleStepMessageTarunReachesConfirmationDirectly() {
        let transcript = "Message Tarun saying I'm running late"
        let outcome = engine.process(transcript, context: .test())

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired for single-step message, got: \(outcome)")
        }

        XCTAssertEqual(appControl.launched.count, 0)
        XCTAssertEqual(request.title, "Send WhatsApp message?")
        XCTAssertTrue(request.details.contains("Tarun"))
    }

    // MARK: - Multi-Step Non-WhatsApp Commands

    func testMultiStepSafariAndGoogleSearchExecutesBothSteps() {
        let transcript = "Open Safari and search Google for cats"
        let outcome = engine.process(transcript, context: .test())

        guard case .executed(let feedback) = outcome else {
            return XCTFail("Expected .executed for safe multi-step, got: \(outcome)")
        }

        XCTAssertTrue(feedback.contains("Opened Safari"))
        XCTAssertTrue(feedback.contains("Searched Google for 'cats'"))
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(appControl.launched.first?.displayName, "Safari")
        XCTAssertEqual(browserControl.openedURLs.count, 1)
        XCTAssertTrue(browserControl.openedURLs.first?.absoluteString.contains("google.com/search?q=cats") ?? false)
    }

    func testMultiStepFinderAndSystemSettingsExecutesBothSteps() {
        let transcript = "Open Finder and open System Settings"
        let outcome = engine.process(transcript, context: .test())

        guard case .executed(let feedback) = outcome else {
            return XCTFail("Expected .executed for multi-step app opens, got: \(outcome)")
        }

        XCTAssertTrue(feedback.contains("Opened Finder"))
        XCTAssertTrue(feedback.contains("Opened System Settings"))
        XCTAssertEqual(appControl.launched.count, 2)
        XCTAssertEqual(appControl.launched[0].displayName, "Finder")
        XCTAssertEqual(appControl.launched[1].displayName, "System Settings")
    }

    // MARK: - ApplicationDiscovery Conjunction Safeguard Test

    func testApplicationDiscoveryDoesNotMatchMultiStepQueries() {
        let multiStepQuery = "whatsapp and message tarun that i m running late"
        let result = ApplicationDiscovery.shared.findApplication(named: multiStepQuery)
        XCTAssertNil(result, "ApplicationDiscovery must NOT match multi-step command text as an application name!")

        let safariQuery = "safari and search google for cats"
        let safariResult = ApplicationDiscovery.shared.findApplication(named: safariQuery)
        XCTAssertNil(safariResult, "ApplicationDiscovery must NOT match multi-step browser query as an application name!")
    }
}
