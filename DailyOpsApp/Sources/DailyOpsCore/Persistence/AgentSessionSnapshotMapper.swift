import Foundation

/// Maps live runtime state into Phase 5A persistence DTOs without modifying the runtime models.
public enum AgentSessionSnapshotMapper {

    // MARK: - Status Mapping

    public static func map(_ status: PlanExecutionState) -> PersistedSessionStatus {
        switch status {
        case .notStarted: return .planned
        case .inProgress: return .executing
        case .waitingForApproval: return .waitingForApproval
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }

    public static func map(_ status: TaskStatus) -> PersistedTaskStatus {
        switch status {
        case .pending: return .pending
        case .inProgress: return .inProgress
        case .waitingForApproval: return .waitingForApproval
        case .completed: return .completed
        case .failed: return .failed
        case .skipped: return .skipped
        case .unsupported: return .unsupported
        }
    }

    public static func map(_ riskLevel: ActionRiskLevel) -> PersistedRiskLevel {
        switch riskLevel {
        case .safe: return .safe
        case .confirmationRequired: return .confirmationRequired
        case .critical: return .critical
        }
    }

    public static func map(_ status: ApprovalStatus) -> PersistedApprovalStatus {
        switch status {
        case .pending: return .pending
        case .approved: return .approved
        case .rejected: return .rejected
        }
    }

    // MARK: - Activity Mapping

    public static func map(_ item: AgentActivityItem) -> PersistedActivityEvent {
        PersistedActivityEvent(
            id: item.id,
            stageKind: item.stage.rawValue,
            detail: item.detail,
            timestamp: item.timestamp,
            status: item.status.rawValue
        )
    }

    public static func map(_ items: [AgentActivityItem]) -> [PersistedActivityEvent] {
        items.map(map)
    }

    // MARK: - Task Mapping

    public static func map(_ task: DailyOpsTask) -> PersistedTaskSnapshot {
        PersistedTaskSnapshot(
            taskID: task.id,
            title: task.title,
            description: task.description,
            order: task.order,
            status: map(task.status),
            toolID: task.toolRequirement?.toolId,
            riskLevel: task.toolRequirement.map { map($0.riskLevel) },
            parameters: task.toolRequirement?.parameters ?? [:],
            dependencies: task.dependencies,
            resultSummary: task.result?.output,
            error: task.error,
            startedAt: nil,
            completedAt: nil
        )
    }

    public static func map(_ tasks: [DailyOpsTask]) -> [PersistedTaskSnapshot] {
        tasks.map(map)
    }

    // MARK: - Approval Mapping

    public static func map(_ request: ApprovalRequest) -> PersistedApprovalSnapshot {
        PersistedApprovalSnapshot(
            requestID: request.id,
            taskID: request.taskId,
            toolID: request.toolId,
            toolName: request.toolName,
            description: request.description,
            riskLevel: map(request.riskLevel),
            reason: request.reason,
            timestamp: request.timestamp,
            status: map(request.status)
        )
    }

    // MARK: - Snapshot Creation

    /// Creates a full session snapshot from the current runtime state.
    public static func makeSnapshot(
        sessionID: UUID,
        goal: DailyOpsGoal,
        plan: DailyOpsPlan,
        routingDecision: RoutingDecision,
        role: EmployeeRole,
        activityItems: [AgentActivityItem],
        pendingApprovals: [ApprovalRequest],
        status: PersistedSessionStatus
    ) -> AgentSessionSnapshot {
        let tasks = map(plan.tasks)
        let approval = pendingApprovals.first { $0.status == .pending }.map(map)
        let activities = map(activityItems)

        return AgentSessionSnapshot(
            schemaVersion: AgentSessionSnapshot.currentSchemaVersion,
            sessionID: sessionID,
            goalID: goal.id,
            goalText: goal.originalText,
            normalizedIntent: goal.normalizedIntent,
            role: role,
            intelligenceLevel: routingDecision.level,
            routingReason: routingDecision.reason,
            planID: plan.id,
            createdAt: goal.createdAt,
            updatedAt: Date(),
            status: status,
            tasks: tasks,
            pendingApproval: approval,
            recentActivity: activities
        )
    }
}