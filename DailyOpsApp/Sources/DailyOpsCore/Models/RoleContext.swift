import Foundation

public struct RoleContext: Sendable, Codable, Equatable {
    public let role: EmployeeRole
    public let activeProject: String?
    public let currentFocus: String?
    public let preferences: [String: String]

    public init(
        role: EmployeeRole,
        activeProject: String? = nil,
        currentFocus: String? = nil,
        preferences: [String: String] = [:]
    ) {
        self.role = role
        self.activeProject = activeProject
        self.currentFocus = currentFocus
        self.preferences = preferences
    }
}