import Foundation

/// Persistence-specific session execution status.
public enum PersistedSessionStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case planned
    case executing
    case paused
    case waitingForApproval
    case completed
    case failed
    case cancelled
}

/// Persistence-specific task status.
public enum PersistedTaskStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case pending
    case inProgress
    case waitingForApproval
    case completed
    case failed
    case skipped
    case unsupported
}

/// Persistence-specific action risk level.
public enum PersistedRiskLevel: String, Sendable, Codable, CaseIterable, Equatable {
    case safe
    case confirmationRequired
    case critical
}

/// Persistence-specific approval status.
public enum PersistedApprovalStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case pending
    case approved
    case rejected
}

/// Persistent snapshot of an action awaiting human approval.
public struct PersistedApprovalSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID { requestID }
    public let requestID: UUID
    public let taskID: UUID
    public let toolID: String
    public let toolName: String
    public let description: String
    public let riskLevel: PersistedRiskLevel
    public let reason: String
    public let timestamp: Date
    public let status: PersistedApprovalStatus

    public init(
        requestID: UUID = UUID(),
        taskID: UUID,
        toolID: String,
        toolName: String,
        description: String,
        riskLevel: PersistedRiskLevel,
        reason: String,
        timestamp: Date = Date(),
        status: PersistedApprovalStatus = .pending
    ) {
        self.requestID = requestID
        self.taskID = taskID
        self.toolID = toolID
        self.toolName = toolName
        self.description = description
        self.riskLevel = riskLevel
        self.reason = reason
        self.timestamp = timestamp
        self.status = status
    }
}

/// Persistent snapshot of an individual task state within a plan.
public struct PersistedTaskSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID { taskID }
    public let taskID: UUID
    public let title: String
    public let description: String
    public let order: Int
    public let status: PersistedTaskStatus
    public let toolID: String?
    public let riskLevel: PersistedRiskLevel?
    public let parameters: [String: String]?
    public let dependencies: [UUID]
    public let resultSummary: String?
    public let error: String?
    public let startedAt: Date?
    public let completedAt: Date?

    public init(
        taskID: UUID = UUID(),
        title: String,
        description: String,
        order: Int,
        status: PersistedTaskStatus = .pending,
        toolID: String? = nil,
        riskLevel: PersistedRiskLevel? = nil,
        parameters: [String: String]? = [:],
        dependencies: [UUID] = [],
        resultSummary: String? = nil,
        error: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.taskID = taskID
        self.title = title
        self.description = description
        self.order = order
        self.status = status
        self.toolID = toolID
        self.riskLevel = riskLevel
        self.parameters = parameters
        self.dependencies = dependencies
        self.resultSummary = resultSummary
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// Factual activity event record for persistence.
public struct PersistedActivityEvent: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let stageKind: String
    public let detail: String?
    public let timestamp: Date
    public let status: String

    public init(
        id: UUID = UUID(),
        stageKind: String,
        detail: String? = nil,
        timestamp: Date = Date(),
        status: String = "completed"
    ) {
        self.id = id
        self.stageKind = stageKind
        self.detail = detail
        self.timestamp = timestamp
        self.status = status
    }
}

/// Self-contained persistent representation of an agent session.
/// Designed for safe on-disk storage and future resumption without modifying live runtime models.
public struct AgentSessionSnapshot: Sendable, Codable, Equatable, Identifiable {
    public static let currentSchemaVersion: Int = 2
    public static let maxActivityEvents: Int = 100

    public var id: UUID { sessionID }

    public let schemaVersion: Int
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

    public init(
        schemaVersion: Int = AgentSessionSnapshot.currentSchemaVersion,
        sessionID: UUID = UUID(),
        goalID: UUID = UUID(),
        goalText: String,
        normalizedIntent: String = "",
        role: EmployeeRole = .general,
        intelligenceLevel: IntelligenceLevel = .L0,
        routingReason: String = "",
        planID: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: PersistedSessionStatus = .planned,
        tasks: [PersistedTaskSnapshot] = [],
        pendingApproval: PersistedApprovalSnapshot? = nil,
        recentActivity: [PersistedActivityEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.goalID = goalID
        self.goalText = goalText
        self.normalizedIntent = normalizedIntent
        self.role = role
        self.intelligenceLevel = intelligenceLevel
        self.routingReason = routingReason
        self.planID = planID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.tasks = tasks
        self.pendingApproval = pendingApproval
        // Cap factual activity history to maxActivityEvents
        if recentActivity.count > AgentSessionSnapshot.maxActivityEvents {
            self.recentActivity = Array(recentActivity.suffix(AgentSessionSnapshot.maxActivityEvents))
        } else {
            self.recentActivity = recentActivity
        }
    }
}
