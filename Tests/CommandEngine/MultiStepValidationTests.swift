import XCTest
@testable import DailyOps

@MainActor
final class MultiStepValidationTests: XCTestCase {
    private var validator: CommandValidator!

    override func setUp() async throws {
        try await super.setUp()
        validator = CommandValidator(registry: .standard())
    }

    func testSafeMultiStepPlanIsApproved() throws {
        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Safari"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .browserOpenURL,
                arguments: .url(URL(string: "https://github.com")!)
            ))
        ])

        let validation = try validator.validate(plan, context: .test())
        XCTAssertEqual(validation, .approved)
    }

    func testPlanWithConfirmationStepRequiresConfirmation() throws {
        let contact = WhatsAppContact(name: "John Appleseed", phoneNumber: "14155551234")
        let target = WhatsAppMessageTarget(
            recipient: WhatsAppRecipient(rawQuery: "John", resolution: .resolved(contact)),
            message: "Hello"
        )
        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Google Chrome"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .whatsAppSendMessage,
                arguments: .whatsAppMessage(target)
            ))
        ])

        let validation = try validator.validate(plan, context: .test())
        guard case .requiresConfirmation(let reason) = validation else {
            return XCTFail("Expected requiresConfirmation for multi-step plan containing message send")
        }
        XCTAssertTrue(reason.contains("Send WhatsApp Message"))
    }

    func testUnknownCommandAtStepTwoRejectsEntirePlan() {
        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Safari"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: CommandIdentifier(rawValue: "unknown.command"),
                arguments: .none
            ))
        ])

        XCTAssertThrowsError(try validator.validate(plan, context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .unknownCommand(CommandIdentifier(rawValue: "unknown.command")))
        }
    }

    func testInvalidArgumentsAtStepTwoRejectsEntirePlan() {
        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Safari"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .browserOpenURL,
                arguments: .none // expected .url
            ))
        ])

        XCTAssertThrowsError(try validator.validate(plan, context: .test())) { error in
            XCTAssertEqual(error as? CommandValidationError, .invalidArguments(.browserOpenURL))
        }
    }

    func testAmbiguousContactAtStepTwoRejectsEntirePlan() {
        let ambiguousTarget = WhatsAppMessageTarget(
            recipient: WhatsAppRecipient(
                rawQuery: "David",
                resolution: .ambiguous([
                    WhatsAppContact(name: "David Miller", phoneNumber: "111"),
                    WhatsAppContact(name: "David Wilson", phoneNumber: "222")
                ])
            ),
            message: "hi"
        )
        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "WhatsApp"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .whatsAppSendMessage,
                arguments: .whatsAppMessage(ambiguousTarget)
            ))
        ])

        XCTAssertThrowsError(try validator.validate(plan, context: .test())) { error in
            guard case .ambiguousRecipient(let query, let matches) = error as? CommandValidationError else {
                return XCTFail("Expected ambiguousRecipient error")
            }
            XCTAssertEqual(query, "David")
            XCTAssertEqual(matches, ["David Miller", "David Wilson"])
        }
    }
}
