import XCTest
@testable import DailyOps

@MainActor
final class DictationConfirmationIntegrationTests: XCTestCase {
    private let safeIdentifier = CommandIdentifier(rawValue: "command.safe")
    private let destructiveIdentifier = CommandIdentifier(rawValue: "command.destructive")

    private func makeEngine(executor: FakeExecutor) -> CommandEngine {
        let registry = CommandRegistry(definitions: [
            CommandDefinition(
                identifier: safeIdentifier,
                name: "Safe Command",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: destructiveIdentifier,
                name: "Destructive Command",
                risk: .destructive,
                confirmation: .mandatory
            )
        ])

        let parser = StubMapParser(mapping: [
            "open safe": CommandPlan(intent: CommandIntent(identifier: safeIdentifier)),
            "delete all": CommandPlan(intent: CommandIntent(identifier: destructiveIdentifier))
        ])

        let router = CommandRouter(
            parsers: [parser],
            validator: CommandValidator(registry: registry),
            executors: [executor]
        )

        return CommandEngine(router: router)
    }

    // MARK: - Engine Process Integration Tests

    func testSafeRecognizedCommandReturnsExecutedOutcome() {
        let executor = FakeExecutor(supportedIdentifiers: [safeIdentifier], feedback: "Safe Completed")
        let engine = makeEngine(executor: executor)

        let outcome = engine.process("open safe", context: .test())
        XCTAssertEqual(outcome, .executed(feedback: "Safe Completed"))
        XCTAssertEqual(executor.executed.count, 1)
    }

    func testConfirmationRequiredCommandReturnsConfirmationRequiredAndHaltsExecution() {
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Should not run")
        let engine = makeEngine(executor: executor)

        let outcome = engine.process("delete all", context: .test())
        XCTAssertTrue(executor.executed.isEmpty, "Command requiring confirmation must not execute before approval")

        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected .confirmationRequired, got \(outcome)")
        }
        XCTAssertEqual(request.title, "Destructive Command")
        XCTAssertEqual(request.risk, .destructive)
        XCTAssertEqual(request.confirmActionLabel, "Confirm")
    }

    func testUnrecognizedSentenceReturnsIgnoredForNormalDictation() {
        let executor = FakeExecutor(supportedIdentifiers: [safeIdentifier, destructiveIdentifier])
        let engine = makeEngine(executor: executor)

        let outcome = engine.process("Please remind me to buy milk tomorrow.", context: .test())
        XCTAssertEqual(outcome, .ignored, "Unrecognized speech must be ignored so normal dictation can insert text")
        XCTAssertTrue(executor.executed.isEmpty)
    }

    func testApprovingPendingConfirmationTriggersExecutionOfExactPlan() {
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Deleted")
        let engine = makeEngine(executor: executor)

        let outcome = engine.process("delete all", context: .test())
        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected confirmation required")
        }
        XCTAssertTrue(executor.executed.isEmpty)

        let result = engine.confirm(id: request.id, context: .test())
        XCTAssertEqual(result, .success(message: "Deleted"))
        XCTAssertEqual(executor.executed.count, 1)
        XCTAssertEqual(executor.executed.first?.identifier, destructiveIdentifier)
    }

    func testCancellingPendingConfirmationDoesNotExecute() {
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier])
        let engine = makeEngine(executor: executor)

        let outcome = engine.process("delete all", context: .test())
        guard case .confirmationRequired(let request) = outcome else {
            return XCTFail("Expected confirmation required")
        }

        let cancelResult = engine.cancel(id: request.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))
        XCTAssertTrue(executor.executed.isEmpty, "Cancelled confirmation must never execute")
    }

    func testSequentialCommandsInvalidateEarlierPendingConfirmation() {
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Done")
        let engine = makeEngine(executor: executor)

        // First command requiring confirmation
        let outcome1 = engine.process("delete all", context: .test())
        guard case .confirmationRequired(let request1) = outcome1 else {
            return XCTFail("Expected request1")
        }

        // Second command requiring confirmation arrives
        let outcome2 = engine.process("delete all", context: .test())
        guard case .confirmationRequired(let request2) = outcome2 else {
            return XCTFail("Expected request2")
        }

        XCTAssertNotEqual(request1.id, request2.id)

        // Attempting to approve request1 must fail and execute nothing
        let staleResult = engine.confirm(id: request1.id, context: .test())
        guard case .failure = staleResult else {
            return XCTFail("Stale confirmation must fail")
        }
        XCTAssertTrue(executor.executed.isEmpty)

        // Approving request2 succeeds
        let validResult = engine.confirm(id: request2.id, context: .test())
        XCTAssertEqual(validResult, .success(message: "Done"))
        XCTAssertEqual(executor.executed.count, 1)
    }

    func testDictationControllerRejectsMismatchedConfirmPending() {
        let controller = DictationController.shared
        let arbitraryId = ConfirmationRequestID()
        // If state is not confirming with that ID, calling confirmPending must be a no-op
        controller.confirmPending(id: arbitraryId)
        XCTAssertEqual(controller.state, .idle)
    }

    func testDictationControllerRejectsMismatchedCancelPending() {
        let controller = DictationController.shared
        let arbitraryId = ConfirmationRequestID()
        // If state is not confirming with that ID, calling cancelPending must be a no-op
        controller.cancelPending(id: arbitraryId)
        XCTAssertEqual(controller.state, .idle)
    }
}

/// Helper parser mapping exact phrase strings to plans for deterministic testing.
@MainActor
private struct StubMapParser: CommandParsing {
    let mapping: [String: CommandPlan]

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        mapping[transcript]
    }
}
