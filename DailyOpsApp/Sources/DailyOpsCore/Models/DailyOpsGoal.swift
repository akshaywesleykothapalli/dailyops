import Foundation

public enum GoalStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case planning
    case executing
    case waitingForApproval
    case completed
    case failed
    case cancelled
}

public enum GoalComplexity: String, Sendable, Codable, CaseIterable {
    case trivial
    case simple
    case moderate
    case complex
    case multiAgent
}

public enum GoalSource: String, Sendable, Codable, CaseIterable {
    case voice
    case text
    case scheduled
    case shortcut
}

public struct DailyOpsGoal: Sendable, Codable, Identifiable {
    public let id: UUID
    public let originalText: String
    public var normalizedIntent: String
    public let createdAt: Date
    public var status: GoalStatus
    public var complexity: GoalComplexity
    public let source: GoalSource
    public var roleContext: RoleContext?
    public var planID: UUID?

    public init(
        id: UUID = UUID(),
        originalText: String,
        normalizedIntent: String,
        createdAt: Date = Date(),
        status: GoalStatus = .pending,
        complexity: GoalComplexity = .simple,
        source: GoalSource = .text,
        roleContext: RoleContext? = nil,
        planID: UUID? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.normalizedIntent = normalizedIntent
        self.createdAt = createdAt
        self.status = status
        self.complexity = complexity
        self.source = source
        self.roleContext = roleContext
        self.planID = planID
    }
}