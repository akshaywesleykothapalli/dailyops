import Testing
import Foundation
@testable import DailyOps

@Suite("PlanExecutionLive Tests")
@MainActor
struct PlanExecutionLiveTests {

    @Test("Safe local tool (open safari) executes, emits events, and completes")
    func safeLocalToolExecution() async {
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared,
            executionEngine: PlanExecutionEngine.shared
        )
        session.executionEngine.stepDelayNanoseconds = 0

        let result = await session.submitGoal("open safari")
        #expect(result.error == nil)
        #expect(result.routingDecision.level == .L0)
        #expect(session.planTasks.count == 1)
        #expect(session.planTasks.first?.status == .pending)

        await session.executePlan()

        #expect(session.executionState == .completed)
        #expect(session.planTasks.first?.status == .completed)
        #expect(session.isExecuting == false)
        #expect(session.currentAction == nil)

        let stageKinds = session.activityStages.map { $0.stage }
        #expect(stageKinds.contains(.executionStarted))
        #expect(stageKinds.contains(.toolSelected))
        #expect(stageKinds.contains(.permissionsEvaluated))
        #expect(stageKinds.contains(.taskCompleted))
        #expect(stageKinds.contains(.executionCompleted))
    }

    @Test("Unsupported integrations in complex goals are truthfully marked unsupported")
    func unsupportedIntegrationsReportedTruthfully() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared,
            executionEngine: PlanExecutionEngine.shared
        )
        session.executionEngine.stepDelayNanoseconds = 0
        session.setRole(.developer)

        _ = await session.submitGoal("start my workday")
        #expect(session.planTasks.count >= 6)

        await session.executePlan()

        #expect(session.executionState == .failed)
        #expect(!session.activityStages.contains { $0.stage == .executionCompleted })
        #expect(session.activityStages.contains {
            $0.stage == .executionFailed && $0.detail?.contains("unsupported") == true
        })

        // Verify task 0 (Calendar) is unsupported and not marked completed
        let calendarTask = session.planTasks.first { $0.title == "Review today's schedule" }
        #expect(calendarTask != nil)
        #expect(calendarTask?.status == .unsupported)
        #expect(calendarTask?.status != .completed)
        #expect(calendarTask?.error?.contains("Calendar") == true)

        // Verify task 1 (GitHub) is unsupported
        let githubTask = session.planTasks.first { $0.title == "Check active development tasks" }
        #expect(githubTask != nil)
        #expect(githubTask?.status == .unsupported)
        #expect(githubTask?.status != .completed)

        // Verify task 2 (System status) is completed
        let systemTask = session.planTasks.first { $0.title == "Inspect current project status" }
        #expect(systemTask != nil)
        #expect(systemTask?.status == .completed)

        // Verify activity contains unsupported notifications
        let stageKinds = session.activityStages.map { $0.stage }
        #expect(stageKinds.contains(.taskUnsupported))
    }

    @Test("Confirmation-required action pauses for approval and resumes upon approval")
    func approvalPauseAndResume() async {
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared,
            executionEngine: PlanExecutionEngine.shared
        )
        session.executionEngine.stepDelayNanoseconds = 0

        _ = await session.submitGoal("create a local note")
        #expect(session.planTasks.count == 1)

        // Launch execution in async task
        let executionTask = Task {
            await session.executePlan()
        }

        // Wait until paused for approval
        for _ in 0..<100 {
            if session.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(session.executionState == .waitingForApproval)
        #expect(session.hasPendingApproval == true)
        #expect(session.currentApprovalRequest != nil)
        #expect(session.currentApprovalRequest?.reason == "This action writes persistent data.")
        #expect(session.currentApprovalRequest?.riskLevel == .confirmationRequired)

        // User approves action
        await session.approveCurrentAction()

        // Wait for execution to finish
        await executionTask.value

        #expect(session.executionState == .completed)
        #expect(session.hasPendingApproval == false)
        #expect(session.planTasks.first?.status == .completed)

        let stageKinds = session.activityStages.map { $0.stage }
        #expect(stageKinds.contains(.waitingForApproval))
        #expect(stageKinds.contains(.approvalReceived))
        #expect(stageKinds.contains(.executionCompleted))
    }

    @Test("Confirmation-required action halts safely upon rejection")
    func approvalRejection() async {
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared,
            executionEngine: PlanExecutionEngine.shared
        )
        session.executionEngine.stepDelayNanoseconds = 0

        _ = await session.submitGoal("create a local note")

        let executionTask = Task {
            await session.executePlan()
        }

        for _ in 0..<100 {
            if session.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(session.executionState == .waitingForApproval)

        // User rejects action
        await session.rejectCurrentAction()
        await executionTask.value

        #expect(session.executionState == .failed)
        #expect(session.planTasks.first?.status == .failed)
        #expect(!session.activityStages.contains { $0.stage == .executionCompleted })
    }

    @Test("Duplicate execution is prevented when already executing or waiting for approval")
    func duplicateExecutionPrevention() async {
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared,
            executionEngine: PlanExecutionEngine.shared
        )
        session.executionEngine.stepDelayNanoseconds = 0

        _ = await session.submitGoal("create a local note")

        let executionTask = Task {
            await session.executePlan()
        }

        for _ in 0..<100 {
            if session.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Try to trigger executePlan again while waiting
        await session.executePlan()

        #expect(session.executionState == .waitingForApproval)

        await session.approveCurrentAction()
        await executionTask.value
    }

    @Test("Run again resets tasks and successfully re-executes")
    func runAgainResetsAndReExecutes() async {
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared,
            executionEngine: PlanExecutionEngine.shared
        )
        session.executionEngine.stepDelayNanoseconds = 0

        _ = await session.submitGoal("open safari")
        await session.executePlan()
        #expect(session.executionState == .completed)

        await session.runAgain()
        #expect(session.executionState == .completed)
        #expect(session.planTasks.first?.status == .completed)
    }
}
