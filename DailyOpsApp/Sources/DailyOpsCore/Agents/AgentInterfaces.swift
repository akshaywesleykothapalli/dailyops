import Foundation

public protocol PlannerAgent: Sendable {
    func generatePlan(for goal: DailyOpsGoal, roleProfile: RoleProfile, availableTools: [any DailyOpsTool]) async throws -> DailyOpsPlan
}

public protocol VerifierAgent: Sendable {
    func verifyPlan(_ plan: DailyOpsPlan, roleProfile: RoleProfile) async throws -> VerificationResult
}

public protocol RecoveryAgent: Sendable {
    func recover(from error: Error, in plan: DailyOpsPlan, roleProfile: RoleProfile) async throws -> RecoveryAction
}

public struct VerificationResult: Sendable, Codable {
    public let approved: Bool
    public let issues: [String]
    public let suggestions: [String]

    public init(approved: Bool, issues: [String] = [], suggestions: [String] = []) {
        self.approved = approved
        self.issues = issues
        self.suggestions = suggestions
    }
}

public enum RecoveryAction: Sendable, Codable, Equatable {
    case retry(taskId: UUID)
    case skip(taskId: UUID)
    case modifyPlan(newTasks: [DailyOpsTask])
    case abort(reason: String)
}