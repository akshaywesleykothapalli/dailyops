import Foundation

public enum TaskStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case inProgress
    case waitingForApproval
    case completed
    case failed
    case skipped
    case unsupported
}

public enum ActionRiskLevel: String, Sendable, Codable, CaseIterable {
    case safe
    case confirmationRequired
    case critical
}

public struct DailyOpsTask: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let description: String
    public let order: Int
    public var status: TaskStatus
    public let toolRequirement: ToolRequirement?
    public let dependencies: [UUID]
    public var result: TaskResult?
    public var error: String?

    public init(
        id: UUID = UUID(),
        title: String,
        description: String,
        order: Int,
        status: TaskStatus = .pending,
        toolRequirement: ToolRequirement? = nil,
        dependencies: [UUID] = [],
        result: TaskResult? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.order = order
        self.status = status
        self.toolRequirement = toolRequirement
        self.dependencies = dependencies
        self.result = result
        self.error = error
    }
}

public struct ToolRequirement: Sendable, Codable, Equatable {
    public let toolId: String
    public let riskLevel: ActionRiskLevel
    public let parameters: [String: String]

    public init(toolId: String, riskLevel: ActionRiskLevel, parameters: [String: String] = [:]) {
        self.toolId = toolId
        self.riskLevel = riskLevel
        self.parameters = parameters
    }
}

public struct TaskResult: Sendable, Codable, Equatable {
    public let success: Bool
    public let output: String?
    public let metadata: [String: String]

    public init(success: Bool, output: String? = nil, metadata: [String: String] = [:]) {
        self.success = success
        self.output = output
        self.metadata = metadata
    }
}