import Foundation

public struct RoleProfile: Sendable, Codable {
    public let role: EmployeeRole
    public let priorities: [String]
    public let commonWorkCategories: [String]
    public let preferredToolCategories: [ToolCategory]
    public let contextualHints: [String]

    public init(
        role: EmployeeRole,
        priorities: [String],
        commonWorkCategories: [String],
        preferredToolCategories: [ToolCategory],
        contextualHints: [String]
    ) {
        self.role = role
        self.priorities = priorities
        self.commonWorkCategories = commonWorkCategories
        self.preferredToolCategories = preferredToolCategories
        self.contextualHints = contextualHints
    }
}