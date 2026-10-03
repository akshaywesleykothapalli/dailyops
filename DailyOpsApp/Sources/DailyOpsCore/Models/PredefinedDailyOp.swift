import Foundation

/// Functional category for predefined DailyOps starter workflows.
public enum DailyOpCategory: String, Sendable, Codable, CaseIterable {
    case planning
    case review
    case coordination
    case focus
}

/// A structured starter workflow template representing a common high-leverage agent goal.
/// Acts as a goal template, feeding directly into the real deterministic planning pipeline.
public struct PredefinedDailyOp: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let shortDescription: String
    public let suggestedGoalText: String
    public let iconName: String
    public let recommendedRoles: [EmployeeRole]
    public let category: DailyOpCategory

    public init(
        id: String,
        title: String,
        shortDescription: String,
        suggestedGoalText: String,
        iconName: String,
        recommendedRoles: [EmployeeRole],
        category: DailyOpCategory
    ) {
        self.id = id
        self.title = title
        self.shortDescription = shortDescription
        self.suggestedGoalText = suggestedGoalText
        self.iconName = iconName
        self.recommendedRoles = recommendedRoles
        self.category = category
    }

    public func isRecommended(for role: EmployeeRole) -> Bool {
        recommendedRoles.contains(role)
    }
}

/// Authoritative catalog of predefined DailyOps starter workflows.
public enum PredefinedDailyOpsCatalog {
    public static let all: [PredefinedDailyOp] = [
        PredefinedDailyOp(
            id: "start_my_workday",
            title: "Start My Workday",
            shortDescription: "Review priorities, blockers, schedule, and active work.",
            suggestedGoalText: "start my workday",
            iconName: "sun.max",
            recommendedRoles: [.developer, .manager, .designer, .general],
            category: .planning
        ),
        PredefinedDailyOp(
            id: "prepare_for_tomorrows_review",
            title: "Prepare for Tomorrow's Review",
            shortDescription: "Gather relevant progress, work items, blockers, and review context.",
            suggestedGoalText: "prepare me for tomorrow's review",
            iconName: "doc.text.magnifyingglass",
            recommendedRoles: [.developer, .manager, .designer],
            category: .review
        ),
        PredefinedDailyOp(
            id: "prepare_my_standup",
            title: "Prepare My Standup",
            shortDescription: "Summarize recent progress, current work, and blockers.",
            suggestedGoalText: "prepare my standup",
            iconName: "bubble.left.and.bubble.right",
            recommendedRoles: [.developer],
            category: .coordination
        ),
        PredefinedDailyOp(
            id: "prioritize_my_day",
            title: "Prioritize My Day",
            shortDescription: "Organize current responsibilities into a practical priority order.",
            suggestedGoalText: "help me prioritize my work today",
            iconName: "list.number",
            recommendedRoles: [.developer, .manager, .designer, .general],
            category: .planning
        ),
        PredefinedDailyOp(
            id: "prepare_for_my_next_meeting",
            title: "Prepare for My Next Meeting",
            shortDescription: "Collect relevant context, tasks, notes, and discussion points.",
            suggestedGoalText: "prepare me for my next meeting",
            iconName: "calendar.badge.clock",
            recommendedRoles: [.manager, .general, .developer],
            category: .coordination
        ),
        PredefinedDailyOp(
            id: "check_my_blockers",
            title: "Check My Blockers",
            shortDescription: "Review current work and surface issues preventing progress.",
            suggestedGoalText: "identify my current blockers",
            iconName: "exclamationmark.triangle",
            recommendedRoles: [.developer, .manager, .designer],
            category: .review
        ),
        PredefinedDailyOp(
            id: "end_my_workday",
            title: "End My Workday",
            shortDescription: "Review completed work, remaining tasks, blockers, and tomorrow's priorities.",
            suggestedGoalText: "help me wrap up my workday",
            iconName: "moon.stars",
            recommendedRoles: [.developer, .manager, .designer, .general],
            category: .planning
        ),
        PredefinedDailyOp(
            id: "review_my_active_work",
            title: "Review My Active Work",
            shortDescription: "Create a structured overview of current responsibilities and unfinished work.",
            suggestedGoalText: "review my active work",
            iconName: "tray.full",
            recommendedRoles: [.developer, .manager, .designer, .general],
            category: .review
        )
    ]

    public static func recommended(for role: EmployeeRole) -> [PredefinedDailyOp] {
        all.filter { $0.isRecommended(for: role) }
    }

    public static func other(for role: EmployeeRole) -> [PredefinedDailyOp] {
        all.filter { !$0.isRecommended(for: role) }
    }
}
