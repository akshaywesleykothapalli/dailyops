import Testing
import Foundation
@testable import DailyOps

@Suite("Predefined DailyOps and Resume UX Tests", .serialized)
@MainActor
struct PredefinedDailyOpsTests {

    // MARK: - Spy Tool

    final class ResumeSpyTool: DailyOpsTool, @unchecked Sendable {
        let id: String
        let name: String
        let description: String
        let category: ToolCategory = .system
        let riskLevel: ActionRiskLevel
        private(set) var executionCount: Int = 0
        private(set) var receivedParameters: [String: String] = [:]

        init(id: String, riskLevel: ActionRiskLevel = .safe) {
            self.id = id
            self.name = id
            self.description = "Resume test tool \(id)"
            self.riskLevel = riskLevel
        }

        func execute(parameters: [String: String]) async throws -> ToolResult {
            executionCount += 1
            receivedParameters = parameters
            return ToolResult(success: true, output: "Executed \(id)")
        }

        func reset() {
            executionCount = 0
            receivedParameters = [:]
        }
    }

    private func makeIsolatedStore() -> (AgentSessionStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("predefined_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = AgentSessionStore(baseDirectory: tempDir)
        return (store, tempDir)
    }

    private func makeSampleSnapshot(
        sessionID: UUID = UUID(),
        status: PersistedSessionStatus = .executing,
        role: EmployeeRole = .developer,
        intelligenceLevel: IntelligenceLevel = .L4,
        tasks: [PersistedTaskSnapshot]
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            schemaVersion: AgentSessionSnapshot.currentSchemaVersion,
            sessionID: sessionID,
            goalID: UUID(),
            goalText: "start my workday",
            normalizedIntent: "start my workday",
            role: role,
            intelligenceLevel: intelligenceLevel,
            routingReason: "Test workflow",
            planID: UUID(),
            createdAt: Date().addingTimeInterval(-120),
            updatedAt: Date().addingTimeInterval(-60),
            status: status,
            tasks: tasks,
            pendingApproval: nil,
            recentActivity: []
        )
    }

    // 1. Expected starter workflows exist (8 count and titles)
    @Test("Expected starter workflows exist in catalog")
    func expectedStarterWorkflowsExist() {
        let all = PredefinedDailyOpsCatalog.all
        #expect(all.count == 8)

        let titles = all.map(\.title)
        #expect(titles.contains("Start My Workday"))
        #expect(titles.contains("Prepare for Tomorrow's Review"))
        #expect(titles.contains("Prepare My Standup"))
        #expect(titles.contains("Prioritize My Day"))
        #expect(titles.contains("Prepare for My Next Meeting"))
        #expect(titles.contains("Check My Blockers"))
        #expect(titles.contains("End My Workday"))
        #expect(titles.contains("Review My Active Work"))
    }

    // 2. Unique IDs across all catalog workflows
    @Test("Catalog workflows have unique IDs")
    func uniqueIDs() {
        let all = PredefinedDailyOpsCatalog.all
        let uniqueIDs = Set(all.map(\.id))
        #expect(uniqueIDs.count == all.count)
    }

    // 3. Non-empty goal text, title, and description
    @Test("Catalog workflows have non-empty goal text and metadata")
    func nonEmptyGoalText() {
        for op in PredefinedDailyOpsCatalog.all {
            #expect(!op.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!op.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!op.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!op.suggestedGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!op.iconName.isEmpty)
            #expect(!op.recommendedRoles.isEmpty)
        }
    }

    // 4. Role recommendation filtering partitions catalog cleanly
    @Test("Role recommendation filtering partitions catalog into recommended and other")
    func roleRecommendationFiltering() {
        for role in EmployeeRole.allCases {
            let rec = PredefinedDailyOpsCatalog.recommended(for: role)
            let other = PredefinedDailyOpsCatalog.other(for: role)
            #expect(rec.count + other.count == PredefinedDailyOpsCatalog.all.count)
            #expect(rec.allSatisfy { $0.isRecommended(for: role) })
            #expect(other.allSatisfy { !$0.isRecommended(for: role) })
        }
    }

    // 5. Developer recommendations include Standup and Workday
    @Test("Developer role recommendations include Developer-targeted workflows")
    func developerRecommendations() {
        let devOps = PredefinedDailyOpsCatalog.recommended(for: .developer)
        let titles = devOps.map(\.title)
        #expect(titles.contains("Start My Workday"))
        #expect(titles.contains("Prepare My Standup"))
        #expect(titles.contains("Prepare for Tomorrow's Review"))
        #expect(titles.contains("Check My Blockers"))
    }

    // 6. Manager recommendations exclude Standup and include Meetings
    @Test("Manager role recommendations prioritize Manager-targeted workflows")
    func managerRecommendations() {
        let mgrOps = PredefinedDailyOpsCatalog.recommended(for: .manager)
        let titles = mgrOps.map(\.title)
        #expect(titles.contains("Start My Workday"))
        #expect(titles.contains("Prepare for My Next Meeting"))
        #expect(!titles.contains("Prepare My Standup")) // Standup is Developer-only
    }

    // 7. General workflows available to all roles
    @Test("General workflows are recommended for General perspective")
    func generalWorkflows() {
        let genOps = PredefinedDailyOpsCatalog.recommended(for: .general)
        let titles = genOps.map(\.title)
        #expect(titles.contains("Start My Workday"))
        #expect(titles.contains("Prioritize My Day"))
        #expect(titles.contains("Prepare for My Next Meeting"))
        #expect(titles.contains("End My Workday"))
        #expect(titles.contains("Review My Active Work"))
    }

    // 8. Template goal sent unchanged into agent pipeline
    @Test("Template goal sent unchanged into agent pipeline")
    func templateGoalSentUnchangedIntoAgentPipeline() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )
        session.setRole(.developer)

        let op = PredefinedDailyOpsCatalog.all.first { $0.id == "start_my_workday" }!
        let result = await session.submitGoal(op.suggestedGoalText)

        #expect(result.error == nil)
        #expect(session.currentGoal?.originalText == op.suggestedGoalText)
        #expect(session.currentPlan != nil)
    }

    // 9. Session inspection triggers zero tool executions
    @Test("Session inspection triggers zero tool executions")
    func sessionInspectionTriggersZeroToolExecutions() async throws {
        let spyTool = ResumeSpyTool(id: "resume_spy_inspect_zero_d2")
        ToolRegistry.shared.register(spyTool)
        defer { ToolRegistry.shared.unregister("resume_spy_inspect_zero_d2") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Task 1", description: "desc", order: 0, status: .pending, toolID: spyTool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        await session.checkForRestorableSession()

        #expect(session.hasRestorableSession == true)
        #expect(session.restoredSession != nil)
        #expect(spyTool.executionCount == 0)
        #expect(session.isProcessing == false)
        #expect(session.executionState == .notStarted)
    }

    // 10. Safe resume requires explicit action
    @Test("Safe resume requires explicit action before executing")
    func safeResumeRequiresExplicitAction() async throws {
        let spyTool = ResumeSpyTool(id: "resume_spy_explicit_action_d2")
        ToolRegistry.shared.register(spyTool)
        defer { ToolRegistry.shared.unregister("resume_spy_explicit_action_d2") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task 1", description: "desc", order: 0, status: .pending, toolID: spyTool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        session.executionEngine.stepDelayNanoseconds = 0

        // Inspect only: ZERO executions
        await session.checkForRestorableSession()
        #expect(spyTool.executionCount == 0)
        #expect(session.resumeAssessment?.disposition == .safeToContinue)

        // Explicit resume: NOW it executes
        await session.resumeRestoredSession()
        #expect(spyTool.executionCount == 1)
        #expect(session.executionState == .completed)
    }

    // 11. Risky resume confirmation exposed
    @Test("Risky resume confirmation exposed for interrupted mutating action")
    func riskyResumeConfirmationExposed() async throws {
        let tool = ResumeSpyTool(id: "resume_spy_risky_exposed_d2", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_spy_risky_exposed_d2") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let taskID = UUID()
        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(taskID: taskID, title: "Modify Settings", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        await session.checkForRestorableSession()
        #expect(session.resumeAssessment?.disposition == .requiresUserConfirmation)

        // Calling resume triggers confirmation exposure without executing
        await session.resumeRestoredSession()
        #expect(session.pendingResumeConfirmation != nil)
        #expect(session.pendingResumeConfirmation?.taskID == taskID)
        #expect(tool.executionCount == 0)
    }

    // 12. Cancel risky resume executes zero tools
    @Test("Cancel risky resume executes zero tools and resets confirmation")
    func cancelRiskyResumeExecutesZeroTools() async throws {
        let tool = ResumeSpyTool(id: "resume_spy_cancel_zero_d2", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_spy_cancel_zero_d2") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Modify File", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        await session.checkForRestorableSession()
        await session.resumeRestoredSession()
        #expect(session.pendingResumeConfirmation != nil)

        session.cancelRiskyResume()
        #expect(session.pendingResumeConfirmation == nil)
        #expect(tool.executionCount == 0)
    }

    // 13. Manual review has no resume execution
    @Test("Manual review required state executes zero tools")
    func manualReviewHasNoResumeExecution() async throws {
        let tool = ResumeSpyTool(id: "resume_spy_manual_review_d2")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_spy_manual_review_d2") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Unsupported", description: "desc", order: 0, status: .unsupported, toolID: tool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        await session.checkForRestorableSession()
        #expect(session.resumeAssessment?.disposition == .manualReviewRequired)

        await session.resumeRestoredSession()
        #expect(tool.executionCount == 0)
        #expect(session.resumeError != nil)
    }

    // 14. Not resumable has no resume execution
    @Test("Not resumable state executes zero tools")
    func notResumableHasNoResumeExecution() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .completed, tasks: [])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        await session.checkForRestorableSession()
        #expect(session.resumeAssessment?.disposition == .notResumable)

        await session.resumeRestoredSession()
        #expect(session.executionState == .notStarted)
    }

    // 15. Discard removes active restorable session
    @Test("Discard removes active restorable session from storage and memory")
    func discardRemovesActiveRestorableSession() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .pending, toolID: "get_current_time", riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let session = AgentSessionController(sessionStore: store)
        await session.checkForRestorableSession()
        #expect(session.hasRestorableSession == true)

        await session.discardRestorableSession()
        #expect(session.hasRestorableSession == false)
        #expect(session.restoredSession == nil)
        #expect(session.resumeAssessment == nil)
        #expect(try store.loadActive() == nil)
    }

    // 16. Template planning does not automatically run plan
    @Test("Template planning does not automatically run plan")
    func templatePlanningDoesNotAutomaticallyRunPlan() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )

        let op = PredefinedDailyOpsCatalog.all.first { $0.id == "prioritize_my_day" }!
        let result = await session.submitGoal(op.suggestedGoalText)

        #expect(result.plan != nil)
        #expect(session.executionState == .notStarted)
        #expect(session.currentPlan?.executionState == .notStarted)
        #expect(session.planTasks.allSatisfy { $0.status == .pending })
    }

    // 17. Normal manual goal entry still works
    @Test("Normal manual goal entry still works")
    func normalManualGoalEntryStillWorks() async {
        defer { RoleEngine.shared.setRole(.general) }
        let session = AgentSessionController(
            runtime: DailyOpsRuntime.shared,
            roleEngine: RoleEngine.shared
        )
        session.setRole(.designer)

        let result = await session.submitGoal("review design system tokens")
        #expect(result.error == nil)
        #expect(session.currentGoal?.originalText == "review design system tokens")
        #expect(session.currentPlan != nil)
    }

    // 18. Normal dictation unaffected
    @Test("Normal dictation unaffected by DailyOps enhancements")
    func normalDictationUnaffected() {
        #expect(WritingMode.allCases.count == 2)
        #expect(AppBrand.displayName == "DailyOps")
        #expect(AppAppearance.allCases.count == 3)
    }
}
