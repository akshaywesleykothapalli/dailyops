import Foundation

public final class RoleEngine: @unchecked Sendable {
    public static let shared = RoleEngine()

    private let profiles: [EmployeeRole: RoleProfile]
    private var currentRole: EmployeeRole = .general
    private let queue = DispatchQueue(label: "com.dailyops.roleengine", attributes: .concurrent)

    private init() {
        self.profiles = Self.buildProfiles()
    }

    public var activeRole: EmployeeRole {
        queue.sync { currentRole }
    }

    public var activeProfile: RoleProfile {
        queue.sync { profiles[currentRole] ?? profiles[.general]! }
    }

    public func setRole(_ role: EmployeeRole) {
        queue.async(flags: .barrier) { self.currentRole = role }
    }

    private static func buildProfiles() -> [EmployeeRole: RoleProfile] {
        [
            .developer: RoleProfile(
                role: .developer,
                priorities: ["code quality", "delivery", "learning", "collaboration"],
                commonWorkCategories: ["repository work", "issues", "builds", "testing", "code review", "debugging", "documentation"],
                preferredToolCategories: [.development, .system, .productivity, .knowledge],
                contextualHints: [
                    "Focus on code changes, builds, and tests",
                    "Prioritize unblocking development flow",
                    "Check CI/CD status and review feedback"
                ]
            ),
            .manager: RoleProfile(
                role: .manager,
                priorities: ["team health", "delivery", "communication", "strategy"],
                commonWorkCategories: ["meetings", "team blockers", "approvals", "communication", "deadlines", "planning", "1:1s"],
                preferredToolCategories: [.communication, .productivity, .system, .knowledge],
                contextualHints: [
                    "Focus on team unblocking and decisions",
                    "Prioritize meetings and approvals",
                    "Track delivery risks and deadlines"
                ]
            ),
            .designer: RoleProfile(
                role: .designer,
                priorities: ["design quality", "user experience", "consistency", "delivery"],
                commonWorkCategories: ["design work", "feedback", "reviews", "assets", "deliverables", "prototyping", "user research"],
                preferredToolCategories: [.knowledge, .productivity, .communication, .system],
                contextualHints: [
                    "Focus on design iteration and feedback loops",
                    "Prioritize asset delivery and handoff",
                    "Track design system consistency"
                ]
            ),
            .general: RoleProfile(
                role: .general,
                priorities: ["productivity", "organization", "communication"],
                commonWorkCategories: ["tasks", "notes", "scheduling", "communication", "research"],
                preferredToolCategories: [.system, .productivity, .communication, .knowledge, .development],
                contextualHints: [
                    "Balanced approach across all work types",
                    "Adapt to current context"
                ]
            )
        ]
    }
}