import XCTest
@testable import DailyOps

@MainActor
final class CommandRouterTests: XCTestCase {
    private let probe = CommandIdentifier(rawValue: "test.probe")

    private func registry(
        risk: CommandRisk = .safe,
        confirmation: ConfirmationRequirement = .none,
        argumentKind: CommandArgumentKind = .none
    ) -> CommandRegistry {
        CommandRegistry(definitions: [
            CommandDefinition(
                identifier: probe,
                name: "Probe",
                risk: risk,
                confirmation: confirmation,
                argumentKind: argumentKind
            )
        ])
    }

    private func router(
        plan: CommandPlan?,
        executors: [CommandExecuting],
        risk: CommandRisk = .safe,
        confirmation: ConfirmationRequirement = .none
    ) -> CommandRouter {
        CommandRouter(
            parsers: [StubParser(plan: plan)],
            validator: CommandValidator(registry: registry(risk: risk, confirmation: confirmation)),
            executors: executors
        )
    }

    private var probePlan: CommandPlan {
        CommandPlan(intent: CommandIntent(identifier: probe))
    }

    // MARK: - Success

    func testSuccessReturnsExecutorFeedback() {
        let executor = FakeExecutor(supportedIdentifiers: [probe], feedback: "Probe ran")
        let router = self.router(plan: probePlan, executors: [executor])

        XCTAssertEqual(router.handle("anything", context: .test()), .success(message: "Probe ran"))
        XCTAssertEqual(executor.executed.count, 1)
        XCTAssertEqual(executor.executed.first?.identifier, probe)
    }

    func testDispatchesToTheExecutorThatClaimsTheIdentifier() {
        let wrong = FakeExecutor(supportedIdentifiers: [.appOpen], feedback: "wrong")
        let right = FakeExecutor(supportedIdentifiers: [probe], feedback: "right")
        let router = self.router(plan: probePlan, executors: [wrong, right])

        XCTAssertEqual(router.handle("anything", context: .test()), .success(message: "right"))
        XCTAssertTrue(wrong.executed.isEmpty)
        XCTAssertEqual(right.executed.count, 1)
    }

    // MARK: - Ignored (§18)

    func testNoPlanIsIgnoredAndNoExecutorRuns() {
        let executor = FakeExecutor(supportedIdentifiers: [probe])
        let router = self.router(plan: nil, executors: [executor])

        XCTAssertEqual(router.handle("Please remind me to buy milk tomorrow.", context: .test()), .ignored)
        XCTAssertTrue(executor.executed.isEmpty)
    }

    /// `.ignored` has to stay distinct from `.failure`: the caller falls back to
    /// dictation on the former and shows an error on the latter.
    func testIgnoredIsNotAFailure() {
        let router = self.router(plan: nil, executors: [])
        let result = router.handle("just some words", context: .test())
        XCTAssertEqual(result, .ignored)
        if case .failure = result { XCTFail("ignored must not be reported as failure") }
    }

    // MARK: - Executor failure

    func testExecutorFailureIsReportedWithItsMessage() {
        let executor = FakeExecutor(
            supportedIdentifiers: [probe],
            errorToThrow: .operationFailed("Calculator would not quit.")
        )
        let router = self.router(plan: probePlan, executors: [executor])

        XCTAssertEqual(
            router.handle("anything", context: .test()),
            .failure(message: "Calculator would not quit.")
        )
    }

    func testMalformedArgumentsAreReportedAsFailure() {
        let executor = FakeExecutor(supportedIdentifiers: [probe], errorToThrow: .malformedArguments(probe))
        let router = self.router(plan: probePlan, executors: [executor])

        guard case .failure = router.handle("anything", context: .test()) else {
            return XCTFail("expected failure")
        }
    }

    func testNoMatchingExecutorIsAFailureNotACrash() {
        let executor = FakeExecutor(supportedIdentifiers: [.appOpen])
        let router = self.router(plan: probePlan, executors: [executor])

        guard case .failure = router.handle("anything", context: .test()) else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(executor.executed.isEmpty)
    }

    func testUnknownCommandNeverReachesAnExecutor() {
        let executor = FakeExecutor(supportedIdentifiers: [probe])
        let router = CommandRouter(
            parsers: [StubParser(plan: probePlan)],
            validator: CommandValidator(registry: CommandRegistry()),
            executors: [executor]
        )

        guard case .failure = router.handle("anything", context: .test()) else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(executor.executed.isEmpty)
    }

    // MARK: - Confirmation

    func testConfirmationRequiredReturnsThePlanAndRunsNothing() {
        let executor = FakeExecutor(supportedIdentifiers: [probe])
        let router = self.router(
            plan: probePlan,
            executors: [executor],
            risk: .destructive,
            confirmation: .mandatory
        )

        guard case .confirmationRequired(let plan, let message) = router.handle("anything", context: .test()) else {
            return XCTFail("expected confirmation")
        }
        XCTAssertEqual(plan, probePlan)
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(executor.executed.isEmpty, "nothing may run before approval")
    }

    /// The returned plan is what an approval surface would re-submit, so
    /// running it must reach the executor without re-parsing.
    func testAnApprovedPlanCanBeRunDirectly() {
        let executor = FakeExecutor(supportedIdentifiers: [probe], feedback: "Probe ran")
        let router = self.router(plan: probePlan, executors: [executor])

        XCTAssertEqual(router.run(probePlan, context: .test()), .success(message: "Probe ran"))
        XCTAssertEqual(executor.executed.count, 1)
    }

    // MARK: - Parser precedence

    func testFirstParserToProduceAPlanWins() {
        let first = CommandPlan(intent: CommandIntent(identifier: probe))
        let second = CommandPlan(intent: CommandIntent(identifier: .appOpen))
        let executor = FakeExecutor(supportedIdentifiers: [probe, .appOpen], feedback: "ran")
        let router = CommandRouter(
            parsers: [StubParser(plan: first), StubParser(plan: second)],
            validator: CommandValidator(registry: registry()),
            executors: [executor]
        )

        _ = router.handle("anything", context: .test())
        XCTAssertEqual(executor.executed.first?.identifier, probe)
    }

    func testLaterParserIsConsultedWhenTheFirstDeclines() {
        let executor = FakeExecutor(supportedIdentifiers: [probe], feedback: "ran")
        let router = CommandRouter(
            parsers: [StubParser(plan: nil), StubParser(plan: probePlan)],
            validator: CommandValidator(registry: registry()),
            executors: [executor]
        )

        XCTAssertEqual(router.handle("anything", context: .test()), .success(message: "ran"))
    }

    // MARK: - Multi-step execution

    func testMultiStepPlanExecutesSequentially() {
        let executor = FakeExecutor(supportedIdentifiers: [probe])
        let multi = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(identifier: probe)),
            CommandStep(intent: CommandIntent(identifier: probe)),
        ])
        let router = self.router(plan: multi, executors: [executor])

        let result = router.handle("anything", context: .test())
        guard case .success = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(executor.executed.count, 2, "both steps should execute from a multi-step plan")
    }
}
