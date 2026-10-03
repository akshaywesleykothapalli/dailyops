import Foundation
import SwiftUI
import DailyOps

/// Stage of the deterministic agent pipeline.
public enum AgentActivityStageKind: String, Sendable, Codable, CaseIterable {
    case goalUnderstood = "Goal understood"
    case roleContextLoaded = "Role context loaded"
    case complexityEvaluated = "Complexity evaluated"
    case planCreated = "Plan created"
    case permissionsEvaluated = "Permissions evaluated"
    case planVerified = "Plan verified"
    case executionStarted = "Execution started"
    case toolSelected = "Tool selected"
    case executing = "Executing"
    case executionSucceeded = "Execution succeeded"
    case verificationPassed = "Verification passed"
    case taskCompleted = "Task completed"
    case waitingForApproval = "Waiting for approval"
    case approvalReceived = "Approval received"
    case executionCompleted = "Execution completed"
    case executionFailed = "Execution failed"
    case executionPaused = "Execution paused"
    case executionResumed = "Execution resumed"
    case recoveryAttempted = "Recovery attempted"
    case taskUnsupported = "Integration not connected"
}

public enum ActivityItemStatus: String, Sendable, Codable {
    case running
    case completed
    case warning
    case failed
    case waiting
}

/// Represents an actual system event during plan generation and execution.
public struct AgentActivityItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let stage: AgentActivityStageKind
    public let detail: String?
    public let timestamp: Date
    public let isCompleted: Bool
    public let status: ActivityItemStatus

    public init(
        id: UUID = UUID(),
        stage: AgentActivityStageKind,
        detail: String? = nil,
        timestamp: Date = Date(),
        isCompleted: Bool = true,
        status: ActivityItemStatus = .completed
    ) {
        self.id = id
        self.stage = stage
        self.detail = detail
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.status = status
    }
}

public struct CurrentActionInfo: Sendable, Equatable {
    public let title: String
    public let toolName: String
    public let toolId: String
    public let permission: String
    public let status: String

    public init(
        title: String,
        toolName: String,
        toolId: String,
        permission: String,
        status: String
    ) {
        self.title = title
        self.toolName = toolName
        self.toolId = toolId
        self.permission = permission
        self.status = status
    }
}

/// Main-actor session controller managing DailyOps agent execution for SwiftUI.
/// Holds state, interfaces with `DailyOpsRuntime` and `PlanExecutionEngine`, and provides reactive state to the UI.
@MainActor
@Observable
public final class AgentSessionController {
    public static let shared = AgentSessionController()

    public let runtime: DailyOpsRuntime
    public let roleEngine: RoleEngine
    public let executionEngine: PlanExecutionEngine

    public private(set) var latestVoiceIntent: VoiceIntentDecision?

    public private(set) var currentGoal: DailyOpsGoal?
    public private(set) var currentPlan: DailyOpsPlan?
    public private(set) var routingDecision: RoutingDecision?
    public private(set) var permissionDecisions: [String: PermissionDecision] = [:]
    public private(set) var verificationResult: VerificationResult?
    public private(set) var executionState: PlanExecutionState = .notStarted
    public private(set) var error: String?
    public private(set) var isProcessing: Bool = false
    public private(set) var activityStages: [AgentActivityItem] = []
    public private(set) var pendingApprovals: [ApprovalRequest] = []
    public private(set) var currentAction: CurrentActionInfo?

    /// Stable persistence session ID for the current goal lifecycle.
    /// Remains constant across planned → executing → waitingForApproval → completed/failed.
    public private(set) var sessionID: UUID?

    /// Internal store reference for restorable session detection.
    private let sessionStore: AgentSessionStore

    /// Internal checkpoint coordinator for persistence operations.
    private let checkpointCoordinator: AgentSessionCheckpointCoordinator

    /// Whether an active restorable session was detected in persistence.
    public private(set) var hasRestorableSession: Bool = false

    /// Reconstructed read-only snapshot representation of the detected session.
    public private(set) var restoredSession: RestoredAgentSession?

    /// Resume policy assessment for the restorable session.
    public private(set) var resumeAssessment: ResumeAssessment?

    /// Any error encountered while checking or loading restorable session.
    public private(set) var restorationError: String?

    /// Controller-level pending confirmation for resuming a potentially mutating interrupted task.
    public private(set) var pendingResumeConfirmation: PendingResumeConfirmation?

    /// Whether the controller is currently in the process of resuming execution.
    public private(set) var isResuming: Bool = false

    /// Any error encountered during resumption attempt.
    public private(set) var resumeError: String?

    public var canAcceptVoiceIntent: Bool {
        !isProcessing && !isResuming && executionState != .inProgress && executionState != .waitingForApproval
    }

    public var isExecuting: Bool {
        executionState == .inProgress
    }

    public var activeRole: EmployeeRole {
        get { roleEngine.activeRole }
        set { setRole(newValue) }
    }

    public var planTasks: [DailyOpsTask] {
        currentPlan?.tasks ?? []
    }

    public var hasPendingApproval: Bool {
        pendingApprovals.contains { $0.status == .pending }
    }

    public var currentApprovalRequest: ApprovalRequest? {
        pendingApprovals.first { $0.status == .pending }
    }

    public init(
        runtime: DailyOpsRuntime = DailyOpsRuntime.shared,
        roleEngine: RoleEngine = RoleEngine.shared,
        executionEngine: PlanExecutionEngine = PlanExecutionEngine.shared,
        sessionStore: AgentSessionStore = AgentSessionStore.shared
    ) {
        self.runtime = runtime
        self.roleEngine = roleEngine
        self.executionEngine = executionEngine
        self.sessionStore = sessionStore
        self.checkpointCoordinator = AgentSessionCheckpointCoordinator(store: sessionStore)
    }

    public func setRole(_ role: EmployeeRole) {
        roleEngine.setRole(role)
    }

    /// Submits a user goal to the DailyOps runtime, recording real system activity stages.
    @discardableResult
    public func submitGoal(_ text: String, source: GoalSource = .text) async -> RuntimeResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let emptyDecision = RoutingDecision(level: .L0, reason: "Empty goal")
            let emptyGoal = DailyOpsGoal(
                originalText: text,
                normalizedIntent: "",
                complexity: .trivial,
                source: source,
                roleContext: RoleContext(role: activeRole)
            )
            let result = RuntimeResult(
                goal: emptyGoal,
                plan: nil,
                routingDecision: emptyDecision,
                permissionDecisions: [:],
                verification: nil,
                error: "Goal cannot be empty"
            )
            self.error = "Goal cannot be empty"
            self.currentGoal = emptyGoal
            self.currentPlan = nil
            self.routingDecision = emptyDecision
            self.executionState = .failed
            return result
        }

        isProcessing = true
        error = nil
        activityStages.removeAll()
        pendingApprovals.removeAll()

        let currentActiveRole = activeRole

        // Real Stage 1: Goal understood
        activityStages.append(AgentActivityItem(
            stage: .goalUnderstood,
            detail: trimmed,
            status: .completed
        ))

        // Real Stage 2: Role context loaded
        activityStages.append(AgentActivityItem(
            stage: .roleContextLoaded,
            detail: "Role: \(currentActiveRole.displayName)",
            status: .completed
        ))

        // Real Stage 3: Complexity evaluated
        let initialRoute = ComplexityRouter.shared.route(trimmed, role: currentActiveRole)
        activityStages.append(AgentActivityItem(
            stage: .complexityEvaluated,
            detail: "\(initialRoute.level.rawValue) · \(initialRoute.reason)",
            status: .completed
        ))

        // Submit to the authoritative DailyOps runtime
        let result = await runtime.submitGoal(trimmed, source: source)

        self.currentGoal = result.goal
        self.currentPlan = result.plan
        self.routingDecision = result.routingDecision
        self.permissionDecisions = result.permissionDecisions
        self.verificationResult = result.verification
        self.error = result.error

        if let plan = result.plan {
            self.executionState = plan.executionState
            for task in plan.tasks where task.status == .skipped {
                activityStages.append(AgentActivityItem(stage: .taskUnsupported, detail: task.error, status: .warning))
            }

            // Start new persistence session for this goal
            self.sessionID = checkpointCoordinator.startNewSession()

            // Real Stage 4: Plan created
            activityStages.append(AgentActivityItem(
                stage: .planCreated,
                detail: "\(plan.tasks.count) ordered steps",
                status: .completed
            ))

            // Real Stage 5: Permissions evaluated
            let permCount = result.permissionDecisions.count
            activityStages.append(AgentActivityItem(
                stage: .permissionsEvaluated,
                detail: permCount > 0 ? "\(permCount) tool permission(s) verified" : "All tools safe",
                status: .completed
            ))

            // Real Stage 6: Plan verified
            if let verification = result.verification {
                let detailText = verification.approved ? "Approved" : "Requires review: \(verification.issues.joined(separator: ", "))"
                activityStages.append(AgentActivityItem(
                    stage: .planVerified,
                    detail: detailText,
                    status: .completed
                ))
            } else {
                activityStages.append(AgentActivityItem(
                    stage: .planVerified,
                    detail: "Verified",
                    status: .completed
                ))
            }

            // CHECKPOINT: Plan created — persist as planned
            let goal = result.goal
            let routing = result.routingDecision
            if let sessionID = self.sessionID {
                let snapshot = AgentSessionSnapshotMapper.makeSnapshot(
                    sessionID: sessionID,
                    goal: goal,
                    plan: plan,
                    routingDecision: routing,
                    role: currentActiveRole,
                    activityItems: activityStages,
                    pendingApprovals: pendingApprovals,
                    status: .planned
                )
                checkpointCoordinator.checkpoint(snapshot, status: .planned)
            }
        } else {
            self.executionState = .failed
        }

        isProcessing = false
        return result
    }

    /// Shared post-STT route used by every Command Mode entry point.
    public func voiceDecision(_ transcript: String, enabled: Bool = true) -> VoiceIntentDecision {
        VoiceIntentRouter().route(transcript, role: activeRole, profiles: RoleWorkspaceStore.shared.load(), enabled: enabled)
    }

    public func handleVoiceIntent(_ decision: VoiceIntentDecision, transcript: String) async {
        guard decision.kind != .dictation, canAcceptVoiceIntent else { return }
        latestVoiceIntent = decision
        if decision.kind == .roleWorkflow { setRole(decision.role) }
        _ = await submitGoal(transcript, source: .voice)
        if decision.kind != .dailyOpsGoal, error == nil { await executePlan() }
    }

    /// Executes the current plan using the PlanExecutionEngine.
    public func executePlan() async {
        guard let plan = currentPlan else { return }
        // Prevent duplicate execution
        guard !isProcessing, executionState != .inProgress, executionState != .waitingForApproval else { return }

        isProcessing = true
        error = nil
        executionState = .inProgress

        // Add execution-specific activity stage
        activityStages.append(AgentActivityItem(
            stage: .executionStarted,
            detail: "Executing \(plan.tasks.count) steps",
            status: .running
        ))

        // CHECKPOINT: Execution started — persist as executing
        if let goal = currentGoal, let routing = routingDecision, let sessionID = sessionID {
            let snapshot = AgentSessionSnapshotMapper.makeSnapshot(
                sessionID: sessionID,
                goal: goal,
                plan: plan,
                routingDecision: routing,
                role: activeRole,
                activityItems: activityStages,
                pendingApprovals: pendingApprovals,
                status: .executing
            )
            checkpointCoordinator.checkpoint(snapshot, status: .executing)
        }

        let result = await executionEngine.executePlan(plan, onEvent: { [weak self] event in
            self?.handleExecutionEvent(event)
        })

        // Update session state with execution results
        self.currentPlan = result.plan
        self.executionState = result.finalState
        self.pendingApprovals = await executionEngine.getPendingApprovals()
        self.currentAction = nil

        if result.finalState == .completed {
            activityStages.append(AgentActivityItem(
                stage: .executionCompleted,
                detail: "\(result.completedTaskCount) tasks completed",
                status: .completed
            ))
        } else if result.finalState == .failed {
            activityStages.append(AgentActivityItem(
                stage: .executionFailed,
                detail: "\(result.failedTaskCount) task(s) failed; \(result.unsupportedTaskCount) task(s) unsupported",
                status: .failed
            ))
        } else if result.finalState == .waitingForApproval {
            activityStages.append(AgentActivityItem(
                stage: .waitingForApproval,
                detail: "\(result.pendingApprovalCount) approval(s) required",
                status: .waiting
            ))
        }

        isProcessing = false
    }

    /// Approves the current pending approval and continues execution.
    public func approveCurrentAction() async {
        guard let request = currentApprovalRequest else { return }

        pendingApprovals.removeAll { $0.id == request.id }

        activityStages.append(AgentActivityItem(
            stage: .approvalReceived,
            detail: "Approved: \(request.toolName)",
            status: .completed
        ))

        await executionEngine.approve(taskId: request.taskId)

        // Checkpoint approval
        checkpointAfterEvent(status: .executing)
    }

    /// Rejects the current pending approval.
    public func rejectCurrentAction() async {
        guard let request = currentApprovalRequest else { return }

        pendingApprovals.removeAll { $0.id == request.id }

        activityStages.append(AgentActivityItem(
            stage: .approvalReceived,
            detail: "Rejected: \(request.toolName)",
            status: .failed
        ))

        await executionEngine.reject(taskId: request.taskId)

        // Checkpoint rejection
        checkpointAfterEvent(status: .failed)
    }

    /// Resets the current session state.
    public func resetSession() {
        currentGoal = nil
        currentPlan = nil
        routingDecision = nil
        permissionDecisions = [:]
        verificationResult = nil
        executionState = .notStarted
        error = nil
        isProcessing = false
        activityStages.removeAll()
        pendingApprovals.removeAll()
        currentAction = nil
        sessionID = nil
        checkpointCoordinator.clearSessionIdentity()
        pendingResumeConfirmation = nil
        isResuming = false
        resumeError = nil
    }

    /// Resets the current plan's tasks to pending and re-runs execution.
    public func runAgain() async {
        guard let plan = currentPlan else { return }
        let resetTasks = plan.tasks.map { task in
            var reset = task
            reset.status = .pending
            reset.error = nil
            reset.result = nil
            return reset
        }
        self.currentPlan = DailyOpsPlan(
            id: plan.id,
            goalID: plan.goalID,
            tasks: resetTasks,
            createdAt: plan.createdAt,
            executionState: .notStarted
        )
        self.executionState = .notStarted
        self.pendingApprovals.removeAll()
        self.currentAction = nil
        await executePlan()
    }

    // MARK: - Restorable Session Detection (Observational Only)

    /// Checks active storage for an unfinished persisted session and performs safe assessment.
    /// Does NOT execute any tools or start the execution engine.
    public func checkForRestorableSession() async {
        do {
            if let snapshot = try sessionStore.loadActive() {
                let restored = RestoredAgentSession(snapshot: snapshot)
                let assessment = AgentSessionResumePolicy.evaluate(snapshot)

                self.restoredSession = restored
                self.resumeAssessment = assessment
                self.hasRestorableSession = true
                self.restorationError = nil
            } else {
                self.restoredSession = nil
                self.resumeAssessment = nil
                self.hasRestorableSession = false
                self.restorationError = nil
            }
        } catch {
            self.restoredSession = nil
            self.resumeAssessment = nil
            self.hasRestorableSession = false
            self.restorationError = error.localizedDescription
        }
    }

    /// Returns the currently inspected restorable session without side effects.
    public func inspectRestorableSession() -> RestoredAgentSession? {
        restoredSession
    }

    /// Safely discards the detected active restorable session from storage.
    /// Does NOT delete archive history or affect any active in-memory session.
    public func discardRestorableSession() async {
        try? sessionStore.clearActive()
        self.restoredSession = nil
        self.resumeAssessment = nil
        self.hasRestorableSession = false
        self.restorationError = nil
        self.pendingResumeConfirmation = nil
    }

    // MARK: - Explicit Resumption (Phase 5D1)

    /// Explicitly requests resumption of a restorable session.
    /// Evaluates resume assessment; if safeToContinue, proceeds with execution.
    /// If requiresUserConfirmation, sets pendingResumeConfirmation without executing.
    /// If requiresPendingApproval, re-enters permission flow for fresh approval.
    /// If manualReviewRequired or notResumable, safely refuses.
    public func resumeRestoredSession() async {
        guard !isProcessing, !isResuming, executionState != .inProgress else { return }

        // Load active snapshot if not already inspected
        let snapshot: AgentSessionSnapshot
        if let inspected = restoredSession?.snapshot {
            snapshot = inspected
        } else {
            do {
                guard let loaded = try sessionStore.loadActive() else {
                    self.resumeError = "No restorable session found."
                    return
                }
                snapshot = loaded
                self.restoredSession = RestoredAgentSession(snapshot: snapshot)
                self.hasRestorableSession = true
            } catch {
                self.resumeError = "Failed to load restorable session: \(error.localizedDescription)"
                return
            }
        }

        // Evaluate deterministically
        let assessment = AgentSessionResumePolicy.evaluate(snapshot)
        self.resumeAssessment = assessment

        switch assessment.disposition {
        case .notResumable, .manualReviewRequired:
            self.resumeError = assessment.reason
            return

        case .requiresUserConfirmation:
            // Interrupted mutation or critical action: expose confirmation, DO NOT execute
            let interrupted = snapshot.tasks.first(where: { $0.taskID == assessment.interruptedTaskID })
                ?? snapshot.tasks.first(where: { $0.status == .inProgress || $0.status == .waitingForApproval })
                ?? snapshot.tasks.first(where: { $0.status == .pending })

            let taskID = interrupted?.taskID ?? UUID()
            let taskTitle = interrupted?.title ?? assessment.interruptedTaskTitle ?? "Interrupted Action"
            let toolID = interrupted?.toolID
            let status = interrupted?.status ?? .inProgress
            let risk: ActionRiskLevel = {
                switch interrupted?.riskLevel {
                case .safe: return .safe
                case .confirmationRequired: return .confirmationRequired
                case .critical: return .critical
                case .none: return .safe
                }
            }()

            self.pendingResumeConfirmation = PendingResumeConfirmation(
                taskID: taskID,
                taskTitle: taskTitle,
                toolID: toolID,
                reason: assessment.reason,
                persistedState: status,
                riskLevel: risk
            )
            self.resumeError = nil
            return

        case .safeToContinue, .requiresPendingApproval:
            await executeResumption(snapshot: snapshot)
        }
    }

    /// User explicitly confirms resumption of a risky/mutating interrupted session.
    /// Resumes execution which will then pass through standard PermissionManager gating.
    public func confirmRiskyResume() async {
        guard pendingResumeConfirmation != nil else { return }
        self.pendingResumeConfirmation = nil

        guard let snapshot = restoredSession?.snapshot ?? (try? sessionStore.loadActive()) else {
            self.resumeError = "No restorable session found to resume."
            return
        }

        await executeResumption(snapshot: snapshot)
    }

    /// Cancels a pending risky resume confirmation.
    /// Executes ZERO tools and preserves the persisted active session without deleting it.
    public func cancelRiskyResume() {
        self.pendingResumeConfirmation = nil
        self.isResuming = false
        self.resumeError = nil
    }

    private func executeResumption(snapshot: AgentSessionSnapshot) async {
        isResuming = true
        isProcessing = true
        resumeError = nil

        // 1. Role restoration: apply persisted role ONLY when execution actually resumes
        setRole(snapshot.role)

        // 2. Build reconstructed plan
        let plan: DailyOpsPlan
        do {
            plan = try RestoredExecutionPlanBuilder.build(from: snapshot)
        } catch {
            self.resumeError = error.localizedDescription
            self.isResuming = false
            self.isProcessing = false
            return
        }

        // 3. Establish runtime state with original session identity
        let restoredGoal = DailyOpsGoal(
            id: snapshot.goalID,
            originalText: snapshot.goalText,
            normalizedIntent: snapshot.normalizedIntent,
            createdAt: snapshot.createdAt,
            source: .text
        )
        self.currentGoal = restoredGoal
        self.currentPlan = plan
        self.routingDecision = RoutingDecision(level: snapshot.intelligenceLevel, reason: snapshot.routingReason)
        self.sessionID = snapshot.sessionID
        self.checkpointCoordinator.setResumedSessionID(snapshot.sessionID)
        self.hasRestorableSession = false

        // Activity stages: restore recent activity + resume event
        self.activityStages = snapshot.recentActivity.map { event in
            AgentActivityItem(
                id: event.id,
                stage: AgentActivityStageKind(rawValue: event.stageKind) ?? .executionStarted,
                detail: event.detail,
                timestamp: event.timestamp,
                status: ActivityItemStatus(rawValue: event.status) ?? .completed
            )
        }
        self.activityStages.append(AgentActivityItem(
            stage: .executionResumed,
            detail: "Resumed session from checkpoint",
            status: .running
        ))

        self.executionState = .inProgress

        // Checkpoint executing state under the SAME session ID
        checkpointAfterEvent(status: .executing)

        // 4. Run through standard execution engine
        let result = await executionEngine.executePlan(plan, onEvent: { [weak self] event in
            self?.handleExecutionEvent(event)
        })

        // 5. Update state
        self.currentPlan = result.plan
        self.executionState = result.finalState
        self.pendingApprovals = await executionEngine.getPendingApprovals()
        self.currentAction = nil

        if result.finalState == .completed {
            activityStages.append(AgentActivityItem(
                stage: .executionCompleted,
                detail: "\(result.completedTaskCount) tasks completed",
                status: .completed
            ))
            checkpointAfterEvent(status: .completed)
        } else if result.finalState == .failed {
            activityStages.append(AgentActivityItem(
                stage: .executionFailed,
                detail: "\(result.failedTaskCount) task(s) failed; \(result.unsupportedTaskCount) task(s) unsupported",
                status: .failed
            ))
            checkpointAfterEvent(status: .failed)
        } else if result.finalState == .waitingForApproval {
            activityStages.append(AgentActivityItem(
                stage: .waitingForApproval,
                detail: "\(result.pendingApprovalCount) approval(s) required",
                status: .waiting
            ))
            checkpointAfterEvent(status: .waitingForApproval)
        }

        self.isResuming = false
        self.isProcessing = false
    }

    // MARK: - Event Handlers

    private func handleExecutionEvent(_ event: ExecutionEvent) {
        switch event {
        case .taskStarted(let taskId, let title):
            updateTaskStatus(taskId: taskId, status: .inProgress)
            currentAction = CurrentActionInfo(
                title: title,
                toolName: "Resolving tool...",
                toolId: "",
                permission: "Evaluating...",
                status: "Executing"
            )
            activityStages.append(AgentActivityItem(stage: .executing, detail: title, status: .running))
            checkpointAfterEvent(status: .executing)

        case .toolSelected(let taskId, let toolId, let toolName):
            if let cur = currentAction {
                currentAction = CurrentActionInfo(
                    title: cur.title,
                    toolName: toolName,
                    toolId: toolId,
                    permission: cur.permission,
                    status: "Executing"
                )
            }
            activityStages.append(AgentActivityItem(stage: .toolSelected, detail: "\(toolName) (\(toolId))", status: .running))
            checkpointAfterEvent(status: .executing)

        case .permissionEvaluated(let taskId, let toolId, let decision):
            if let cur = currentAction {
                currentAction = CurrentActionInfo(
                    title: cur.title,
                    toolName: cur.toolName,
                    toolId: toolId,
                    permission: decision.rawValue,
                    status: "Executing"
                )
            }
            activityStages.append(AgentActivityItem(stage: .permissionsEvaluated, detail: "\(toolId): \(decision.rawValue)", status: .completed))
            checkpointAfterEvent(status: .executing)

        case .executing(let taskId):
            if let cur = currentAction {
                currentAction = CurrentActionInfo(
                    title: cur.title,
                    toolName: cur.toolName,
                    toolId: cur.toolId,
                    permission: cur.permission,
                    status: "Executing"
                )
            }

        case .executionSucceeded(let taskId, let output):
            activityStages.append(AgentActivityItem(stage: .executionSucceeded, detail: output, status: .completed))
            checkpointAfterEvent(status: .executing)

        case .verificationStarted:
            break

        case .verificationPassed:
            activityStages.append(AgentActivityItem(stage: .verificationPassed, detail: "Verified", status: .completed))
            checkpointAfterEvent(status: .executing)

        case .verificationFailed(let taskId, let issues):
            activityStages.append(AgentActivityItem(stage: .executionFailed, detail: "Verification failed: \(issues.joined(separator: ", "))", status: .failed))
            checkpointAfterEvent(status: .executing)

        case .taskCompleted(let taskId):
            updateTaskStatus(taskId: taskId, status: .completed)
            activityStages.append(AgentActivityItem(stage: .taskCompleted, detail: "Task completed", status: .completed))
            currentAction = nil
            checkpointAfterEvent(status: .executing)

        case .taskFailed(let taskId, let error):
            updateTaskStatus(taskId: taskId, status: .failed, error: error)
            activityStages.append(AgentActivityItem(stage: .executionFailed, detail: error, status: .failed))
            currentAction = nil
            checkpointAfterEvent(status: .executing)

        case .taskUnsupported(let taskId, let reason):
            updateTaskStatus(taskId: taskId, status: .unsupported, error: reason)
            activityStages.append(AgentActivityItem(stage: .taskUnsupported, detail: reason, status: .warning))
            currentAction = nil
            checkpointAfterEvent(status: .executing)

        case .waitingForApproval(let taskId, let toolId, let reason):
            updateTaskStatus(taskId: taskId, status: .waitingForApproval)
            executionState = .waitingForApproval
            pendingApprovals = executionEngine.getPendingApprovals()
            currentAction = CurrentActionInfo(
                title: currentAction?.title ?? "Action requires approval",
                toolName: currentAction?.toolName ?? toolId,
                toolId: toolId,
                permission: "Confirmation Required",
                status: "Waiting for approval"
            )
            activityStages.append(AgentActivityItem(stage: .waitingForApproval, detail: reason, status: .waiting))
            checkpointAfterEvent(status: .waitingForApproval)

        case .approvalReceived(let taskId, let approved):
            activityStages.append(AgentActivityItem(stage: .approvalReceived, detail: approved ? "Approved" : "Rejected", status: approved ? .completed : .failed))
            if approved {
                if let cur = currentAction {
                    currentAction = CurrentActionInfo(
                        title: cur.title,
                        toolName: cur.toolName,
                        toolId: cur.toolId,
                        permission: "Approved",
                        status: "Resuming..."
                    )
                }
            } else {
                currentAction = nil
            }
            checkpointAfterEvent(status: approved ? .executing : .failed)

        case .recoveryAttempted(let taskId, let action):
            activityStages.append(AgentActivityItem(stage: .recoveryAttempted, detail: "Recovery: \(action)", status: .warning))
            checkpointAfterEvent(status: .executing)

        case .executionPaused:
            executionState = .waitingForApproval
            activityStages.append(AgentActivityItem(stage: .executionPaused, detail: "Execution paused for approval", status: .waiting))
            checkpointAfterEvent(status: .paused)

        case .executionResumed:
            executionState = .inProgress
            activityStages.append(AgentActivityItem(stage: .executionResumed, detail: "Execution resumed", status: .running))
            checkpointAfterEvent(status: .executing)

        case .executionCompleted:
            currentAction = nil
            checkpointAfterEvent(status: .completed)

        case .executionFailedOverall(let planId, let error):
            executionState = .failed
            currentAction = nil
            checkpointAfterEvent(status: .failed)

        default:
            break
        }
    }

    /// Checkpoints the current session state after a meaningful execution event.
    private func checkpointAfterEvent(status: PersistedSessionStatus) {
        guard let goal = currentGoal,
              let plan = currentPlan,
              let routing = routingDecision,
              let sessionID = sessionID else { return }

        let snapshot = AgentSessionSnapshotMapper.makeSnapshot(
            sessionID: sessionID,
            goal: goal,
            plan: plan,
            routingDecision: routing,
            role: activeRole,
            activityItems: activityStages,
            pendingApprovals: pendingApprovals,
            status: status
        )
        checkpointCoordinator.checkpoint(snapshot, status: status)
    }

    private func updateTaskStatus(taskId: UUID, status: TaskStatus, error: String? = nil) {
        guard var plan = currentPlan,
              let index = plan.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        var updatedTask = plan.tasks[index]
        updatedTask.status = status
        if let error = error {
            updatedTask.error = error
        }
        var updatedTasks = plan.tasks
        updatedTasks[index] = updatedTask
        self.currentPlan = DailyOpsPlan(
            id: plan.id,
            goalID: plan.goalID,
            tasks: updatedTasks,
            createdAt: plan.createdAt,
            executionState: self.executionState
        )
    }

    private func convertEventToActivityItem(_ event: ExecutionEvent) -> AgentActivityItem {
        switch event {
        case .goalAccepted(let goalId, let text):
            return AgentActivityItem(stage: .goalUnderstood, detail: text, status: .completed)
        case .roleLoaded(let role):
            return AgentActivityItem(stage: .roleContextLoaded, detail: "Role: \(role.displayName)", status: .completed)
        case .planGenerated(let planId, let taskCount):
            return AgentActivityItem(stage: .planCreated, detail: "\(taskCount) ordered steps", status: .completed)
        case .executionStarted(let planId):
            return AgentActivityItem(stage: .executionStarted, detail: "Execution started", status: .running)
        case .taskStarted(let taskId, let title):
            return AgentActivityItem(stage: .executing, detail: title, status: .running)
        case .toolSelected(let taskId, let toolId, let toolName):
            return AgentActivityItem(stage: .toolSelected, detail: "\(toolName) (\(toolId))", status: .running)
        case .permissionEvaluated(let taskId, let toolId, let decision):
            return AgentActivityItem(stage: .permissionsEvaluated, detail: "\(toolId): \(decision.rawValue)", status: .completed)
        case .executing(let taskId):
            return AgentActivityItem(stage: .executing, detail: "Running...", status: .running)
        case .executionSucceeded(let taskId, let output):
            return AgentActivityItem(stage: .executionSucceeded, detail: output, status: .completed)
        case .executionFailed(let taskId, let error):
            return AgentActivityItem(stage: .executionFailed, detail: error, status: .failed)
        case .verificationStarted(let taskId):
            return AgentActivityItem(stage: .planVerified, detail: "Verifying...", status: .running)
        case .verificationPassed(let taskId):
            return AgentActivityItem(stage: .verificationPassed, detail: "Verified", status: .completed)
        case .verificationFailed(let taskId, let issues):
            return AgentActivityItem(stage: .executionFailed, detail: "Verification failed: \(issues.joined(separator: ", "))", status: .failed)
        case .taskCompleted(let taskId):
            return AgentActivityItem(stage: .taskCompleted, detail: "Completed", status: .completed)
        case .taskFailed(let taskId, let error):
            return AgentActivityItem(stage: .executionFailed, detail: error, status: .failed)
        case .taskUnsupported(let taskId, let reason):
            return AgentActivityItem(stage: .taskUnsupported, detail: reason, status: .warning)
        case .waitingForApproval(let taskId, let toolId, let reason):
            return AgentActivityItem(stage: .waitingForApproval, detail: reason, status: .waiting)
        case .approvalReceived(let taskId, let approved):
            return AgentActivityItem(stage: .approvalReceived, detail: approved ? "Approved" : "Rejected", status: approved ? .completed : .failed)
        case .recoveryAttempted(let taskId, let action):
            return AgentActivityItem(stage: .recoveryAttempted, detail: "Recovery: \(action)", status: .warning)
        case .executionPaused(let planId):
            return AgentActivityItem(stage: .executionPaused, detail: "Execution paused for approval", status: .waiting)
        case .executionResumed(let planId):
            return AgentActivityItem(stage: .executionResumed, detail: "Resumed after approval", status: .running)
        case .executionCompleted(let planId):
            return AgentActivityItem(stage: .executionCompleted, detail: "Execution completed", status: .completed)
        case .executionFailedOverall(let planId, let error):
            return AgentActivityItem(stage: .executionFailed, detail: error, status: .failed)
        }
    }
}