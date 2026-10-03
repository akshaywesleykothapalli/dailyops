import Foundation

/// Events emitted during plan execution for observable integration.
public enum ExecutionEvent: Sendable, Equatable {
    case goalAccepted(goalId: UUID, text: String)
    case roleLoaded(role: EmployeeRole)
    case planGenerated(planId: UUID, taskCount: Int)
    case executionStarted(planId: UUID)
    case taskStarted(taskId: UUID, title: String)
    case toolSelected(taskId: UUID, toolId: String, toolName: String)
    case permissionEvaluated(taskId: UUID, toolId: String, decision: PermissionDecision)
    case executing(taskId: UUID)
    case executionSucceeded(taskId: UUID, output: String)
    case executionFailed(taskId: UUID, error: String)
    case verificationStarted(taskId: UUID)
    case verificationPassed(taskId: UUID)
    case verificationFailed(taskId: UUID, issues: [String])
    case taskCompleted(taskId: UUID)
    case taskFailed(taskId: UUID, error: String)
    case taskUnsupported(taskId: UUID, reason: String)
    case waitingForApproval(taskId: UUID, toolId: String, reason: String)
    case approvalReceived(taskId: UUID, approved: Bool)
    case recoveryAttempted(taskId: UUID, action: RecoveryAction)
    case executionPaused(planId: UUID)
    case executionResumed(planId: UUID)
    case executionCompleted(planId: UUID)
    case executionFailedOverall(planId: UUID, error: String)
}

/// Represents an approval request for a confirmation-required or critical action.
public struct ApprovalRequest: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let taskId: UUID
    public let toolId: String
    public let toolName: String
    public let description: String
    public let riskLevel: ActionRiskLevel
    public let reason: String
    public let timestamp: Date
    public var status: ApprovalStatus

    public init(
        id: UUID = UUID(),
        taskId: UUID,
        toolId: String,
        toolName: String,
        description: String,
        riskLevel: ActionRiskLevel,
        reason: String,
        timestamp: Date = Date(),
        status: ApprovalStatus = .pending
    ) {
        self.id = id
        self.taskId = taskId
        self.toolId = toolId
        self.toolName = toolName
        self.description = description
        self.riskLevel = riskLevel
        self.reason = reason
        self.timestamp = timestamp
        self.status = status
    }
}

public enum ApprovalStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case pending
    case approved
    case rejected
}

/// Result of plan execution containing final state and all events.
public struct PlanExecutionResult: Sendable {
    public let plan: DailyOpsPlan
    public let events: [ExecutionEvent]
    public let finalState: PlanExecutionState
    public let completedTaskCount: Int
    public let failedTaskCount: Int
    public let unsupportedTaskCount: Int
    public let pendingApprovalCount: Int

    public init(
        plan: DailyOpsPlan,
        events: [ExecutionEvent],
        finalState: PlanExecutionState,
        completedTaskCount: Int,
        failedTaskCount: Int,
        unsupportedTaskCount: Int,
        pendingApprovalCount: Int
    ) {
        self.plan = plan
        self.events = events
        self.finalState = finalState
        self.completedTaskCount = completedTaskCount
        self.failedTaskCount = failedTaskCount
        self.unsupportedTaskCount = unsupportedTaskCount
        self.pendingApprovalCount = pendingApprovalCount
    }
}

/// Core execution engine for DailyOps plans.
/// Handles sequential task execution, permission gating, tool resolution, verification, and recovery.
@MainActor
public final class PlanExecutionEngine {
    public static let shared = PlanExecutionEngine()

    public var onEvent: ((ExecutionEvent) -> Void)?
    public var stepDelayNanoseconds: UInt64 = 80_000_000

    private let toolRegistry = ToolRegistry.shared
    private let permissionManager = PermissionManager.shared
    private let verifierAgent = DeterministicVerifierAgent.shared
    private let recoveryAgent = DeterministicRecoveryAgent.shared

    private var currentPlan: DailyOpsPlan?
    private var currentEvents: [ExecutionEvent] = []
    private var pendingApprovals: [ApprovalRequest] = []
    private var isPaused = false
    private var shouldStop = false

    private var continuation: CheckedContinuation<Void, Never>?

    private init() {}

    /// Executes a plan sequentially, returning the final result with all events.
    public func executePlan(
        _ plan: DailyOpsPlan,
        onEvent: ((ExecutionEvent) -> Void)? = nil
    ) async -> PlanExecutionResult {
        if let onEvent = onEvent {
            self.onEvent = onEvent
        }
        currentPlan = plan
        currentEvents = []
        pendingApprovals = []
        isPaused = false
        shouldStop = false

        var workingTasks = plan.tasks.sorted { $0.order < $1.order }

        emit(.executionStarted(planId: plan.id))

        var planState = plan.executionState
        var completedCount = 0
        var failedCount = 0
        var unsupportedCount = 0
        var pendingApprovalCount = 0

        for taskIndex in 0..<workingTasks.count {
            if shouldStop { break }

            let task = workingTasks[taskIndex]

            // Respect pre-existing terminal task states during execution resumption
            if task.status == .completed {
                completedCount += 1
                continue
            }
            if task.status == .unsupported {
                unsupportedCount += 1
                continue
            }
            if task.status == .skipped {
                continue
            }

            // Check dependencies
            if !dependenciesSatisfied(task, in: workingTasks) {
                let reason = "Dependencies not satisfied"
                workingTasks[taskIndex].status = .unsupported
                workingTasks[taskIndex].error = reason
                await markTaskUnsupported(task, reason: reason)
                unsupportedCount += 1
                continue
            }

            if stepDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: stepDelayNanoseconds)
            }

            workingTasks[taskIndex].status = .inProgress

            let taskResult = await executeTask(task, plan: plan)
            switch taskResult {
            case .completed:
                workingTasks[taskIndex].status = .completed
                completedCount += 1
            case .failed:
                workingTasks[taskIndex].status = .failed
                failedCount += 1
                // Stop execution on failure unless recovery says otherwise
                let recoveryAction = await attemptRecovery(for: task, in: plan)
                switch recoveryAction {
                case .retry:
                    emit(.executing(taskId: task.id))
                    let retryResult = await executeTask(task, plan: plan)
                    if case .completed = retryResult {
                        workingTasks[taskIndex].status = .completed
                        completedCount += 1
                        failedCount -= 1
                    }
                case .skip:
                    workingTasks[taskIndex].status = .skipped
                    break
                case .modifyPlan:
                    shouldStop = true
                case .abort:
                    shouldStop = true
                }
            case .unsupported:
                workingTasks[taskIndex].status = .unsupported
                if let req = task.toolRequirement {
                    workingTasks[taskIndex].error = readableUnsupportedReason(for: req.toolId)
                }
                unsupportedCount += 1
            case .waitingForApproval:
                workingTasks[taskIndex].status = .waitingForApproval
                pendingApprovalCount += 1
                isPaused = true
                emit(.executionPaused(planId: plan.id))

                // Wait for user approval
                await waitForApproval(for: task)

                if shouldStop { break }

                let status = pendingApprovals.first(where: { $0.taskId == task.id })?.status
                pendingApprovals.removeAll(where: { $0.taskId == task.id })

                if status == .approved {
                    emit(.executionResumed(planId: plan.id))
                    workingTasks[taskIndex].status = .inProgress
                    if let req = task.toolRequirement, let tool = toolRegistry.tool(id: req.toolId) {
                        let approvalResult = await executeToolSafely(task, tool: tool, requirement: req)
                        switch approvalResult {
                        case .completed:
                            workingTasks[taskIndex].status = .completed
                            completedCount += 1
                            pendingApprovalCount -= 1
                        case .failed:
                            workingTasks[taskIndex].status = .failed
                            failedCount += 1
                            pendingApprovalCount -= 1
                        default:
                            break
                        }
                    }
                } else {
                    workingTasks[taskIndex].status = .failed
                    workingTasks[taskIndex].error = "Action rejected by user"
                    failedCount += 1
                    pendingApprovalCount -= 1
                    await markTaskFailed(task, error: "Action rejected by user")
                    shouldStop = true
                }
            }
        }

        if !shouldStop && failedCount == 0 && unsupportedCount == 0 && pendingApprovalCount == 0 {
            planState = .completed
        } else if failedCount > 0 || unsupportedCount > 0 {
            planState = .failed
        } else if pendingApprovalCount > 0 {
            planState = .waitingForApproval
        } else {
            planState = .failed
        }

        if planState == .completed {
            emit(.executionCompleted(planId: plan.id))
        } else if planState == .failed {
            emit(.executionFailedOverall(
                planId: plan.id,
                error: "\(failedCount) task(s) failed; \(unsupportedCount) task(s) unsupported"
            ))
        }

        let finalPlan = DailyOpsPlan(
            id: plan.id,
            goalID: plan.goalID,
            tasks: workingTasks,
            createdAt: plan.createdAt,
            executionState: planState
        )

        return PlanExecutionResult(
            plan: finalPlan,
            events: currentEvents,
            finalState: planState,
            completedTaskCount: completedCount,
            failedTaskCount: failedCount,
            unsupportedTaskCount: unsupportedCount,
            pendingApprovalCount: pendingApprovalCount
        )
    }

    /// Approves a pending approval request and resumes execution.
    public func approve(taskId: UUID) async {
        if let index = pendingApprovals.firstIndex(where: { $0.taskId == taskId }) {
            pendingApprovals[index].status = .approved
            emit(.approvalReceived(taskId: taskId, approved: true))
        }
        isPaused = false
        continuation?.resume()
        continuation = nil
    }

    /// Rejects a pending approval request.
    public func reject(taskId: UUID) async {
        if let index = pendingApprovals.firstIndex(where: { $0.taskId == taskId }) {
            pendingApprovals[index].status = .rejected
            emit(.approvalReceived(taskId: taskId, approved: false))
        }
        isPaused = false
        continuation?.resume()
        continuation = nil
    }

    /// Stops execution immediately.
    public func stop() {
        shouldStop = true
        isPaused = false
        continuation?.resume()
        continuation = nil
    }

    /// Returns current pending approvals.
    public func getPendingApprovals() -> [ApprovalRequest] {
        pendingApprovals.filter { $0.status == .pending }
    }

    /// Returns current execution events.
    public func getEvents() -> [ExecutionEvent] {
        currentEvents
    }

    private func readableUnsupportedReason(for toolId: String) -> String {
        switch toolId {
        case "calendar_events", "calendar":
            return "Calendar integration unavailable"
        case "github_issues", "github":
            return "GitHub integration unavailable"
        case "figma_pipeline", "figma":
            return "Figma integration unavailable"
        default:
            return "Tool '\(toolId)' not registered"
        }
    }

    // MARK: - Private Execution Methods

    private func executeTask(_ task: DailyOpsTask, plan: DailyOpsPlan) async -> TaskExecutionResult {
        guard let requirement = task.toolRequirement else {
            // No tool required - mark as completed with note
            emit(.taskStarted(taskId: task.id, title: task.title))
            emit(.taskCompleted(taskId: task.id))
            return .completed
        }

        emit(.taskStarted(taskId: task.id, title: task.title))

        // Resolve tool
        guard let tool = toolRegistry.tool(id: requirement.toolId) else {
            let reason = "Tool '\(requirement.toolId)' not registered"
            await markTaskUnsupported(task, reason: reason)
            return .unsupported
        }

        emit(.toolSelected(taskId: task.id, toolId: tool.id, toolName: tool.name))

        // Check permissions
        let decision = permissionManager.decision(for: requirement.riskLevel, toolId: requirement.toolId)
        emit(.permissionEvaluated(taskId: task.id, toolId: tool.id, decision: decision))

        if decision == .denied || (decision == .requiresConfirmation && requirement.riskLevel == .critical) {
            let reason = "Critical actions require explicit approval"
            await markTaskFailed(task, error: reason)
            return .failed
        }

        if decision == .requiresConfirmation {
            let request = ApprovalRequest(
                taskId: task.id,
                toolId: tool.id,
                toolName: tool.name,
                description: task.description,
                riskLevel: requirement.riskLevel,
                reason: "This action writes persistent data."
            )
            pendingApprovals.append(request)
            emit(.waitingForApproval(taskId: task.id, toolId: tool.id, reason: request.reason))
            return .waitingForApproval
        }

        // Execute safe tool
        return await executeToolSafely(task, tool: tool, requirement: requirement)
    }

    private func executeToolSafely(
        _ task: DailyOpsTask,
        tool: any DailyOpsTool,
        requirement: ToolRequirement
    ) async -> TaskExecutionResult {
        emit(.executing(taskId: task.id))

        do {
            let result = try await tool.execute(parameters: requirement.parameters)

            if result.success {
                emit(.executionSucceeded(taskId: task.id, output: result.output ?? ""))

                // Verify the result
                emit(.verificationStarted(taskId: task.id))
                let verification = try await verifierAgent.verifyPlan(
                    DailyOpsPlan(
                        id: UUID(),
                        goalID: task.id,
                        tasks: [task],
                        createdAt: Date()
                    ),
                    roleProfile: RoleEngine.shared.activeProfile
                )

                if verification.approved {
                    emit(.verificationPassed(taskId: task.id))
                    emit(.taskCompleted(taskId: task.id))
                    return .completed
                } else {
                    let issues = verification.issues.joined(separator: "; ")
                    emit(.verificationFailed(taskId: task.id, issues: verification.issues))
                    await markTaskFailed(task, error: "Verification failed: \(issues)")
                    return .failed
                }
            } else {
                let error = result.error ?? "Tool execution failed"
                emit(.executionFailed(taskId: task.id, error: error))
                await markTaskFailed(task, error: error)
                return .failed
            }
        } catch {
            let errorMsg = error.localizedDescription
            emit(.executionFailed(taskId: task.id, error: errorMsg))
            await markTaskFailed(task, error: errorMsg)
            return .failed
        }
    }

    private func waitForApproval(for task: DailyOpsTask) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func attemptRecovery(for task: DailyOpsTask, in plan: DailyOpsPlan) async -> RecoveryAction {
        let error = NSError(domain: "DailyOps", code: -1, userInfo: [NSLocalizedDescriptionKey: task.error ?? "Unknown error"])
        do {
            let action = try await recoveryAgent.recover(from: error, in: plan, roleProfile: RoleEngine.shared.activeProfile)
            emit(.recoveryAttempted(taskId: task.id, action: action))
            return action
        } catch {
            return .abort(reason: "Recovery failed: \(error.localizedDescription)")
        }
    }

    private func dependenciesSatisfied(_ task: DailyOpsTask, in tasks: [DailyOpsTask]) -> Bool {
        for depId in task.dependencies {
            if let depTask = tasks.first(where: { $0.id == depId }),
               depTask.status != .completed {
                return false
            }
        }
        return true
    }

    private func markTaskUnsupported(_ task: DailyOpsTask, reason: String) async {
        emit(.taskUnsupported(taskId: task.id, reason: reason))
        emit(.taskFailed(taskId: task.id, error: "Unsupported: \(reason)"))
    }

    private func markTaskFailed(_ task: DailyOpsTask, error: String) async {
        emit(.taskFailed(taskId: task.id, error: error))
    }

    private func emit(_ event: ExecutionEvent) {
        currentEvents.append(event)
        onEvent?(event)
    }
}

/// Internal result type for task execution
private enum TaskExecutionResult {
    case completed
    case failed
    case unsupported
    case waitingForApproval
}