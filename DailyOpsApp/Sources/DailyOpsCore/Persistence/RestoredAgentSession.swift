import Foundation

/// Disposition classification for assessing if and how an agent session may be resumed.
public enum ResumeDisposition: String, Sendable, Codable, CaseIterable, Equatable {
    case safeToContinue
    case requiresUserConfirmation
    case requiresPendingApproval
    case manualReviewRequired
    case notResumable
}

/// Structured assessment of a restorable session's resumability.
public struct ResumeAssessment: Sendable, Codable, Equatable {
    public let disposition: ResumeDisposition
    public let reason: String
    public let interruptedTaskID: UUID?
    public let interruptedTaskTitle: String?
    public let pendingApproval: PersistedApprovalSnapshot?

    public init(
        disposition: ResumeDisposition,
        reason: String,
        interruptedTaskID: UUID? = nil,
        interruptedTaskTitle: String? = nil,
        pendingApproval: PersistedApprovalSnapshot? = nil
    ) {
        self.disposition = disposition
        self.reason = reason
        self.interruptedTaskID = interruptedTaskID
        self.interruptedTaskTitle = interruptedTaskTitle
        self.pendingApproval = pendingApproval
    }
}

/// Safe, read-only reconstructed runtime representation of a persisted agent session.
/// Contains complete observational state without executing any tools or triggering runtime actions.
public struct RestoredAgentSession: Sendable, Equatable, Identifiable {
    public var id: UUID { sessionID }
    public let sessionID: UUID
    public let goalID: UUID
    public let goalText: String
    public let normalizedIntent: String
    public let role: EmployeeRole
    public let intelligenceLevel: IntelligenceLevel
    public let routingReason: String
    public let planID: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let status: PersistedSessionStatus
    public let tasks: [PersistedTaskSnapshot]
    public let pendingApproval: PersistedApprovalSnapshot?
    public let recentActivity: [PersistedActivityEvent]
    public let snapshot: AgentSessionSnapshot

    public init(snapshot: AgentSessionSnapshot) {
        self.sessionID = snapshot.sessionID
        self.goalID = snapshot.goalID
        self.goalText = snapshot.goalText
        self.normalizedIntent = snapshot.normalizedIntent
        self.role = snapshot.role
        self.intelligenceLevel = snapshot.intelligenceLevel
        self.routingReason = snapshot.routingReason
        self.planID = snapshot.planID
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
        self.status = snapshot.status
        self.tasks = snapshot.tasks
        self.pendingApproval = snapshot.pendingApproval
        self.recentActivity = snapshot.recentActivity
        self.snapshot = snapshot
    }
}

/// Explicit confirmation payload required before resuming an interrupted task that may mutate state.
public struct PendingResumeConfirmation: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID { taskID }
    public let taskID: UUID
    public let taskTitle: String
    public let toolID: String?
    public let reason: String
    public let persistedState: PersistedTaskStatus
    public let riskLevel: ActionRiskLevel

    public init(
        taskID: UUID,
        taskTitle: String,
        toolID: String?,
        reason: String,
        persistedState: PersistedTaskStatus,
        riskLevel: ActionRiskLevel
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.toolID = toolID
        self.reason = reason
        self.persistedState = persistedState
        self.riskLevel = riskLevel
    }
}
