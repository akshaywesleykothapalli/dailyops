import Testing
import Foundation
@testable import DailyOps

@Suite("AgentSessionRestoration Tests")
@MainActor
struct AgentSessionRestorationTests {

    private func createTempStore() -> (AgentSessionStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DailyOpsRestoreTest_\(UUID().uuidString)", isDirectory: true)
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

    private func makeSampleSnapshot(
        id: UUID = UUID(),
        goalText: String = "Test goal",
        role: EmployeeRole = .developer,
        intelligenceLevel: IntelligenceLevel = .L4,
        status: PersistedSessionStatus = .executing,
        schemaVersion: Int = AgentSessionSnapshot.currentSchemaVersion,
        tasks: [PersistedTaskSnapshot] = [],
        pendingApproval: PersistedApprovalSnapshot? = nil,
        recentActivity: [PersistedActivityEvent] = []
    ) -> AgentSessionSnapshot {
        let defaultTasks = tasks.isEmpty ? [
            PersistedTaskSnapshot(
                taskID: UUID(),
                title: "Task 0",
                description: "Description 0",
                order: 0,
                status: .completed,
                toolID: "get_current_time",
                riskLevel: .safe,
                dependencies: []
            ),
            PersistedTaskSnapshot(
                taskID: UUID(),
                title: "Task 1",
                description: "Description 1",
                order: 1,
                status: .inProgress,
                toolID: "open_application",
                riskLevel: .safe,
                dependencies: []
            )
        ] : tasks

        return AgentSessionSnapshot(
            schemaVersion: schemaVersion,
            sessionID: id,
            goalID: UUID(),
            goalText: goalText,
            normalizedIntent: goalText,
            role: role,
            intelligenceLevel: intelligenceLevel,
            routingReason: "Developer review workflow",
            planID: UUID(),
            createdAt: Date().addingTimeInterval(-100),
            updatedAt: Date(),
            status: status,
            tasks: defaultTasks,
            pendingApproval: pendingApproval,
            recentActivity: recentActivity
        )
    }

    // 1. Detects planned active session
    @Test("Detects planned active session")
    func detectsPlannedActiveSession() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.hasRestorableSession == true)
        #expect(controller.restoredSession?.sessionID == snapshot.sessionID)
        #expect(controller.restoredSession?.status == .planned)
    }

    // 2. Planned → safeToContinue
    @Test("Planned session assesses as safeToContinue")
    func plannedSessionAssessesSafeToContinue() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .safeToContinue)
        #expect(controller.resumeAssessment?.reason.contains("not started") == true)
    }

    // 3. WaitingForApproval → requiresPendingApproval
    @Test("WaitingForApproval assesses as requiresPendingApproval")
    func waitingForApprovalRequiresPendingApproval() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let taskID = UUID()
        let approval = PersistedApprovalSnapshot(
            requestID: UUID(),
            taskID: taskID,
            toolID: "create_note",
            toolName: "Create Note",
            description: "Write local file",
            riskLevel: .confirmationRequired,
            reason: "Modifies user disk",
            status: .pending
        )
        let tasks = [
            PersistedTaskSnapshot(taskID: taskID, title: "Create note", description: "Desc", order: 0, status: .waitingForApproval, toolID: "create_note", riskLevel: .confirmationRequired)
        ]
        let snapshot = makeSampleSnapshot(status: .waitingForApproval, tasks: tasks, pendingApproval: approval)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .requiresPendingApproval)
        #expect(controller.resumeAssessment?.pendingApproval?.toolName == "Create Note")
    }

    // 4. Approval details preserved
    @Test("Approval details preserved during restoration assessment")
    func approvalDetailsPreserved() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let taskID = UUID()
        let requestID = UUID()
        let approval = PersistedApprovalSnapshot(
            requestID: requestID,
            taskID: taskID,
            toolID: "disk_write",
            toolName: "Disk Write",
            description: "Detailed description",
            riskLevel: .confirmationRequired,
            reason: "Specific reason for approval",
            status: .pending
        )
        let tasks = [
            PersistedTaskSnapshot(taskID: taskID, title: "Disk Task", description: "Desc", order: 0, status: .waitingForApproval, toolID: "disk_write", riskLevel: .confirmationRequired)
        ]
        let snapshot = makeSampleSnapshot(status: .waitingForApproval, tasks: tasks, pendingApproval: approval)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        let restoredApproval = controller.restoredSession?.pendingApproval
        #expect(restoredApproval?.requestID == requestID)
        #expect(restoredApproval?.taskID == taskID)
        #expect(restoredApproval?.toolName == "Disk Write")
        #expect(restoredApproval?.reason == "Specific reason for approval")
    }

    // 5. Interrupted safe/idempotent task → safeToContinue
    @Test("Interrupted safe and idempotent task assesses as safeToContinue")
    func interruptedSafeIdempotentTaskSafeToContinue() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Check Time", description: "", order: 0, status: .inProgress, toolID: "get_current_time", riskLevel: .safe)
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .safeToContinue)
        #expect(controller.resumeAssessment?.reason.contains("idempotent") == true)
    }

    // 6. Interrupted mutation → requiresUserConfirmation
    @Test("Interrupted mutating task assesses as requiresUserConfirmation")
    func interruptedMutationRequiresConfirmation() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Write Note", description: "", order: 0, status: .inProgress, toolID: "create_note", riskLevel: .confirmationRequired)
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .requiresUserConfirmation)
        #expect(controller.resumeAssessment?.reason.contains("mutated persistent state") == true)
    }

    // 7. Critical action never auto-safe
    @Test("Critical action is never classified as auto-safe")
    func criticalActionNeverAutoSafe() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Critical wipe", description: "", order: 0, status: .inProgress, toolID: "critical_tool", riskLevel: .critical)
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition != .safeToContinue)
        #expect(controller.resumeAssessment?.disposition == .requiresUserConfirmation)
    }

    // 8. Failed task → manualReviewRequired
    @Test("Failed task assesses as manualReviewRequired")
    func failedTaskManualReviewRequired() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Failed step", description: "", order: 0, status: .failed, toolID: "tool", riskLevel: .safe, error: "Network timeout")
        ]
        let snapshot = makeSampleSnapshot(status: .failed, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .manualReviewRequired)
        #expect(controller.resumeAssessment?.reason.contains("failed") == true)
    }

    // 9. Unsupported task preserved
    @Test("Unsupported task preserved and assesses as manualReviewRequired")
    func unsupportedTaskPreserved() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Calendar Check", description: "", order: 0, status: .unsupported, toolID: "calendar", riskLevel: .safe, error: "Calendar integration unavailable")
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.restoredSession?.tasks.first?.status == .unsupported)
        #expect(controller.resumeAssessment?.disposition == .manualReviewRequired)
    }

    // 10. Completed active snapshot → notResumable
    @Test("Completed active snapshot assesses as notResumable")
    func completedActiveSnapshotNotResumable() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Done", description: "", order: 0, status: .completed)
        ]
        let snapshot = makeSampleSnapshot(status: .completed, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .notResumable)
    }

    // 11. Cancelled active snapshot → notResumable
    @Test("Cancelled active snapshot assesses as notResumable")
    func cancelledActiveSnapshotNotResumable() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(status: .cancelled)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .notResumable)
    }

    // 12. Invalid dependency → manualReviewRequired
    @Test("Invalid task dependency assesses as manualReviewRequired")
    func invalidDependencyManualReview() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Step with missing dep", description: "", order: 0, status: .pending, dependencies: [UUID()])
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .manualReviewRequired)
        #expect(controller.resumeAssessment?.reason.contains("dependency") == true)
    }

    // 13. Pending approval referencing wrong task rejected safely
    @Test("Pending approval referencing wrong task is flagged as manualReviewRequired")
    func approvalReferencingWrongTaskFlagged() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let approval = PersistedApprovalSnapshot(
            requestID: UUID(),
            taskID: UUID(), // Unrelated ID not in tasks
            toolID: "tool",
            toolName: "Tool",
            description: "Desc",
            riskLevel: .confirmationRequired,
            reason: "Reason",
            status: .pending
        )
        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Existing task", description: "", order: 0, status: .waitingForApproval)
        ]
        let snapshot = makeSampleSnapshot(status: .waitingForApproval, tasks: tasks, pendingApproval: approval)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .manualReviewRequired)
        #expect(controller.resumeAssessment?.reason.contains("non-existent task") == true)
    }

    // 14. Unsupported schema handled
    @Test("Unsupported schema version is handled cleanly without crash")
    func unsupportedSchemaHandled() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let futureJSON = """
        {
            "schemaVersion": 99,
            "sessionID": "\(UUID().uuidString)",
            "goalID": "\(UUID().uuidString)",
            "goalText": "Future Goal",
            "normalizedIntent": "Future Goal",
            "role": "general",
            "intelligenceLevel": "L0",
            "routingReason": "Future",
            "planID": "\(UUID().uuidString)",
            "createdAt": "2026-10-03T12:00:00Z",
            "updatedAt": "2026-10-03T12:00:00Z",
            "status": "planned",
            "tasks": [],
            "recentActivity": []
        }
        """
        try futureJSON.write(to: store.activeFileURL, atomically: true, encoding: .utf8)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.hasRestorableSession == false)
        #expect(controller.restorationError != nil)
    }

    // 15. Corrupt active snapshot does not crash
    @Test("Corrupt active snapshot does not crash runtime")
    func corruptActiveSnapshotDoesNotCrash() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        try "{ broken json corrupt content".write(to: store.activeFileURL, atomically: true, encoding: .utf8)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.hasRestorableSession == false)
        #expect(controller.restorationError != nil)
    }

    // 16. Role restored into read-only session representation
    @Test("Role restored into read-only representation")
    func roleRestoredReadOnly() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(role: .designer)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.restoredSession?.role == .designer)
    }

    // 17. Routing information restored
    @Test("Routing information restored into read-only session")
    func routingInfoRestored() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(intelligenceLevel: .L4)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.restoredSession?.intelligenceLevel == .L4)
        #expect(controller.restoredSession?.routingReason == "Developer review workflow")
    }

    // 18. Activity history restored within cap
    @Test("Activity history restored within cap")
    func activityHistoryRestoredWithinCap() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let activities = (0..<150).map { i in
            PersistedActivityEvent(stageKind: "Stage", detail: "Step \(i)", status: "completed")
        }
        let snapshot = makeSampleSnapshot(recentActivity: activities)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.restoredSession?.recentActivity.count == 100)
    }

    // 19. Inspecting session does not change live RoleEngine
    @Test("Inspecting session does not modify live RoleEngine active role")
    func inspectingSessionDoesNotChangeLiveRoleEngine() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        RoleEngine.shared.setRole(.general)
        #expect(RoleEngine.shared.activeRole == .general)

        let snapshot = makeSampleSnapshot(role: .designer)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.restoredSession?.role == .designer)
        #expect(RoleEngine.shared.activeRole == .general)
    }

    // 20. MANDATORY: Zero tool execution proof
    @Test("Inspecting and loading restorable session executes ZERO tools")
    func inspectingSessionExecutesZeroTools() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        final class SpyTrackingTool: DailyOpsTool, @unchecked Sendable {
            let id: String = "spy_tracking_tool"
            let name: String = "Spy Tool"
            let description: String = "Spy Tool Description"
            let category: ToolCategory = .system
            let riskLevel: ActionRiskLevel = .safe
            var executionCount = 0

            func execute(parameters: [String: String]) async throws -> ToolResult {
                executionCount += 1
                return ToolResult(success: true, output: "Executed")
            }
        }

        let spyTool = SpyTrackingTool()
        ToolRegistry.shared.register(spyTool)
        defer { ToolRegistry.shared.unregister(spyTool.id) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "Spy Task", description: "", order: 0, status: .inProgress, toolID: spyTool.id, riskLevel: .safe)
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()
        _ = controller.inspectRestorableSession()

        #expect(spyTool.executionCount == 0, "Inspecting a restorable session MUST execute ZERO tools.")
    }

    // 21. Inspecting session does not modify task statuses
    @Test("Inspecting session does not modify task statuses")
    func inspectingSessionPreservesTaskStatuses() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = [
            PersistedTaskSnapshot(taskID: UUID(), title: "T0", description: "", order: 0, status: .completed),
            PersistedTaskSnapshot(taskID: UUID(), title: "T1", description: "", order: 1, status: .inProgress),
            PersistedTaskSnapshot(taskID: UUID(), title: "T2", description: "", order: 2, status: .pending)
        ]
        let snapshot = makeSampleSnapshot(status: .executing, tasks: tasks)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        let restoredTasks = controller.restoredSession?.tasks ?? []
        #expect(restoredTasks.count == 3)
        #expect(restoredTasks[0].status == .completed)
        #expect(restoredTasks[1].status == .inProgress)
        #expect(restoredTasks[2].status == .pending)
    }

    // 22. Discard removes active snapshot
    @Test("Discard removes active snapshot from storage")
    func discardRemovesActiveSnapshot() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned)
        try store.saveActive(snapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()
        #expect(controller.hasRestorableSession == true)

        await controller.discardRestorableSession()
        #expect(controller.hasRestorableSession == false)
        #expect(controller.restoredSession == nil)
        #expect(controller.resumeAssessment == nil)
        #expect(try store.loadActive() == nil)
    }

    // 23. Discard does not remove archives
    @Test("Discard does not delete archived sessions")
    func discardPreservesArchives() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let activeSnapshot = makeSampleSnapshot(id: UUID(), status: .planned)
        let archiveSnapshot = makeSampleSnapshot(id: UUID(), status: .completed)

        try store.saveActive(activeSnapshot)
        try store.archive(archiveSnapshot)

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()
        await controller.discardRestorableSession()

        let archives = try store.loadRecentArchives()
        #expect(archives.count == 1)
        #expect(archives.first?.sessionID == archiveSnapshot.sessionID)
    }

    // 24. No session → hasRestorableSession false
    @Test("When no active session exists hasRestorableSession is false")
    func noActiveSessionGivesFalse() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        await controller.checkForRestorableSession()

        #expect(controller.hasRestorableSession == false)
        #expect(controller.restoredSession == nil)
        #expect(controller.resumeAssessment == nil)
        #expect(controller.restorationError == nil)
    }

    // 25. Existing Phase 5B checkpoint behavior remains intact
    @Test("Phase 5B checkpoint behavior continues working alongside restorable detection")
    func phase5BCheckpointBehaviorIntact() async throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let controller = createTestController(store: store)
        controller.setRole(.developer)

        _ = await controller.submitGoal("start my workday")

        #expect(controller.sessionID != nil)
        let active = try store.loadActive()
        #expect(active?.goalText == "start my workday")
        #expect(active?.status == .planned)
    }
}
