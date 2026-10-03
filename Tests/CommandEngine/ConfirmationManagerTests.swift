import XCTest
@testable import DailyOps

@MainActor
final class ConfirmationManagerTests: XCTestCase {
    private let probeIdentifier = CommandIdentifier(rawValue: "test.probe")

    private var samplePlan: CommandPlan {
        CommandPlan(intent: CommandIntent(identifier: probeIdentifier))
    }

    private var sampleDefinition: CommandDefinition {
        CommandDefinition(
            identifier: probeIdentifier,
            name: "Probe Command",
            risk: .sensitive,
            confirmation: .mandatory
        )
    }

    // MARK: - Lifecycle & Exposure

    func testCreatesPendingConfirmation() {
        let manager = ConfirmationManager()
        XCTAssertNil(manager.pendingConfirmation)

        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Probe needs confirmation."
        )

        XCTAssertEqual(request.title, "Probe Command")
        XCTAssertEqual(request.details, "Probe needs confirmation.")
        XCTAssertEqual(request.risk, .sensitive)
        XCTAssertEqual(request.plan, samplePlan)
    }

    func testExposesPendingConfirmation() {
        let manager = ConfirmationManager()
        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Waiting for approval"
        )

        XCTAssertNotNil(manager.pendingConfirmation)
        XCTAssertEqual(manager.pendingConfirmation?.id, request.id)
        XCTAssertEqual(manager.pendingConfirmation?.title, "Probe Command")
    }

    // MARK: - Exact-Once Resolution

    func testConfirmResolvesOnce() {
        let manager = ConfirmationManager()
        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Needs approval"
        )

        let resolution = manager.resolve(id: request.id, decision: .confirm)
        XCTAssertEqual(resolution, .confirmed(request))
        XCTAssertNil(manager.pendingConfirmation, "Pending confirmation should be cleared after resolution")
    }

    func testCancelResolvesOnce() {
        let manager = ConfirmationManager()
        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Needs approval"
        )

        let resolution = manager.resolve(id: request.id, decision: .cancel)
        XCTAssertEqual(resolution, .cancelled(request))
        XCTAssertNil(manager.pendingConfirmation, "Pending confirmation should be cleared after cancellation")
    }

    // MARK: - Rejection Cases

    func testDuplicateConfirmRejected() {
        let manager = ConfirmationManager()
        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Needs approval"
        )

        let firstResolution = manager.resolve(id: request.id, decision: .confirm)
        XCTAssertEqual(firstResolution, .confirmed(request))

        let secondResolution = manager.resolve(id: request.id, decision: .confirm)
        XCTAssertEqual(secondResolution, .rejected(.alreadyResolved))
    }

    func testDuplicateCancelRejected() {
        let manager = ConfirmationManager()
        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Needs approval"
        )

        let firstResolution = manager.resolve(id: request.id, decision: .cancel)
        XCTAssertEqual(firstResolution, .cancelled(request))

        let secondResolution = manager.resolve(id: request.id, decision: .cancel)
        XCTAssertEqual(secondResolution, .rejected(.alreadyResolved))
    }

    func testStaleConfirmationIDRejected() {
        let manager = ConfirmationManager()
        _ = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Active request"
        )

        let staleId = ConfirmationRequestID()
        let resolution = manager.resolve(id: staleId, decision: .confirm)
        XCTAssertEqual(resolution, .rejected(.staleId))
    }

    func testReplacingPendingConfirmationInvalidatesTheOldRequest() {
        let manager = ConfirmationManager()
        let firstRequest = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "First request"
        )

        let secondPlan = CommandPlan(intent: CommandIntent(identifier: .appQuit))
        let secondDefinition = CommandDefinition(
            identifier: .appQuit,
            name: "Quit App",
            risk: .destructive,
            confirmation: .mandatory
        )
        let secondRequest = manager.requestConfirmation(
            for: secondPlan,
            definition: secondDefinition,
            context: .test(),
            reason: "Second request"
        )

        XCTAssertEqual(manager.pendingConfirmation?.id, secondRequest.id)

        // Attempting to resolve the replaced (stale) first request must be rejected
        let staleResolution = manager.resolve(id: firstRequest.id, decision: .confirm)
        XCTAssertEqual(staleResolution, .rejected(.alreadyResolved))

        // Second request can still be resolved cleanly
        let validResolution = manager.resolve(id: secondRequest.id, decision: .confirm)
        XCTAssertEqual(validResolution, .confirmed(secondRequest))
    }

    func testNoPendingConfirmationCannotBeConfirmed() {
        let manager = ConfirmationManager()
        XCTAssertNil(manager.pendingConfirmation)

        let arbitraryId = ConfirmationRequestID()
        let resolution = manager.resolve(id: arbitraryId, decision: .confirm)
        XCTAssertEqual(resolution, .rejected(.noPendingRequest))
    }

    func testNoPendingConfirmationCannotBeCancelled() {
        let manager = ConfirmationManager()
        XCTAssertNil(manager.pendingConfirmation)

        let arbitraryId = ConfirmationRequestID()
        let resolution = manager.resolve(id: arbitraryId, decision: .cancel)
        XCTAssertEqual(resolution, .rejected(.noPendingRequest))
    }

    func testCancelCurrentClearsPendingAndPreventsLaterApproval() {
        let manager = ConfirmationManager()
        let request = manager.requestConfirmation(
            for: samplePlan,
            definition: sampleDefinition,
            context: .test(),
            reason: "Waiting"
        )

        manager.cancelCurrent()
        XCTAssertNil(manager.pendingConfirmation)

        let laterResolution = manager.resolve(id: request.id, decision: .confirm)
        XCTAssertEqual(laterResolution, .rejected(.alreadyResolved))
    }
}
