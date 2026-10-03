import XCTest
@testable import DailyOps

@MainActor
final class CommandConfirmationRouterTests: XCTestCase {
    private let safeIdentifier = CommandIdentifier(rawValue: "command.safe")
    private let sensitiveIdentifier = CommandIdentifier(rawValue: "command.sensitive")
    private let destructiveIdentifier = CommandIdentifier(rawValue: "command.destructive")

    private func registry() -> CommandRegistry {
        CommandRegistry(definitions: [
            CommandDefinition(
                identifier: safeIdentifier,
                name: "Safe Action",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: sensitiveIdentifier,
                name: "Sensitive Action",
                risk: .sensitive,
                confirmation: .optional
            ),
            CommandDefinition(
                identifier: destructiveIdentifier,
                name: "Destructive Action",
                risk: .destructive,
                confirmation: .mandatory
            )
        ])
    }

    private func makeRouter(
        plan: CommandPlan?,
        executors: [CommandExecuting],
        confirmationManager: ConfirmationManaging = ConfirmationManager()
    ) -> CommandRouter {
        CommandRouter(
            parsers: [StubParser(plan: plan)],
            validator: CommandValidator(registry: registry()),
            executors: executors,
            confirmationManager: confirmationManager
        )
    }

    // MARK: - Router Tests

    func testSafeCommandExecutesWithoutConfirmation() {
        let plan = CommandPlan(intent: CommandIntent(identifier: safeIdentifier))
        let executor = FakeExecutor(supportedIdentifiers: [safeIdentifier], feedback: "Safe Executed")
        let router = makeRouter(plan: plan, executors: [executor])

        let result = router.handle("run safe", context: .test())
        XCTAssertEqual(result, .success(message: "Safe Executed"))
        XCTAssertEqual(executor.executed.count, 1)
        XCTAssertNil(router.pendingConfirmation)
    }

    func testConfirmationRequiredCommandDoesNotExecuteImmediately() {
        let plan = CommandPlan(intent: CommandIntent(identifier: destructiveIdentifier))
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Should not run")
        let router = makeRouter(plan: plan, executors: [executor])

        let result = router.handle("delete everything", context: .test())
        XCTAssertTrue(executor.executed.isEmpty, "Executor must not be invoked before confirmation")
        XCTAssertNotNil(router.pendingConfirmation)
        XCTAssertEqual(router.pendingConfirmation?.plan, plan)

        guard case .confirmationRequired(let returnedPlan, _) = result else {
            return XCTFail("Expected .confirmationRequired, got \(result)")
        }
        XCTAssertEqual(returnedPlan, plan)
    }

    func testConfirmationRequiredCommandReturnsConfirmationRequired() {
        let plan = CommandPlan(intent: CommandIntent(identifier: sensitiveIdentifier))
        let executor = FakeExecutor(supportedIdentifiers: [sensitiveIdentifier])
        let router = makeRouter(plan: plan, executors: [executor])

        let result = router.handle("do sensitive", context: .test())
        guard case .confirmationRequired(let returnedPlan, let message) = result else {
            return XCTFail("Expected .confirmationRequired, got \(result)")
        }
        XCTAssertEqual(returnedPlan, plan)
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(executor.executed.isEmpty)
    }

    func testConfirmingExecutesTheExactPendingCommand() {
        let plan = CommandPlan(intent: CommandIntent(identifier: destructiveIdentifier))
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Action Completed")
        let router = makeRouter(plan: plan, executors: [executor])

        _ = router.handle("trigger action", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation to be created")
        }

        XCTAssertTrue(executor.executed.isEmpty, "Must not execute prior to confirm()")

        let confirmResult = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Action Completed"))
        XCTAssertEqual(executor.executed.count, 1)
        XCTAssertEqual(executor.executed.first?.identifier, destructiveIdentifier)
        XCTAssertNil(router.pendingConfirmation, "Pending confirmation should be cleared")
    }

    func testCancellingNeverExecutes() {
        let plan = CommandPlan(intent: CommandIntent(identifier: destructiveIdentifier))
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Should never run")
        let router = makeRouter(plan: plan, executors: [executor])

        _ = router.handle("trigger action", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let cancelResult = router.cancel(id: pending.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))
        XCTAssertTrue(executor.executed.isEmpty, "Executor must never run when cancelled")
        XCTAssertNil(router.pendingConfirmation)
    }

    func testStaleConfirmationCannotExecuteANewerCommand() {
        let planA = CommandPlan(intent: CommandIntent(identifier: sensitiveIdentifier))
        let executorSensitive = FakeExecutor(supportedIdentifiers: [sensitiveIdentifier], feedback: "Sensitive Ran")
        let executorDestructive = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Destructive Ran")

        let manager = ConfirmationManager()
        let router = makeRouter(
            plan: planA,
            executors: [executorSensitive, executorDestructive],
            confirmationManager: manager
        )

        // First command
        _ = router.handle("first sensitive", context: .test())
        guard let firstPending = router.pendingConfirmation else {
            return XCTFail("Expected first pending confirmation")
        }
        let staleId = firstPending.id

        // Second command replaces the first
        let planB = CommandPlan(intent: CommandIntent(identifier: destructiveIdentifier))
        _ = router.run(planB, context: .test())
        guard let secondPending = router.pendingConfirmation else {
            return XCTFail("Expected second pending confirmation")
        }
        XCTAssertNotEqual(staleId, secondPending.id)

        // Attempting to confirm with the stale first ID must fail and execute nothing
        let staleConfirmResult = router.confirm(id: staleId, context: .test())
        guard case .failure = staleConfirmResult else {
            return XCTFail("Stale confirmation must be rejected as failure")
        }
        XCTAssertTrue(executorSensitive.executed.isEmpty, "First executor must not have run")
        XCTAssertTrue(executorDestructive.executed.isEmpty, "Second executor must not have run yet")

        // Confirming with the valid second ID executes the second plan
        let validConfirmResult = router.confirm(id: secondPending.id, context: .test())
        XCTAssertEqual(validConfirmResult, .success(message: "Destructive Ran"))
        XCTAssertTrue(executorSensitive.executed.isEmpty)
        XCTAssertEqual(executorDestructive.executed.count, 1)
    }

    func testDuplicateConfirmDoesNotExecuteTwice() {
        let plan = CommandPlan(intent: CommandIntent(identifier: destructiveIdentifier))
        let executor = FakeExecutor(supportedIdentifiers: [destructiveIdentifier], feedback: "Ran Once")
        let router = makeRouter(plan: plan, executors: [executor])

        _ = router.handle("action", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let firstConfirm = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(firstConfirm, .success(message: "Ran Once"))
        XCTAssertEqual(executor.executed.count, 1)

        // Second confirm must be rejected
        let secondConfirm = router.confirm(id: pending.id, context: .test())
        guard case .failure = secondConfirm else {
            return XCTFail("Duplicate confirmation must be rejected")
        }
        XCTAssertEqual(executor.executed.count, 1, "Executor must not run a second time")
    }

    // MARK: - Standard Commands Confirmation Tests (.appQuit & .clipboardClear)

    func testAppQuitCommandRequiresConfirmationAndDoesNotExecuteBeforeApproval() {
        let app = ApplicationReference(displayName: "Safari", bundleURL: nil)
        let plan = CommandPlan(intent: CommandIntent(identifier: .appQuit, arguments: .application(app)))
        let executor = FakeExecutor(supportedIdentifiers: [.appQuit], feedback: "Quit Safari")
        let confirmationManager = ConfirmationManager()
        let router = CommandRouter(
            parsers: [StubParser(plan: plan)],
            validator: CommandValidator(registry: .standard()),
            executors: [executor],
            confirmationManager: confirmationManager
        )

        let result = router.handle("quit Safari", context: .test())
        XCTAssertTrue(executor.executed.isEmpty, "App quit must NOT execute before confirmation")
        guard case .confirmationRequired(let pendingPlan, _) = result else {
            return XCTFail("Expected .confirmationRequired for app quit")
        }
        XCTAssertEqual(pendingPlan, plan)
        XCTAssertNotNil(router.pendingConfirmation)
        XCTAssertEqual(router.pendingConfirmation?.confirmActionLabel, "Quit")

        // Confirm executes exactly once
        let confirmResult = router.confirm(id: router.pendingConfirmation!.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Quit Safari"))
        XCTAssertEqual(executor.executed.count, 1)

        // Stale confirmation rejected
        let staleConfirm = router.confirm(id: ConfirmationRequestID(), context: .test())
        guard case .failure = staleConfirm else {
            return XCTFail("Stale confirm must fail")
        }
        XCTAssertEqual(executor.executed.count, 1)
    }

    func testAppQuitCancellationExecutesZeroTimes() {
        let app = ApplicationReference(displayName: "Slack", bundleURL: nil)
        let plan = CommandPlan(intent: CommandIntent(identifier: .appQuit, arguments: .application(app)))
        let executor = FakeExecutor(supportedIdentifiers: [.appQuit], feedback: "Quit Slack")
        let confirmationManager = ConfirmationManager()
        let router = CommandRouter(
            parsers: [StubParser(plan: plan)],
            validator: CommandValidator(registry: .standard()),
            executors: [executor],
            confirmationManager: confirmationManager
        )

        _ = router.handle("quit Slack", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation for quit Slack")
        }

        let cancelResult = router.cancel(id: pending.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))
        XCTAssertTrue(executor.executed.isEmpty, "Cancelled quit must execute zero times")
        XCTAssertNil(router.pendingConfirmation)
    }

    func testClipboardClearRequiresConfirmationAndDoesNotExecuteBeforeApproval() {
        let plan = CommandPlan(intent: CommandIntent(identifier: .clipboardClear))
        let executor = FakeExecutor(supportedIdentifiers: [.clipboardClear], feedback: "Clipboard Cleared")
        let confirmationManager = ConfirmationManager()
        let router = CommandRouter(
            parsers: [StubParser(plan: plan)],
            validator: CommandValidator(registry: .standard()),
            executors: [executor],
            confirmationManager: confirmationManager
        )

        let result = router.handle("clear clipboard", context: .test())
        XCTAssertTrue(executor.executed.isEmpty, "Clipboard clear must not execute before confirmation")
        guard case .confirmationRequired(let pendingPlan, _) = result else {
            return XCTFail("Expected .confirmationRequired for clipboard clear")
        }
        XCTAssertEqual(pendingPlan, plan)
        XCTAssertNotNil(router.pendingConfirmation)
        XCTAssertEqual(router.pendingConfirmation?.confirmActionLabel, "Clear")

        // Cancel test
        let cancelResult = router.cancel(id: router.pendingConfirmation!.id)
        XCTAssertEqual(cancelResult, .success(message: "Cancelled"))
        XCTAssertTrue(executor.executed.isEmpty, "Cancelled clear clipboard must not execute")
    }

    func testClipboardClearConfirmExecutesExactlyOnce() {
        let plan = CommandPlan(intent: CommandIntent(identifier: .clipboardClear))
        let executor = FakeExecutor(supportedIdentifiers: [.clipboardClear], feedback: "Clipboard Cleared")
        let confirmationManager = ConfirmationManager()
        let router = CommandRouter(
            parsers: [StubParser(plan: plan)],
            validator: CommandValidator(registry: .standard()),
            executors: [executor],
            confirmationManager: confirmationManager
        )

        _ = router.handle("clear clipboard", context: .test())
        guard let pending = router.pendingConfirmation else {
            return XCTFail("Expected pending confirmation")
        }

        let confirmResult = router.confirm(id: pending.id, context: .test())
        XCTAssertEqual(confirmResult, .success(message: "Clipboard Cleared"))
        XCTAssertEqual(executor.executed.count, 1)

        let duplicateConfirm = router.confirm(id: pending.id, context: .test())
        guard case .failure = duplicateConfirm else {
            return XCTFail("Duplicate confirm must fail")
        }
        XCTAssertEqual(executor.executed.count, 1)
    }
}
