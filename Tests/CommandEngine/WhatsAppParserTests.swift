import XCTest
@testable import DailyOps

@MainActor
final class WhatsAppParserTests: XCTestCase {
    private var contactResolver: FakeWhatsAppContactResolver!
    private var parser: WhatsAppCommandParser!

    override func setUp() async throws {
        try await super.setUp()
        contactResolver = FakeWhatsAppContactResolver(responses: [
            "John": .resolved(WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")),
            "Alice": .resolved(WhatsAppContact(name: "Alice", phoneNumber: "14155552222")),
            "David": .ambiguous([
                WhatsAppContact(name: "David Miller", phoneNumber: "14155553333"),
                WhatsAppContact(name: "David Wilson", phoneNumber: "14155554444")
            ]),
            "Tarun": .resolved(WhatsAppContact(name: "Tarun", phoneNumber: "14155555551")),
            "Rahul": .resolved(WhatsAppContact(name: "Rahul", phoneNumber: "14155555552")),
            "Priya": .resolved(WhatsAppContact(name: "Priya", phoneNumber: "14155555553")),
            "Rahul Kumar": .resolved(WhatsAppContact(name: "Rahul Kumar", phoneNumber: "14155555554")),
            "Priya Sharma": .resolved(WhatsAppContact(name: "Priya Sharma", phoneNumber: "14155555555")),
            "Mom": .resolved(WhatsAppContact(name: "Mom", phoneNumber: "14155555556")),
            "Dad": .resolved(WhatsAppContact(name: "Dad", phoneNumber: "14155555557")),
        ])
        parser = WhatsAppCommandParser(contactResolver: contactResolver)
    }

    // MARK: - Open WhatsApp Fallback (Must Not Be Handled Here)

    func testOpenWhatsAppReturnsNilForGenericAppLauncher() {
        XCTAssertNil(parser.parse("open WhatsApp", context: .test()))
        XCTAssertNil(parser.parse("launch WhatsApp", context: .test()))
        XCTAssertNil(parser.parse("start WhatsApp", context: .test()))
        XCTAssertNil(parser.parse("Open WhatsApp.", context: .test()))
    }

    // MARK: - Chat Opening Phrases

    func testParsesOpenChatPossessivePhrase() {
        let plan = parser.parse("open John's WhatsApp chat", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
        XCTAssertEqual(target.recipient.resolvedContact?.name, "John Appleseed")
        XCTAssertEqual(target.recipient.resolvedContact?.phoneNumber, "14155551234")
    }

    func testParsesOpenMyWhatsAppChatWithPhrase() {
        let plan = parser.parse("open my WhatsApp chat with Alice", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Alice")
        XCTAssertEqual(target.recipient.resolvedContact?.name, "Alice")
    }

    func testParsesOpenWhatsAppChatWithPhrase() {
        let plan = parser.parse("open WhatsApp chat with John", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
    }

    func testParsesOpenChatOnWhatsAppPhrase() {
        let plan = parser.parse("open chat with John on WhatsApp", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
    }

    func testParsesOpenPersonOnWhatsApp() {
        let plan = parser.parse("open John on WhatsApp", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
    }

    // MARK: - Message Sending Phrases

    func testParsesMessagePersonSayingPhrase() {
        let plan = parser.parse("message John saying I'll be there in 10 minutes", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
        XCTAssertEqual(target.message, "I'll be there in 10 minutes")
        XCTAssertEqual(target.recipient.resolvedContact?.name, "John Appleseed")
    }

    func testParsesSendPersonAWhatsAppMessageSaying() {
        let plan = parser.parse("send John a WhatsApp message saying I'll call later", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
        XCTAssertEqual(target.message, "I'll call later")
    }

    func testParsesSendAWhatsAppMessageToPersonSaying() {
        let plan = parser.parse("send a WhatsApp message to Alice saying see you tomorrow", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Alice")
        XCTAssertEqual(target.message, "see you tomorrow")
    }

    func testParsesWhatsAppPersonSaying() {
        let plan = parser.parse("whatsapp John saying hello there", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
        XCTAssertEqual(target.message, "hello there")
    }

    func testParsesMessageArbitraryNameThatPhrase() {
        let plan = parser.parse("Message Tarun that I'm running late", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Tarun")
        XCTAssertEqual(target.message, "I'm running late")
        XCTAssertEqual(target.recipient.resolvedContact?.phoneNumber, "14155555551")
    }

    func testParsesMessageArbitraryNameSayingPhrase() {
        let plan = parser.parse("Message John saying I'll call you later", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "John")
        XCTAssertEqual(target.message, "I'll call you later")
    }

    func testParsesSendWhatsAppMessageToArbitraryName() {
        let plan = parser.parse("Send Rahul a WhatsApp message saying happy birthday", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Rahul")
        XCTAssertEqual(target.message, "happy birthday")
        XCTAssertEqual(target.recipient.resolvedContact?.name, "Rahul")
    }

    func testParsesTextPersonOnWhatsAppSaying() {
        let plan = parser.parse("Text Priya on WhatsApp saying I'm on my way", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Priya")
        XCTAssertEqual(target.message, "I'm on my way")
        XCTAssertEqual(target.recipient.resolvedContact?.name, "Priya")
    }

    func testParsesTextPersonThat() {
        let plan = parser.parse("text Priya that I'm running late", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Priya")
        XCTAssertEqual(target.message, "I'm running late")
    }

    func testParsesOpenChatPossessiveArbitraryNames() {
        let planTarun = parser.parse("Open Tarun's WhatsApp chat", context: .test())
        XCTAssertEqual(planTarun?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let targetTarun) = planTarun?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(targetTarun.recipient.rawQuery, "Tarun")
        XCTAssertEqual(targetTarun.recipient.resolvedContact?.name, "Tarun")

        let planJohn = parser.parse("Open John's WhatsApp chat", context: .test())
        XCTAssertEqual(planJohn?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let targetJohn) = planJohn?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(targetJohn.recipient.rawQuery, "John")
    }

    func testParsesOpenChatWithPhraseArbitraryName() {
        let plan = parser.parse("Open WhatsApp chat with Priya", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Priya")
        XCTAssertEqual(target.recipient.resolvedContact?.name, "Priya")
    }

    func testParsesMultiWordContactNames() {
        let messagePlan = parser.parse("Message Rahul Kumar saying hello", context: .test())
        XCTAssertEqual(messagePlan?.steps.first?.intent.identifier, .whatsAppSendMessage)
        guard case .whatsAppMessage(let messageTarget) = messagePlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(messageTarget.recipient.rawQuery, "Rahul Kumar")
        XCTAssertEqual(messageTarget.message, "hello")
        XCTAssertEqual(messageTarget.recipient.resolvedContact?.phoneNumber, "14155555554")

        let chatPlan = parser.parse("Open Rahul Kumar's WhatsApp chat", context: .test())
        XCTAssertEqual(chatPlan?.steps.first?.intent.identifier, .whatsAppOpenChat)
        guard case .whatsAppChat(let chatTarget) = chatPlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppChat argument")
        }
        XCTAssertEqual(chatTarget.recipient.rawQuery, "Rahul Kumar")
    }

    func testParsesInformalContactNames() {
        let momPlan = parser.parse("Message Mom saying hello", context: .test())
        guard case .whatsAppMessage(let momTarget) = momPlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(momTarget.recipient.rawQuery, "Mom")
        XCTAssertEqual(momTarget.message, "hello")

        let dadPlan = parser.parse("Message Dad that I'll be home soon", context: .test())
        guard case .whatsAppMessage(let dadTarget) = dadPlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(dadTarget.recipient.rawQuery, "Dad")
        XCTAssertEqual(dadTarget.message, "I'll be home soon")
    }

    func testMessageContentContainingDelimiterPreservesRecipient() {
        let plan = parser.parse("Message Tarun that I told Rahul that I'm running late", context: .test())
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Tarun")
        XCTAssertEqual(target.message, "I told Rahul that I'm running late")
    }

    func testMessageContentContainingAndPreservesRecipientAndMessage() {
        let plan = parser.parse("Message Rahul saying I'll call you and let you know", context: .test())
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        XCTAssertEqual(target.recipient.rawQuery, "Rahul")
        XCTAssertEqual(target.message, "I'll call you and let you know")
    }

    // MARK: - Ambiguous Contact Parsing

    func testAmbiguousContactIsCapturedInPlan() {
        let plan = parser.parse("message David saying hello", context: .test())
        XCTAssertNotNil(plan)
        guard case .whatsAppMessage(let target) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected whatsAppMessage argument")
        }
        if case .ambiguous(let matches) = target.recipient.resolution {
            XCTAssertEqual(matches.count, 2)
        } else {
            XCTFail("Expected ambiguous resolution in recipient")
        }
    }

    // MARK: - Conversational Sentences Ignored for Dictation

    func testConversationalPhrasesAreIgnoredForDictation() {
        XCTAssertNil(parser.parse("John sent me a message", context: .test()))
        XCTAssertNil(parser.parse("I use WhatsApp every day", context: .test()))
        XCTAssertNil(parser.parse("Open the door", context: .test()))
        XCTAssertNil(parser.parse("Tell John about WhatsApp", context: .test()))
        XCTAssertNil(parser.parse("message", context: .test()))
    }

    func testNothingParsesWhileCommandModeIsDisabled() {
        let disabledContext = CommandContext.test(isCommandModeEnabled: false)
        XCTAssertNil(parser.parse("message John saying hello", context: disabledContext))
        XCTAssertNil(parser.parse("open John's WhatsApp chat", context: disabledContext))
    }
}
