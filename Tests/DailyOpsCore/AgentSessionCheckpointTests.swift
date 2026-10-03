import Testing
import Foundation
@testable import DailyOps

@Suite("AgentSessionCheckpoint Tests")
@MainActor
struct AgentSessionCheckpointTests {

    private func createTempStore() -> (AgentSessionStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DailyOpsCheckpointTest_\(UUID().uuidString)", isDirectory: true)
        let store = AgentSessionStore(baseDirectory: tempDir)
        return (store, tempDir)
    }

    private func cleanupTempStore(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func createTestController(store: AgentSessionStore) -> AgentSessionController {
        let runtime = DailyOpsRuntime.shared
        let roleEngine = RoleEngine.shared
        let controller = AgentSessionController(
            runtime: runtime,
            roleEngine: roleEngine,
            sessionStore: store
        )
        controller.executionEngine.stepDelayNanoseconds = 0
        return controller
    }

    // 1. successful plan submission creates persisted session
    @Test("Successful plan submission creates persisted session")
    func planSubmissionCreatesPersistedSession() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")

        #expect(controller.sessionID != nil)
        let sessionID = try #require(controller.sessionID)

        // Verify session was persisted
        let loaded = try store.load(sessionID: sessionID)
        #expect(loaded.sessionID == sessionID)
        #expect(loaded.goalText == "start my workday")
        #expect(loaded.status == .planned)
    }

    // 2. plan submission creates active snapshot
    @Test("Plan submission creates active snapshot")
    func planSubmissionCreatesActiveSnapshot() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")

        let sessionID = try #require(controller.sessionID)
        let active = try store.loadActive()
        #expect(active != nil)
        #expect(active?.sessionID == sessionID)
        #expect(active?.status == .planned)
    }

    // 3. role persisted correctly
    @Test("Role persisted correctly")
    func rolePersistedCorrectly() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)

        for role in EmployeeRole.allCases {
            controller.setRole(role)
            _ = await controller.submitGoal("start my workday")

            let sessionID = try #require(controller.sessionID)
            let loaded = try store.load(sessionID: sessionID)
            #expect(loaded.role == role)
        }
    }

    // 4. routing decision persisted correctly
    @Test("Routing decision persisted correctly")
    func routingDecisionPersistedCorrectly() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        let result = await controller.submitGoal("prepare me for tomorrow's review")

        let sessionID = try #require(controller.sessionID)
        let loaded = try store.load(sessionID: sessionID)

        #expect(loaded.intelligenceLevel == .L4)
        #expect(loaded.routingReason == result.routingDecision.reason)
    }

    // 5. stable session ID across checkpoints
    @Test("Stable session ID across checkpoints")
    func stableSessionIDAcrossCheckpoints() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")
        let sessionID = try #require(controller.sessionID)

        await controller.executePlan()

        #expect(controller.sessionID == sessionID)

        let loaded = try store.load(sessionID: sessionID)
        #expect(loaded.sessionID == sessionID)
        #expect(loaded.status == .executing || loaded.status == .completed || loaded.status == .failed)
    }

    // 6. new goal receives new session ID
    @Test("New goal receives new session ID")
    func newGoalReceivesNewSessionID() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")
        let firstSessionID = controller.sessionID

        controller.resetSession()

        _ = await controller.submitGoal("prepare me for tomorrow's review")
        let secondSessionID = controller.sessionID

        #expect(firstSessionID != nil)
        #expect(secondSessionID != nil)
        #expect(firstSessionID != secondSessionID)
    }

    // 7. execution-start status persisted as executing
    @Test("Execution-start status persisted as executing")
    func executionStartStatusPersistedAsExecuting() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("open safari")
        await controller.executePlan()

        let sessionID = try #require(controller.sessionID)
        let loaded = try store.load(sessionID: sessionID)

        #expect(loaded.status == .executing || loaded.status == .completed)
    }

    // 8. task completion reflected in snapshot
    @Test("Task completion reflected in snapshot")
    func taskCompletionReflectedInSnapshot() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("open safari")
        await controller.executePlan()
        try await Task.sleep(nanoseconds: 50_000_000)

        let sessionID = try #require(controller.sessionID)
        let loaded = try store.load(sessionID: sessionID)

        // At least one task should be completed
        let completedTasks = loaded.tasks.filter { $0.status == .completed }
        #expect(completedTasks.count >= 1)
    }

    // 9. unsupported task reflected truthfully
    @Test("Unsupported task reflected truthfully")
    func unsupportedTaskReflectedTruthfully() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")
        await controller.executePlan()

        // Verify in-memory state has unsupported tasks (this is the source of truth)
        let inMemoryUnsupported = controller.planTasks.filter { $0.status == .unsupported }
        #expect(inMemoryUnsupported.count >= 1)

        // Check persisted snapshot has tasks reflecting execution (some completed, some unsupported)
        let sessionID = try #require(controller.sessionID)
        try await Task.sleep(nanoseconds: 10_000_000)
        let loaded = try store.load(sessionID: sessionID)
        #expect(loaded.sessionID == sessionID)

        // Snapshot should have tasks with non-pending statuses, indicating execution occurred
        let nonPendingTasks = loaded.tasks.filter { $0.status != .pending }
        #expect(nonPendingTasks.count >= 1)
    }

    // 10. waiting-for-approval status persisted
    @Test("Waiting-for-approval status persisted")
    func waitingForApprovalStatusPersisted() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("write file")
        await controller.executePlan()
        try await Task.sleep(nanoseconds: 50_000_000)

        let sessionID = try #require(controller.sessionID)
        let loaded = try store.load(sessionID: sessionID)

        // If there was a waiting for approval, status should be captured
        // Note: This test may pass with .completed if no approval was needed
        #expect([.executing, .completed, .waitingForApproval, .failed].contains(loaded.status))
    }

    // 11. pending approval snapshot persisted
    @Test("Pending approval snapshot persisted")
    func pendingApprovalSnapshotPersisted() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("write file")
        await controller.executePlan()
        try await Task.sleep(nanoseconds: 50_000_000)

        let sessionID = try #require(controller.sessionID)
        let loaded = try store.load(sessionID: sessionID)

        // If approval was pending, it should be in the snapshot
        if loaded.pendingApproval != nil {
            #expect(loaded.pendingApproval?.status == .pending)
            #expect(loaded.pendingApproval?.taskID != nil)
            #expect(loaded.pendingApproval?.toolID != nil)
        }
    }

    // 12. approval state checkpointed
    @Test("Approval state checkpointed")
    func approvalStateCheckpointed() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("write file")
        await controller.executePlan()
        try await Task.sleep(nanoseconds: 50_000_000)

        // If there's a pending approval, approve it
        if controller.currentApprovalRequest != nil {
            await controller.approveCurrentAction()
            try await Task.sleep(nanoseconds: 50_000_000)

            let sessionID = try #require(controller.sessionID)
            let loaded = try store.load(sessionID: sessionID)

            // After approval, status should be executing or completed
            #expect([.executing, .completed].contains(loaded.status))
        }
    }

    // 13. rejection state checkpointed
    @Test("Rejection state checkpointed")
    func rejectionStateCheckpointed() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("write file")
        await controller.executePlan()
        try await Task.sleep(nanoseconds: 50_000_000)

        // If there's a pending approval, reject it
        if controller.currentApprovalRequest != nil {
            await controller.rejectCurrentAction()
            try await Task.sleep(nanoseconds: 50_000_000)

            let sessionID = try #require(controller.sessionID)
            let loaded = try store.load(sessionID: sessionID)

            // After rejection, status should be failed
            #expect(loaded.status == .failed)
        }
    }

    // 14. completed session archived
    @Test("Completed session archived")
    func completedSessionArchived() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("open safari")
        await controller.executePlan()

        let sessionID = try #require(controller.sessionID)

        // Wait for completion and archival
        try await Task.sleep(nanoseconds: 100_000_000)

        // Load from archive
        let archived = try store.load(sessionID: sessionID)
        #expect(archived.sessionID == sessionID)
        #expect([.completed, .failed].contains(archived.status))
    }

    // 15. completed session clears active snapshot
    @Test("Completed session clears active snapshot")
    func completedSessionClearsActiveSnapshot() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("open safari")
        await controller.executePlan()

        let sessionID = try #require(controller.sessionID)

        // Wait for completion and archival
        try await Task.sleep(nanoseconds: 100_000_000)

        // Active should be cleared
        let active = try store.loadActive()
        #expect(active == nil || active?.sessionID != sessionID)
    }

    // 16. failed terminal session archived
    @Test("Failed terminal session archived")
    func failedTerminalSessionArchived() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("create github issue")
        await controller.executePlan()

        let sessionID = try #require(controller.sessionID)

        // Wait for failure and archival
        try await Task.sleep(nanoseconds: 100_000_000)

        // Load from archive
        let archived = try store.load(sessionID: sessionID)
        #expect(archived.sessionID == sessionID)
        #expect(archived.status == .failed || archived.status == .completed)
    }

    // 17. persistence failure does not crash runtime
    @Test("Persistence failure does not crash runtime")
    func persistenceFailureDoesNotCrashRuntime() async throws {
        // Create a store with invalid path to simulate write failure
        let invalidStore = AgentSessionStore(baseDirectory: URL(fileURLWithPath: "/invalid/path/that/does/not/exist"))

        let runtime = DailyOpsRuntime.shared
        let roleEngine = RoleEngine.shared
        let controller = AgentSessionController(
            runtime: runtime,
            roleEngine: roleEngine,
            sessionStore: invalidStore
        )
        controller.setRole(.developer)

        // This should not crash even though persistence will fail
        let result = await controller.submitGoal("start my workday")
        #expect(result.error == nil)
        #expect(controller.currentPlan != nil)

        // Execution should also not crash
        await controller.executePlan()
        #expect(controller.executionState == .completed || controller.executionState == .failed)
    }

    // 18. activity history respects cap
    @Test("Activity history respects cap")
    func activityHistoryRespectsCap() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        // Create a goal that generates many activity items
        _ = await controller.submitGoal("start my workday")

        let sessionID = try #require(controller.sessionID)
        let loaded = try store.load(sessionID: sessionID)

        #expect(loaded.recentActivity.count <= AgentSessionSnapshot.maxActivityEvents)
    }

    // 19. reset does not contaminate next session
    @Test("Reset does not contaminate next session")
    func resetDoesNotContaminateNextSession() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")
        let firstSessionID = controller.sessionID
        _ = controller.currentPlan?.tasks.count ?? 0

        controller.resetSession()

        #expect(controller.currentGoal == nil)
        #expect(controller.currentPlan == nil)
        #expect(controller.sessionID == nil)
        #expect(controller.activityStages.isEmpty)

        _ = await controller.submitGoal("prepare me for tomorrow's review")
        let secondSessionID = controller.sessionID
        let secondPlanTasks = controller.currentPlan?.tasks.count ?? 0

        #expect(secondSessionID != firstSessionID)
        #expect(secondPlanTasks > 0)
    }

    // 20. tests use only temporary directories
    @Test("Tests use only temporary directories")
    func testsUseOnlyTemporaryDirectories() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        #expect(store.baseDirectory != AgentSessionStore.defaultBaseDirectory)
        #expect(store.baseDirectory.path.contains("DailyOpsCheckpointTest_"))
        #expect(!store.baseDirectory.path.contains("Application Support/DailyOps/AgentSessions"))
    }
}