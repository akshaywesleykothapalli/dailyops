import Foundation

public struct DailyOpsPlan: Sendable, Codable {
    public let id: UUID
    public let goalID: UUID
    public let tasks: [DailyOpsTask]
    public let createdAt: Date
    public var executionState: PlanExecutionState

    public init(
        id: UUID = UUID(),
        goalID: UUID,
        tasks: [DailyOpsTask],
        createdAt: Date = Date(),
        executionState: PlanExecutionState = .notStarted
    ) {
        self.id = id
        self.goalID = goalID
        self.tasks = tasks
        self.createdAt = createdAt
        self.executionState = executionState
    }
}

public enum PlanExecutionState: String, Sendable, Codable, CaseIterable {
    case notStarted
    case inProgress
    case waitingForApproval
    case completed
    case failed
    case cancelled
}