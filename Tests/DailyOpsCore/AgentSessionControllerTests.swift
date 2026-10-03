import Testing
import Foundation
@testable import DailyOps

@Suite("AgentSessionController Tests")
@MainActor
struct AgentSessionControllerTests {

    @Test("AgentSessionController submission produces plan and updates state")
    func submitGoalBasic() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )
        session.setRole(.developer)

        let result = await session.submitGoal("start my workday")

        #expect(result.error == nil)
        #expect(result.plan != nil)
        #expect(session.currentGoal != nil)
        #expect(session.currentPlan != nil)
        #expect(session.routingDecision != nil)
        #expect(session.error == nil)
        #expect(session.isProcessing == false)
        #expect(session.planTasks.count >= 6)
    }

    @Test("Role switching updates activeRole and reflects in planned tasks")
    func roleSwitchingAffectsPlanning() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )

        // 1. Submit as Developer
        session.setRole(.developer)
        #expect(session.activeRole == .developer)
        let devResult = await session.submitGoal("start my workday")
        let devTasks = devResult.plan?.tasks.map { $0.title } ?? []

        // Developer plan includes development tasks and blockers
        #expect(devTasks.contains("Check active development tasks"))
        #expect(devTasks.contains("Review today's schedule"))

        // 2. Switch to Manager
        session.setRole(.manager)
        #expect(session.activeRole == .manager)
        let mgrResult = await session.submitGoal("start my workday")
        let mgrTasks = mgrResult.plan?.tasks.map { $0.title } ?? []

        // Manager plan includes meetings and approvals
        #expect(mgrTasks.contains("Review today's meetings"))
        #expect(mgrTasks.contains("Review pending approvals"))
        #expect(mgrTasks.contains("Check team blockers"))

        // Ensure plans are visibly and functionally different
        #expect(devTasks != mgrTasks)

        // 3. Switch to Designer
        session.setRole(.designer)
        #expect(session.activeRole == .designer)
        let desResult = await session.submitGoal("start my workday")
        let desTasks = desResult.plan?.tasks.map { $0.title } ?? []
        #expect(desTasks.contains("Review design tasks"))

        // 4. Switch to General
        session.setRole(.general)
        #expect(session.activeRole == .general)
        let genResult = await session.submitGoal("start my workday")
        let genTasks = genResult.plan?.tasks.map { $0.title } ?? []
        #expect(genTasks.contains("Review schedule"))
    }

    @Test("Demo 2: prepare me for tomorrow's review routes to L4 and creates role-aware plan")
    func prepareForReviewDemo() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )

        // Developer Review Prep
        session.setRole(.developer)
        let devResult = await session.submitGoal("prepare me for tomorrow's review")
        #expect(devResult.error == nil)
        #expect(devResult.routingDecision.level == .L4)
        #expect(session.routingDecision?.level == .L4)
        let devTasks = devResult.plan?.tasks.map { $0.title } ?? []
        #expect(devTasks.contains("Gather recent commits"))
        #expect(devTasks.contains("Run test suite"))

        // Manager Review Prep
        session.setRole(.manager)
        let mgrResult = await session.submitGoal("prepare me for tomorrow's review")
        #expect(mgrResult.error == nil)
        #expect(mgrResult.routingDecision.level == .L4)
        let mgrTasks = mgrResult.plan?.tasks.map { $0.title } ?? []
        #expect(mgrTasks.contains("Review team metrics"))
        #expect(mgrTasks.contains("Gather project status"))

        #expect(devTasks != mgrTasks)
    }

    @Test("Routing information and execution state propagate correctly")
    func routingAndExecutionStatePropagation() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )
        session.setRole(.developer)

        _ = await session.submitGoal("start my workday")

        #expect(session.routingDecision != nil)
        #expect(session.routingDecision?.level == .L4)
        #expect(session.routingDecision?.reason.isEmpty == false)
        #expect(session.executionState == .notStarted || session.executionState == .inProgress)
    }

    @Test("Activity stages reflect real deterministic pipeline events")
    func activityStagesRecorded() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )
        session.setRole(.developer)

        _ = await session.submitGoal("start my workday")

        let stageKinds = session.activityStages.map { $0.stage }
        #expect(stageKinds.contains(.goalUnderstood))
        #expect(stageKinds.contains(.roleContextLoaded))
        #expect(stageKinds.contains(.complexityEvaluated))
        #expect(stageKinds.contains(.planCreated))
        #expect(stageKinds.contains(.permissionsEvaluated))
        #expect(stageKinds.contains(.planVerified))
    }

    @Test("Session reset clears current goal and plan state")
    func sessionResetClearsState() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )
        session.setRole(.developer)

        _ = await session.submitGoal("start my workday")
        #expect(session.currentPlan != nil)
        #expect(session.activityStages.isEmpty == false)

        session.resetSession()
        #expect(session.currentGoal == nil)
        #expect(session.currentPlan == nil)
        #expect(session.routingDecision == nil)
        #expect(session.activityStages.isEmpty)
        #expect(session.error == nil)
    }

    @Test("Empty goal submission returns error and fails safely")
    func emptyGoalHandling() async {
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )

        let result = await session.submitGoal("   ")
        #expect(result.error != nil)
        #expect(session.error != nil)
        #expect(session.currentPlan == nil)
    }

    @Test("AgentActivation preserves normal dictation and only triggers on explicit goals")
    func agentActivationPreservesNormalDictation() {
        // Critical safety rule: normal dictation must NOT become an agent goal
        #expect(AgentActivation.matchGoal("Hello this is a test") == nil)
        #expect(AgentActivation.matchGoal("Testing one two three.") == nil)
        #expect(AgentActivation.matchGoal("Can we schedule a meeting?") == nil)
        #expect(AgentActivation.matchGoal("I need to review the document") == nil)
        #expect(AgentActivation.matchGoal("") == nil)

        // Explicit activation phrases MUST be recognized
        #expect(AgentActivation.matchGoal("start my workday") == "Start my workday")
        #expect(AgentActivation.matchGoal("Start my workday.") == "Start my workday")
        #expect(AgentActivation.matchGoal("begin workday") == "Start my workday")
        #expect(AgentActivation.matchGoal("prepare me for tomorrow's review") == "Prepare me for tomorrow's review")
        #expect(AgentActivation.matchGoal("prepare me for tomorrows review.") == "Prepare me for tomorrow's review")
        #expect(AgentActivation.matchGoal("prepare for tomorrow's review") == "Prepare me for tomorrow's review")
    }
}
