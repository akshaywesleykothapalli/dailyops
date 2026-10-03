import XCTest
@testable import DailyOps

@MainActor
final class WhatsAppModelsTests: XCTestCase {
    func testPhoneNumberNormalization() {
        XCTAssertEqual(WhatsAppURLBuilder.normalizePhoneNumber("+1 (415) 555-2671"), "14155552671")
        XCTAssertEqual(WhatsAppURLBuilder.normalizePhoneNumber("+91 98765 43210"), "919876543210")
        XCTAssertEqual(WhatsAppURLBuilder.normalizePhoneNumber("  (080) 123-4567 "), "0801234567")
        XCTAssertEqual(WhatsAppURLBuilder.normalizePhoneNumber(""), "")
    }

    func testChatURLConstruction() {
        let url = WhatsAppURLBuilder.chatURL(for: "+1 (415) 555-2671")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "whatsapp://send?phone=14155552671")
    }

    func testChatURLWithEmptyPhoneReturnsNil() {
        XCTAssertNil(WhatsAppURLBuilder.chatURL(for: ""))
        XCTAssertNil(WhatsAppURLBuilder.chatURL(for: "   "))
        XCTAssertNil(WhatsAppURLBuilder.chatURL(for: "abc"))
    }

    func testMessageURLConstructionWithPercentEncoding() {
        let url = WhatsAppURLBuilder.messageURL(for: "+1 (415) 555-2671", message: "I'll be there in 10 minutes!")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.hasPrefix("whatsapp://send?phone=14155552671&text=") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("I'll%20be%20there") ?? false)
    }

    func testMessageURLPreservesReservedCharactersAndMultiline() {
        let testCases = [
            "I'm with Tom & Jerry",
            "C++ is great",
            "A=B",
            "hello #world",
            "line one\nline two",
            "Swift + macOS & iOS = awesome"
        ]

        for message in testCases {
            guard let url = WhatsAppURLBuilder.messageURL(for: "14155551234", message: message) else {
                XCTFail("Failed to build URL for message: \(message)")
                continue
            }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                XCTFail("Failed to parse back URL for message: \(message)")
                continue
            }
            let parsedText = components.queryItems?.first(where: { $0.name == "text" })?.value
            XCTAssertEqual(parsedText, message, "Query parameter 'text' must match original message exactly")
        }
    }

    func testRecipientDisplayNames() {
        let contact = WhatsAppContact(name: "John Doe", phoneNumber: "14155552671")
        let resolved = WhatsAppRecipient(rawQuery: "John", resolution: .resolved(contact))
        XCTAssertEqual(resolved.displayName, "John Doe (+14155552671)")
        XCTAssertEqual(resolved.contactName, "John Doe")
        XCTAssertEqual(resolved.resolvedContact, contact)

        let notFound = WhatsAppRecipient(rawQuery: "Unknown", resolution: .notFound(query: "Unknown"))
        XCTAssertEqual(notFound.displayName, "Unknown")
        XCTAssertEqual(notFound.contactName, "Unknown")
        XCTAssertNil(notFound.resolvedContact)
    }
}
