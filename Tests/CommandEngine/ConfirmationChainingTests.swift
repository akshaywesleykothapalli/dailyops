import XCTest
import SwiftData
@testable import DailyOps

@MainActor
final class ConfirmationChainingTests: XCTestCase {
    private let ids = (1...3).map { CommandIdentifier(rawValue: "chain.sensitive.\($0)") }

    private func makeController() throws -> (DictationController, FakeExecutor, ChainParser) {
        let registry = CommandRegistry(definitions: ids.map {
            CommandDefinition(identifier: $0, name: "Sensitive Action", risk: .sensitive, confirmation: .mandatory)
        })
        let plan = CommandPlan(steps: ids.map { CommandStep(intent: CommandIntent(identifier: $0)) })
        let parser = ChainParser(plan: plan)
        let executor = FakeExecutor(supportedIdentifiers: Set(ids))
        let engine = CommandEngine(router: CommandRouter(
            parsers: [parser], validator: CommandValidator(registry: registry), executors: [executor]
        ))
        let container = try ModelContainer(for: DictationEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let controller = DictationController(history: HistoryStore(container: container), commandEngine: engine)
        _ = engine.process("do chain", context: .test())
        controller.presentPendingConfirmation()
        return (controller, executor, parser)
    }

    private func displayed(_ controller: DictationController) throws -> ConfirmationRequest {
        let pending = try XCTUnwrap(controller.commandEngine.pendingConfirmation)
        XCTAssertEqual(controller.state, .confirming(pending), "HUD must display the exact engine-owned request")
        return pending
    }

    func testConfirmFirstDisplaysExactSecondRequest() throws {
        let (controller, executor, parser) = try makeController()
        let first = try displayed(controller)
        XCTAssertTrue(executor.executed.isEmpty)
        XCTAssertTrue(controller.confirmPending(id: first.id))
        let second = try displayed(controller)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.plan, CommandPlan(steps: Array(first.plan.steps.dropFirst())))
        XCTAssertEqual(executor.executed.map(\.identifier), [ids[0]])
        XCTAssertEqual(parser.calls, 1, "Approval must never reparse speech")
    }

    func testCancelSecondRejectsDuplicateAndNeverExecutesRemainder() throws {
        let (controller, executor, _) = try makeController()
        let first = try displayed(controller)
        controller.confirmPending(id: first.id)
        let second = try displayed(controller)
        XCTAssertTrue(controller.cancelPending(id: second.id))
        XCTAssertFalse(controller.cancelPending(id: second.id))
        XCTAssertFalse(controller.confirmPending(id: second.id))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.commandEngine.pendingConfirmation)
        XCTAssertEqual(executor.executed.count, 1)
    }

    func testStaleAndDuplicateFirstDecisionsPreserveSecond() throws {
        let (controller, executor, _) = try makeController()
        let first = try displayed(controller)
        controller.confirmPending(id: first.id)
        let second = try displayed(controller)
        XCTAssertFalse(controller.confirmPending(id: first.id))
        XCTAssertFalse(controller.cancelPending(id: first.id))
        guard case .failure = controller.commandEngine.confirm(id: first.id, context: .test()) else {
            return XCTFail("Engine must also reject a resolved ID")
        }
        XCTAssertEqual(try displayed(controller), second)
        XCTAssertEqual(executor.executed.count, 1)
    }

    func testThreeSensitiveBoundariesLoseNoRequestsOrReparsePlans() throws {
        let (controller, executor, parser) = try makeController()
        var seen = Set<ConfirmationRequestID>()
        for index in 0..<3 {
            let request = try displayed(controller)
            XCTAssertTrue(seen.insert(request.id).inserted)
            XCTAssertEqual(request.plan.steps.map { $0.intent.identifier }, Array(ids[index...]))
            XCTAssertEqual(executor.executed.count, index)
            XCTAssertTrue(controller.confirmPending(id: request.id))
        }
        XCTAssertEqual(controller.state, .done)
        XCTAssertNil(controller.commandEngine.pendingConfirmation)
        XCTAssertEqual(executor.executed.map(\.identifier), ids)
        XCTAssertEqual(parser.calls, 1)
        for id in seen { XCTAssertFalse(controller.confirmPending(id: id)) }
        XCTAssertEqual(executor.executed.count, 3)
    }
}

@MainActor
private final class ChainParser: CommandParsing {
    let plan: CommandPlan
    var calls = 0
    init(plan: CommandPlan) { self.plan = plan }
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        calls += 1
        return plan
    }
}
