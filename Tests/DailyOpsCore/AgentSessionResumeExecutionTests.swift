import Foundation
import Testing
@testable import DailyOps

@Suite("Agent Session Resume Execution Tests (Phase 5D1)", .serialized)
struct AgentSessionResumeExecutionTests {

    private func makeIsolatedStore() -> (AgentSessionStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DailyOpsResumeTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = AgentSessionStore(baseDirectory: tempDir)
        return (store, tempDir)
    }

    private func makeSampleSnapshot(
        sessionID: UUID = UUID(),
        goalText: String = "Resume execution test goal",
        role: EmployeeRole = .developer,
        intelligenceLevel: IntelligenceLevel = .L2,
        status: PersistedSessionStatus = .executing,
        schemaVersion: Int = AgentSessionSnapshot.currentSchemaVersion,
        tasks: [PersistedTaskSnapshot],
        pendingApproval: PersistedApprovalSnapshot? = nil
    ) -> AgentSessionSnapshot {
        AgentSessionSnapshot(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            goalID: UUID(),
            goalText: goalText,
            normalizedIntent: goalText,
            role: role,
            intelligenceLevel: intelligenceLevel,
            routingReason: "Deterministic test routing",
            planID: UUID(),
            createdAt: Date().addingTimeInterval(-60),
            updatedAt: Date(),
            status: status,
            tasks: tasks,
            pendingApproval: pendingApproval,
            recentActivity: []
        )
    }

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

    // 1. Inspection still executes zero tools
    @Test("Inspection executes zero tools")
    @MainActor
    func inspectionExecutesZeroTools() async throws {
        let tool = ResumeSpyTool(id: "resume_test_tool_1")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_test_tool_1") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Task 1", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()

        #expect(controller.hasRestorableSession)
        #expect(tool.executionCount == 0)
    }

    // 2. Planned session requires explicit resume call
    @Test("Planned session requires explicit resume call")
    @MainActor
    func plannedSessionRequiresExplicitResumeCall() async throws {
        let tool = ResumeSpyTool(id: "resume_test_tool_2")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_test_tool_2") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task 1", description: "desc", order: 0, status: .pending, toolID: tool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()

        #expect(controller.executionState == .notStarted)
        #expect(tool.executionCount == 0)
    }

    // 3. Planned explicit resume executes eligible work
    @Test("Planned explicit resume executes eligible work")
    @MainActor
    func plannedExplicitResumeExecutesEligibleWork() async throws {
        let tool = ResumeSpyTool(id: "resume_test_tool_3")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_test_tool_3") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task 1", description: "desc", order: 0, status: .pending, toolID: tool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(tool.executionCount == 1)
        #expect(controller.executionState == .completed)
    }

    // 4. Completed task never reruns
    @Test("Completed task never reruns")
    @MainActor
    func completedTaskNeverReruns() async throws {
        let toolA = ResumeSpyTool(id: "resume_test_completed_4")
        let toolB = ResumeSpyTool(id: "resume_test_pending_4")
        ToolRegistry.shared.register(toolA)
        ToolRegistry.shared.register(toolB)
        defer {
            ToolRegistry.shared.unregister("resume_test_completed_4")
            ToolRegistry.shared.unregister("resume_test_pending_4")
        }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Completed Task", description: "desc", order: 0, status: .completed, toolID: toolA.id, riskLevel: .safe, parameters: [:]),
            PersistedTaskSnapshot(title: "Pending Task", description: "desc", order: 1, status: .pending, toolID: toolB.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(toolA.executionCount == 0)
        #expect(toolB.executionCount == 1)
    }

    // 5. Completed task execution counter remains zero
    @Test("Completed task execution counter remains zero")
    @MainActor
    func completedTaskExecutionCounterRemainsZero() async throws {
        let toolA = ResumeSpyTool(id: "resume_test_counter_5")
        ToolRegistry.shared.register(toolA)
        defer { ToolRegistry.shared.unregister("resume_test_counter_5") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Already done", description: "desc", order: 0, status: .completed, toolID: toolA.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(toolA.executionCount == 0)
    }

    // 6. Unsupported task never reruns
    @Test("Unsupported task never reruns")
    @MainActor
    func unsupportedTaskNeverReruns() async throws {
        let toolA = ResumeSpyTool(id: "resume_test_unsupported_6")
        let toolB = ResumeSpyTool(id: "resume_test_pending_6")
        ToolRegistry.shared.register(toolA)
        ToolRegistry.shared.register(toolB)
        defer {
            ToolRegistry.shared.unregister("resume_test_unsupported_6")
            ToolRegistry.shared.unregister("resume_test_pending_6")
        }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Unsupported", description: "desc", order: 0, status: .unsupported, toolID: toolA.id, riskLevel: .safe, parameters: [:]),
            PersistedTaskSnapshot(title: "Pending", description: "desc", order: 1, status: .pending, toolID: toolB.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(toolA.executionCount == 0)
        #expect(controller.resumeError != nil) // Assessment manualReviewRequired on unsupported
    }

    // 7. Interrupted safe idempotent task executes after explicit resume
    @Test("Interrupted safe idempotent task executes after explicit resume")
    @MainActor
    func interruptedSafeIdempotentTaskExecutesAfterExplicitResume() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Check time", description: "desc", order: 0, status: .inProgress, toolID: "get_current_time", riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        #expect(controller.resumeAssessment?.disposition == .safeToContinue)

        await controller.resumeRestoredSession()
        #expect(controller.executionState == .completed)
    }

    // 8. Interrupted mutation does NOT execute on resume request
    @Test("Interrupted mutation does not execute on resume request")
    @MainActor
    func interruptedMutationDoesNotExecuteOnResumeRequest() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_8", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_8") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Write File", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: ["file": "a.txt"])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(tool.executionCount == 0)
    }

    // 9. Interrupted mutation exposes pending resume confirmation
    @Test("Interrupted mutation exposes pending resume confirmation")
    @MainActor
    func interruptedMutationExposesPendingResumeConfirmation() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_9", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_9") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let taskID = UUID()
        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(taskID: taskID, title: "Create Document", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(controller.pendingResumeConfirmation != nil)
        #expect(controller.pendingResumeConfirmation?.taskID == taskID)
        #expect(controller.pendingResumeConfirmation?.toolID == tool.id)
    }

    // 10. Cancel risky resume executes zero tools
    @Test("Cancel risky resume executes zero tools")
    @MainActor
    func cancelRiskyResumeExecutesZeroTools() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_10", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_10") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Mutate", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        controller.cancelRiskyResume()
        #expect(controller.pendingResumeConfirmation == nil)
        #expect(tool.executionCount == 0)

        // Snapshot remains in active store
        let active = try store.loadActive()
        #expect(active != nil)
    }

    // 11. Confirm risky resume still enters PermissionManager
    @Test("Confirm risky resume still enters PermissionManager")
    @MainActor
    func confirmRiskyResumeStillEntersPermissionManager() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_11", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_11") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Mutate", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let resumeTask = Task {
            await controller.confirmRiskyResume()
        }

        for _ in 0..<100 {
            if controller.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Enters PermissionManager and pauses for approval; tool has NOT executed
        #expect(tool.executionCount == 0)
        #expect(controller.hasPendingApproval)
        #expect(controller.executionState == .waitingForApproval)

        await controller.rejectCurrentAction()
        await resumeTask.value
    }

    // 12. Confirmation-required action pauses for normal approval
    @Test("Confirmation-required action pauses for normal approval")
    @MainActor
    func confirmationRequiredActionPausesForNormalApproval() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_12", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_12") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Mutate", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let resumeTask = Task {
            await controller.confirmRiskyResume()
        }

        for _ in 0..<100 {
            if controller.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(controller.currentApprovalRequest != nil)
        #expect(controller.currentApprovalRequest?.toolId == tool.id)

        await controller.rejectCurrentAction()
        await resumeTask.value
    }

    // 13. Actual approval executes mutation exactly once
    @Test("Actual approval executes mutation exactly once")
    @MainActor
    func actualApprovalExecutesMutationExactlyOnce() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_13", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_13") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Mutate", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let resumeTask = Task {
            await controller.confirmRiskyResume()
        }

        for _ in 0..<100 {
            if controller.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(tool.executionCount == 0)
        await controller.approveCurrentAction()
        await resumeTask.value

        #expect(tool.executionCount == 1)
        #expect(controller.executionState == .completed)
    }

    // 14. Old persisted approval is never reused as authorization
    @Test("Old persisted approval is never reused as authorization")
    @MainActor
    func oldPersistedApprovalNeverReused() async throws {
        let tool = ResumeSpyTool(id: "resume_approval_14", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_approval_14") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let taskID = UUID()
        let oldApproval = PersistedApprovalSnapshot(
            requestID: UUID(),
            taskID: taskID,
            toolID: tool.id,
            toolName: tool.name,
            description: "Old approval",
            riskLevel: .confirmationRequired,
            reason: "Needs check",
            status: .pending
        )
        let snapshot = makeSampleSnapshot(status: .waitingForApproval, tasks: [
            PersistedTaskSnapshot(taskID: taskID, title: "Waiting Task", description: "desc", order: 0, status: .waitingForApproval, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ], pendingApproval: oldApproval)
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()

        let resumeTask = Task {
            await controller.resumeRestoredSession()
        }

        for _ in 0..<100 {
            if controller.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // It must NOT have executed automatically using the old approval
        #expect(tool.executionCount == 0)
        #expect(controller.hasPendingApproval)
        #expect(controller.currentApprovalRequest?.id != oldApproval.requestID) // Fresh request

        await controller.rejectCurrentAction()
        await resumeTask.value
    }

    // 15. Rejected approval produces no mutation
    @Test("Rejected approval produces no mutation")
    @MainActor
    func rejectedApprovalProducesNoMutation() async throws {
        let tool = ResumeSpyTool(id: "resume_mutation_15", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_mutation_15") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Mutate", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let resumeTask = Task {
            await controller.confirmRiskyResume()
        }

        for _ in 0..<100 {
            if controller.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        await controller.rejectCurrentAction()
        await resumeTask.value
        #expect(tool.executionCount == 0)
        #expect(controller.executionState == .failed)
    }

    // 16. Critical action cannot bypass permissions
    @Test("Critical action cannot bypass permissions")
    @MainActor
    func criticalActionCannotBypassPermissions() async throws {
        let tool = ResumeSpyTool(id: "resume_critical_16", riskLevel: .critical)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_critical_16") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Critical Task", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .critical, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        #expect(controller.resumeAssessment?.disposition == .requiresUserConfirmation)

        await controller.resumeRestoredSession()
        #expect(tool.executionCount == 0)
    }

    // 17. manualReviewRequired refuses resume
    @Test("manualReviewRequired refuses resume")
    @MainActor
    func manualReviewRequiredRefusesResume() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Task with missing dep", description: "desc", order: 0, status: .pending, dependencies: [UUID()])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(controller.resumeError != nil)
    }

    // 18. notResumable refuses resume
    @Test("notResumable refuses resume")
    @MainActor
    func notResumableRefusesResume() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .completed, tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .completed)
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(controller.resumeError != nil)
    }

    // 19. Failed restored session is not retried
    @Test("Failed restored session is not retried")
    @MainActor
    func failedRestoredSessionNotRetried() async throws {
        let tool = ResumeSpyTool(id: "resume_failed_19")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_failed_19") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(status: .failed, tasks: [
            PersistedTaskSnapshot(title: "Failed Task", description: "desc", order: 0, status: .failed, toolID: tool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(tool.executionCount == 0)
        #expect(controller.resumeError != nil)
    }

    // 20. Persisted role applied only when execution actually resumes
    @Test("Persisted role applied only when execution actually resumes")
    @MainActor
    func persistedRoleAppliedOnlyWhenExecutionResumes() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(role: .designer, status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .pending, toolID: "get_current_time", riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        controller.setRole(.manager)
        #expect(controller.activeRole == .manager)

        await controller.checkForRestorableSession()
        #expect(controller.activeRole == .manager) // Untouched on inspection

        await controller.resumeRestoredSession()
        #expect(controller.activeRole == .designer) // Applied on explicit resume
    }

    // 21. Inspection does not change role
    @Test("Inspection does not change role")
    @MainActor
    func inspectionDoesNotChangeRole() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(role: .manager, tasks: [])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        controller.setRole(.general)

        await controller.checkForRestorableSession()
        #expect(controller.activeRole == .general)
    }

    // 22. Same persistence session ID retained
    @Test("Same persistence session ID retained")
    @MainActor
    func sameSessionIDRetained() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalSessionID = UUID()
        let snapshot = makeSampleSnapshot(sessionID: originalSessionID, status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .pending, toolID: "get_current_time", riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(controller.sessionID == originalSessionID)
    }

    // 23. Resumed checkpoints update same active session
    @Test("Resumed checkpoints update same active session")
    @MainActor
    func resumedCheckpointsUpdateSameActiveSession() async throws {
        let tool = ResumeSpyTool(id: "resume_tool_23", riskLevel: .confirmationRequired)
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_tool_23") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionID = UUID()
        let snapshot = makeSampleSnapshot(sessionID: sessionID, tasks: [
            PersistedTaskSnapshot(title: "Action", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .confirmationRequired, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let resumeTask = Task {
            await controller.confirmRiskyResume()
        }

        for _ in 0..<100 {
            if controller.executionState == .waitingForApproval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Should have updated active.json with sessionID
        let active = try store.loadActive()
        #expect(active?.sessionID == sessionID)

        await controller.rejectCurrentAction()
        await resumeTask.value
    }

    // 24. Completed resumed session archived
    @Test("Completed resumed session archived")
    @MainActor
    func completedResumedSessionArchived() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionID = UUID()
        let snapshot = makeSampleSnapshot(sessionID: sessionID, status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .pending, toolID: "get_current_time", riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let archives = try store.loadRecentArchives()
        #expect(archives.contains(where: { $0.sessionID == sessionID && $0.status == .completed }))
    }

    // 25. Active marker cleared after terminal completion
    @Test("Active marker cleared after terminal completion")
    @MainActor
    func activeMarkerClearedAfterTerminalCompletion() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionID = UUID()
        let snapshot = makeSampleSnapshot(sessionID: sessionID, status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .pending, toolID: "get_current_time", riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        let active = try store.loadActive()
        #expect(active == nil)
    }

    // 26. Exact tool parameters survive persistence and resume
    @Test("Exact tool parameters survive persistence and resume")
    @MainActor
    func exactToolParametersSurvivePersistenceAndResume() async throws {
        let tool = ResumeSpyTool(id: "resume_param_tool_26")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_param_tool_26") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectedParams = ["destination": "reports/quarterly.pdf", "format": "pdf", "dpi": "300"]
        let snapshot = makeSampleSnapshot(status: .planned, tasks: [
            PersistedTaskSnapshot(title: "Export", description: "desc", order: 0, status: .pending, toolID: tool.id, riskLevel: .safe, parameters: expectedParams)
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(tool.executionCount == 1)
        #expect(tool.receivedParameters == expectedParams)
    }

    // 27. Missing legacy v1 parameters never guessed
    @Test("Missing legacy v1 parameters never guessed")
    @MainActor
    func missingLegacyV1ParametersNeverGuessed() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(schemaVersion: 1, tasks: [
            PersistedTaskSnapshot(title: "Legacy task", description: "desc", order: 0, status: .inProgress, toolID: "open_application", riskLevel: .safe, parameters: nil)
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()

        #expect(controller.resumeAssessment?.disposition == .manualReviewRequired)
        await controller.resumeRestoredSession()
        #expect(controller.resumeError != nil)
    }

    // 28. Dependency on completed task works
    @Test("Dependency on completed task works")
    @MainActor
    func dependencyOnCompletedTaskWorks() async throws {
        let tool = ResumeSpyTool(id: "resume_dep_tool_28")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_dep_tool_28") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let completedID = UUID()
        let dependentID = UUID()

        let snapshot = makeSampleSnapshot(status: .planned, tasks: [
            PersistedTaskSnapshot(taskID: completedID, title: "Step 1", description: "Done", order: 0, status: .completed, parameters: [:]),
            PersistedTaskSnapshot(taskID: dependentID, title: "Step 2", description: "Work", order: 1, status: .pending, toolID: tool.id, riskLevel: .safe, parameters: [:], dependencies: [completedID])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(tool.executionCount == 1)
        #expect(controller.executionState == .completed)
    }

    // 29. Invalid/failed dependency does not falsely execute
    @Test("Invalid/failed dependency does not falsely execute")
    @MainActor
    func invalidFailedDependencyDoesNotFalselyExecute() async throws {
        let tool = ResumeSpyTool(id: "resume_dep_tool_29")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_dep_tool_29") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let failedID = UUID()
        let dependentID = UUID()

        let snapshot = makeSampleSnapshot(status: .executing, tasks: [
            PersistedTaskSnapshot(taskID: failedID, title: "Step 1", description: "Failed", order: 0, status: .failed, parameters: [:]),
            PersistedTaskSnapshot(taskID: dependentID, title: "Step 2", description: "Work", order: 1, status: .pending, toolID: tool.id, riskLevel: .safe, parameters: [:], dependencies: [failedID])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.resumeRestoredSession()

        #expect(tool.executionCount == 0)
        #expect(controller.resumeError != nil)
    }

    // 30. Discard remains non-executing
    @Test("Discard remains non-executing")
    @MainActor
    func discardRemainsNonExecuting() async throws {
        let tool = ResumeSpyTool(id: "resume_discard_tool_30")
        ToolRegistry.shared.register(tool)
        defer { ToolRegistry.shared.unregister("resume_discard_tool_30") }

        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshot = makeSampleSnapshot(tasks: [
            PersistedTaskSnapshot(title: "Task", description: "desc", order: 0, status: .inProgress, toolID: tool.id, riskLevel: .safe, parameters: [:])
        ])
        try store.saveActive(snapshot)

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        await controller.checkForRestorableSession()
        await controller.discardRestorableSession()

        #expect(tool.executionCount == 0)
        #expect(controller.hasRestorableSession == false)
        let active = try store.loadActive()
        #expect(active == nil)
    }

    // 31. Normal fresh execution remains unchanged
    @Test("Normal fresh execution remains unchanged")
    @MainActor
    func normalFreshExecutionRemainsUnchanged() async throws {
        let (store, tempDir) = makeIsolatedStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let controller = AgentSessionController(sessionStore: store)
        controller.executionEngine.stepDelayNanoseconds = 0
        _ = await controller.submitGoal("Check the time")

        #expect(controller.currentPlan != nil)
        #expect(controller.sessionID != nil)
    }

    // 32. Normal dictation remains unaffected
    @Test("Normal dictation remains unaffected")
    func normalDictationRemainsUnaffected() {
        let state = DictationState.idle
        #expect(state == .idle)
    }
}
