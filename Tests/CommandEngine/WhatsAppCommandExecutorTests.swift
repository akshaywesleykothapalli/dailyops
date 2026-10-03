import XCTest
@testable import DailyOps

@MainActor
final class WhatsAppCommandExecutorTests: XCTestCase {
    private var control: FakeWhatsAppControl!
    private var executor: WhatsAppCommandExecutor!

    override func setUp() async throws {
        try await super.setUp()
        control = FakeWhatsAppControl()
        executor = WhatsAppCommandExecutor(control: control)
    }

    func testOpenChatExecutesSuccessfully() throws {
        let contact = WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")
        let target = WhatsAppChatTarget(recipient: WhatsAppRecipient(rawQuery: "John", resolution: .resolved(contact)))
        let intent = CommandIntent(identifier: .whatsAppOpenChat, arguments: .whatsAppChat(target))

        let feedback = try executor.execute(intent, context: .test())

        XCTAssertEqual(feedback, "Opened WhatsApp chat with John Appleseed")
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertEqual(control.openedURLs.first?.absoluteString, "whatsapp://send?phone=14155551234")
    }

    func testSendMessageExecutesSuccessfully() throws {
        let contact = WhatsAppContact(name: "Alice", phoneNumber: "14155552222")
        let target = WhatsAppMessageTarget(
            recipient: WhatsAppRecipient(rawQuery: "Alice", resolution: .resolved(contact)),
            message: "I'll be there at 7!"
        )
        let intent = CommandIntent(identifier: .whatsAppSendMessage, arguments: .whatsAppMessage(target))

        let feedback = try executor.execute(intent, context: .test())

        XCTAssertEqual(feedback, "Prepared WhatsApp message for Alice")
        XCTAssertEqual(control.openedURLs.count, 1)
        XCTAssertTrue(control.openedURLs.first?.absoluteString.hasPrefix("whatsapp://send?phone=14155552222&text=") ?? false)
        XCTAssertTrue(control.openedURLs.first?.absoluteString.contains("I'll%20be%20there") ?? false)
    }

    func testUnresolvedRecipientThrowsError() {
        let target = WhatsAppChatTarget(recipient: WhatsAppRecipient(rawQuery: "Unknown", resolution: .notFound(query: "Unknown")))
        let intent = CommandIntent(identifier: .whatsAppOpenChat, arguments: .whatsAppChat(target))

        XCTAssertThrowsError(try executor.execute(intent, context: .test()))
    }

    func testControlFailurePropagates() {
        control.shouldFail = true
        let contact = WhatsAppContact(name: "John", phoneNumber: "14155551234")
        let target = WhatsAppChatTarget(recipient: WhatsAppRecipient(rawQuery: "John", resolution: .resolved(contact)))
        let intent = CommandIntent(identifier: .whatsAppOpenChat, arguments: .whatsAppChat(target))

        XCTAssertThrowsError(try executor.execute(intent, context: .test()))
    }
}
