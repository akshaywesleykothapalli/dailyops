import XCTest
@testable import DailyOps

@MainActor
final class WhatsAppConfirmationIntegrationTests: XCTestCase {
    private var control: FakeWhatsAppControl!
    private var contactResolver: FakeWhatsAppContactResolver!
    private var router: CommandRouter!

    override func setUp() async throws {
        try await super.setUp()
        control = FakeWhatsAppControl()
        contactResolver = FakeWhatsAppContactResolver(responses: [
            "John": .resolved(WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")),
            "Alice": .resolved(WhatsAppContact(name: "Alice", phoneNumber: "14155552222")),
            "David": .ambiguous([
                WhatsAppContact(name: "David Miller", phoneNumber: "14155553333"),
                WhatsAppContact(name: "David Wilson", phoneNumber: "14155554444")
            ]),
            "Tarun": .resolved(WhatsAppContact(name: "Tarun", phoneNumber: "14155553333")),
            "Rahul Kumar": .resolved(WhatsAppContact(name: "Rahul Kumar", phoneNumber: "14155556666")),
            "Unknown": .notFound(query: "Unknown"),
        ])

        let parser = WhatsAppCommandParser(contactResolver: contactResolver)
        let validator = CommandValidator(registry: .standard())
        let executor = WhatsAppCommandExecutor(control: control)

        router = CommandRouter(
            parsers: [parser],
            validator: validator,
            executors: [executor]
        )
    }

    func testOpenChatExecutesImmediatelyWithoutConfirmation() {
        let result = router.handle("open John's WhatsApp chat", context: .test())

        XCTAssertEqual(result, .success(message: "Opened WhatsApp chat with John Appleseed"))
        XCTAssertNil(router.pendingConfirmation)
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertEqual(control.openedURLs.first?.absoluteString, "whatsapp://send?phone=14155551234")
    }

    func testSendMessageHaltsAtConfirmationBoundaryWithoutExecuting() {
        let result = router.handle("message John saying I'll be there in 10 minutes", context: .test())

        guard case .confirmationRequired(let plan, _) = result else {
            return XCTFail("Expected confirmationRequired for sending message")
        }

        XCTAssertEqual(plan.steps.first?.intent.identifier, .whatsAppSendMessage)
        // Ensure no side effect occurred
        XCTAssertEqual(control.openedURLs.count, 0)

        // Verify pending confirmation metadata
        let pending = router.pendingConfirmation
        XCTAssertNotNil(pending)
        XCTAssertEqual(pending?.title, "Send WhatsApp message?")
        XCTAssertEqual(pending?.confirmActionLabel, "Send")
        XCTAssertEqual(pending?.cancelActionLabel, "Cancel")
        XCTAssertTrue(pending?.details.contains("John Appleseed") ?? false)
        XCTAssertTrue(pending?.details.contains("I'll be there in 10 minutes") ?? false)
    }

    func testConfirmingPendingSendMessageExecutesExactPlan() {
        _ = router.handle("message Alice saying meeting starts at 3", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let confirmResult = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Prepared WhatsApp message for Alice"))
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertTrue(control.openedURLs.first?.absoluteString.contains("meeting%20starts%20at%203") ?? false)
        XCTAssertNil(router.pendingConfirmation)
    }

    func testCancellingPendingSendMessageNeverExecutes() {
        _ = router.handle("message Alice saying meeting starts at 3", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let cancelResult = router.cancel(id: pending.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))
        XCTAssertEqual(control.openedURLs.count, 0)
        XCTAssertNil(router.pendingConfirmation)
    }

    func testAmbiguousContactFailsValidationWithClarification() {
        let result = router.handle("message David saying hello", context: .test())

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure for ambiguous contact")
        }
        XCTAssertTrue(message.contains("Multiple contacts found for 'David'"))
        XCTAssertTrue(message.contains("David Miller"))
        XCTAssertTrue(message.contains("David Wilson"))

        XCTAssertNil(router.pendingConfirmation)
        XCTAssertEqual(control.openedURLs.count, 0)
    }

    func testNotFoundContactFailsValidationWithoutSending() {
        let result = router.handle("message Unknown saying hello", context: .test())

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure for unknown contact")
        }
        XCTAssertTrue(message.contains("No contact found for 'Unknown'"))

        XCTAssertNil(router.pendingConfirmation)
        XCTAssertEqual(control.openedURLs.count, 0)
    }

    func testArbitraryContactTarunConfirmationFlow() {
        let result = router.handle("Message Tarun that I'm running late", context: .test())

        guard case .confirmationRequired(let plan, _) = result else {
            return XCTFail("Expected confirmationRequired for Tarun message")
        }

        XCTAssertEqual(plan.steps.first?.intent.identifier, .whatsAppSendMessage)
        XCTAssertEqual(control.openedURLs.count, 0)

        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation for Tarun")
        }
        XCTAssertTrue(pending.details.contains("Tarun"))
        XCTAssertTrue(pending.details.contains("I'm running late"))

        let confirmResult = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Prepared WhatsApp message for Tarun"))
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertTrue(control.openedURLs.first?.absoluteString.contains("phone=14155553333") ?? false)
        XCTAssertTrue(control.openedURLs.first?.absoluteString.contains("I'm%20running%20late") ?? false)
    }

    func testCriticalNegativeUnknownContactDoesNotExecute() {
        let result = router.handle("Message SomeoneWhoDoesNotExist saying hello", context: .test())

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure for non-existent contact")
        }
        XCTAssertTrue(message.contains("No contact found for 'SomeoneWhoDoesNotExist'"))

        // Must not create a pending confirmation and must not open any URL
        XCTAssertNil(router.pendingConfirmation)
        XCTAssertEqual(control.openedURLs.count, 0)
    }

    func testOpenChatArbitraryContactTarun() {
        let result = router.handle("Open Tarun's WhatsApp chat", context: .test())
        XCTAssertEqual(result, .success(message: "Opened WhatsApp chat with Tarun"))
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertEqual(control.openedURLs.first?.absoluteString, "whatsapp://send?phone=14155553333")
    }
}
