import XCTest
@testable import DailyOps

@MainActor
final class MultiStepParserTests: XCTestCase {
    private var parser: MultiStepCommandParser!

    override func setUp() async throws {
        try await super.setUp()
        let appResolver = FakeApplicationResolver(installed: [
            "Google Chrome", "Chrome", "Safari", "WhatsApp", "Finder"
        ])
        let contactResolver = FakeWhatsAppContactResolver(responses: [
            "John": .resolved(WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")),
            "Alice": .resolved(WhatsAppContact(name: "Alice", phoneNumber: "14155552222")),
            "Tarun": .resolved(WhatsAppContact(name: "Tarun", phoneNumber: "14155553333")),
            "Rahul": .resolved(WhatsAppContact(name: "Rahul", phoneNumber: "14155554444")),
            "Priya": .resolved(WhatsAppContact(name: "Priya", phoneNumber: "14155555555")),
        ])

        let deterministic = DeterministicCommandParser(applications: appResolver)
        let whatsApp = WhatsAppCommandParser(contactResolver: contactResolver)

        parser = MultiStepCommandParser(parsers: [whatsApp, deterministic])
    }

    func testParsesTwoStepCommandWithAnd() {
        let plan = parser.parse("Open Chrome and search Google for cats", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .browserSearch)

        guard case .application(let app) = plan?.steps[0].intent.arguments else {
            return XCTFail("Expected application argument for step 1")
        }
        XCTAssertEqual(app.displayName, "Chrome")

        guard case .search(let request) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected search argument for step 2")
        }
        XCTAssertEqual(request.query, "cats")
        XCTAssertEqual(request.provider, .google)
    }

    func testParsesTwoStepCommandWithThen() {
        let plan = parser.parse("Open Safari, then go to github.com", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .browserOpenURL)

        guard case .url(let url) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected url argument for step 2")
        }
        XCTAssertEqual(url.absoluteString, "https://github.com")
    }

    func testParsesTwoStepCommandWithAfterThat() {
        let plan = parser.parse("Open Chrome after that search YouTube for worship songs", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .browserSearch)

        guard case .search(let req) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected search argument for step 2")
        }
        XCTAssertEqual(req.query, "worship songs")
        XCTAssertEqual(req.provider, .youtube)
    }

    func testParsesWhatsAppMultiStepCommand() {
        let plan = parser.parse("Open WhatsApp and open John's chat", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppOpenChat)
    }

    func testParsesThreeStepCommand() {
        let plan = parser.parse("Open WhatsApp, open John's chat, and message John saying I'll be there", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 3)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppOpenChat)
        XCTAssertEqual(plan?.steps[2].intent.identifier, .whatsAppSendMessage)
    }

    func testParsesOpenWhatsAppAndMessageTarunThat() {
        let plan = parser.parse("Open WhatsApp and message Tarun that I'm running late", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppSendMessage)

        guard case .whatsAppMessage(let target) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected whatsAppMessage for step 2")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Tarun")
        XCTAssertEqual(target.message, "I'm running late")
    }

    func testParsesOpenWhatsAppAndMessageJohnThat() {
        let plan = parser.parse("Open WhatsApp and message John that I'm running late", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppSendMessage)

        guard case .whatsAppMessage(let target) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected whatsAppMessage for step 2")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
        XCTAssertEqual(target.message, "I'm running late")
    }

    func testParsesOpenWhatsAppAndMessageRahulSaying() {
        let plan = parser.parse("Open WhatsApp and message Rahul saying I'll call you later", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppSendMessage)

        guard case .whatsAppMessage(let target) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected whatsAppMessage for step 2")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Rahul")
        XCTAssertEqual(target.message, "I'll call you later")
    }

    func testParsesOpenWhatsAppAndMessagePriyaSaying() {
        let plan = parser.parse("Open WhatsApp and message Priya saying I'll be there soon", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppSendMessage)

        guard case .whatsAppMessage(let target) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected whatsAppMessage for step 2")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Priya")
        XCTAssertEqual(target.message, "I'll be there soon")
    }

    func testParsesOpenWhatsAppAndTextPriyaThat() {
        let plan = parser.parse("Open WhatsApp and text Priya that I'm running late", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppSendMessage)

        guard case .whatsAppMessage(let target) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected whatsAppMessage for step 2")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Priya")
        XCTAssertEqual(target.message, "I'm running late")
    }

    func testParsesOpenWhatsAppAndMessageWithAndInMessageRemainsTwoSteps() {
        let plan = parser.parse("Open WhatsApp and message Rahul saying I'll call you and let you know", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .whatsAppSendMessage)

        guard case .whatsAppMessage(let target) = plan?.steps[1].intent.arguments else {
            return XCTFail("Expected whatsAppMessage for step 2")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Rahul")
        XCTAssertEqual(target.message, "I'll call you and let you know")
    }

    func testSearchQueryContainingAndIsPreservedAsSingleCommand() {
        let plan = parser.parse("Search Google for rock and roll music", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 1)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .browserSearch)

        guard case .search(let request) = plan?.steps[0].intent.arguments else {
            return XCTFail("Expected search argument")
        }
        XCTAssertEqual(request.query, "rock and roll music")
    }

    func testSingleCommandIsNotSplit() {
        let plan = parser.parse("Open Chrome", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 1)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .appOpen)
    }

    func testConversationalSentencesWithAndAreIgnoredForDictation() {
        XCTAssertNil(parser.parse("I went to the store and bought apples", context: .test()))
        XCTAssertNil(parser.parse("John and Mary went for a walk", context: .test()))
        XCTAssertNil(parser.parse("Open the door and close the window", context: .test()))
    }

    func testDisabledCommandModeReturnsNil() {
        let disabled = CommandContext.test(isCommandModeEnabled: false)
        XCTAssertNil(parser.parse("Open Chrome and search Google for cats", context: disabled))
    }
}
