import XCTest
@testable import DailyOps

@MainActor
final class MultiStepConfirmationTests: XCTestCase {
    private var appControl: FakeApplicationControl!
    private var whatsAppControl: FakeWhatsAppControl!
    private var router: CommandRouter!

    override func setUp() async throws {
        try await super.setUp()
        appControl = FakeApplicationControl()
        whatsAppControl = FakeWhatsAppControl()

        let appExecutor = ApplicationCommandExecutor(control: appControl)
        let whatsAppExecutor = WhatsAppCommandExecutor(control: whatsAppControl)

        router = CommandRouter(
            parsers: [],
            validator: CommandValidator(registry: .standard()),
            executors: [appExecutor, whatsAppExecutor]
        )
    }

    private func createMixedPlan() -> CommandPlan {
        let contact = WhatsAppContact(name: "Alice", phoneNumber: "14155552222")
        let messageTarget = WhatsAppMessageTarget(
            recipient: WhatsAppRecipient(rawQuery: "Alice", resolution: .resolved(contact)),
            message: "See you soon"
        )

        return CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Google Chrome"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .whatsAppSendMessage,
                arguments: .whatsAppMessage(messageTarget)
            ))
        ])
    }

    func testSafeStepRunsImmediatelyWhileConfirmationStepHalts() {
        let plan = createMixedPlan()
        let result = router.run(plan, context: .test())

        guard case .confirmationRequired = result else {
            return XCTFail("Expected confirmationRequired for mixed multi-step plan")
        }

        // Safe step 1 ran immediately
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(appControl.launched.first?.displayName, "Google Chrome")

        // Dangerous step 2 has NOT run yet
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)

        // Pending confirmation is created for remaining step(s)
        XCTAssertNotNil(router.pendingConfirmation)
        XCTAssertEqual(router.pendingConfirmation?.title, "Send WhatsApp message?")
    }

    func testConfirmingPendingStepExecutesRemainingAction() {
        let plan = createMixedPlan()
        _ = router.run(plan, context: .test())

        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let confirmResult = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Prepared WhatsApp message for Alice"))

        // Step 2 now executed
        XCTAssertEqual(whatsAppControl.openedURLs.count, 1)
        XCTAssertTrue(whatsAppControl.openedURLs.first?.absoluteString.contains("See%20you%20soon") ?? false)
        XCTAssertNil(router.pendingConfirmation)
    }

    func testCancellingPendingStepLeavesSafeStepDoneAndDropsRemainingStep() {
        let plan = createMixedPlan()
        _ = router.run(plan, context: .test())

        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let cancelResult = router.cancel(id: pending.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))

        // Step 1 remains completed
        XCTAssertEqual(appControl.launched.count, 1)

        // Step 2 was never executed
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)
        XCTAssertNil(router.pendingConfirmation)
    }

    func testStaleConfirmationCannotExecuteNewerPlan() {
        let planA = createMixedPlan()
        _ = router.run(planA, context: .test())
        guard let pendingA = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation for plan A")
        }

        // Plan B arrives and invalidates plan A
        let planB = createMixedPlan()
        _ = router.run(planB, context: .test())

        // Confirming replaced plan A fails because it was invalidated
        let replacedConfirm = router.confirm(id: pendingA.id, context: .test())
        XCTAssertEqual(replacedConfirm, .failure(message: "Confirmation request has already been resolved."))

        // Confirming an unknown/stale ID fails with staleId
        let staleConfirm = router.confirm(id: ConfirmationRequestID(), context: .test())
        XCTAssertEqual(staleConfirm, .failure(message: "Confirmation request is stale."))

        // Step 2 was not executed for plan A
        XCTAssertEqual(whatsAppControl.openedURLs.count, 0)
    }

    func testDuplicateConfirmationCannotExecuteTwice() {
        let plan = createMixedPlan()
        _ = router.run(plan, context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let firstConfirm = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(firstConfirm, .success(message: "Prepared WhatsApp message for Alice"))

        let secondConfirm = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(secondConfirm, .failure(message: "Confirmation request has already been resolved."))

        XCTAssertEqual(whatsAppControl.openedURLs.count, 1)
    }
}
