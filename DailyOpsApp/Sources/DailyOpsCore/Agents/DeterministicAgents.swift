import Foundation

public final class DeterministicPlannerAgent: PlannerAgent {
    public static let shared = DeterministicPlannerAgent()

    private init() {}

    public func generatePlan(for goal: DailyOpsGoal, roleProfile: RoleProfile, availableTools: [any DailyOpsTool]) async throws -> DailyOpsPlan {
        let tasks = try buildTasks(for: goal, roleProfile: roleProfile, availableTools: availableTools)
        return DailyOpsPlan(goalID: goal.id, tasks: tasks)
    }

    private func buildTasks(for goal: DailyOpsGoal, roleProfile: RoleProfile, availableTools: [any DailyOpsTool]) throws -> [DailyOpsTask] {
        let normalizedIntent = goal.normalizedIntent.lowercased()

        if normalizedIntent.contains("start my workday") || normalizedIntent.contains("begin workday") {
            return buildWorkdayStartTasks(role: roleProfile.role)
        }

        if normalizedIntent.contains("prepare me for") || normalizedIntent.contains("prepare for") {
            if normalizedIntent.contains("tomorrow") || normalizedIntent.contains("review") {
                return buildReviewPrepTasks(role: roleProfile.role)
            }
        }

        // Open application command (e.g. "open safari")
        if normalizedIntent.contains("open safari") || normalizedIntent == "open safari" || normalizedIntent == "safari" {
            return [DailyOpsTask(
                title: "Opening Safari",
                description: "Launch Safari browser",
                order: 0,
                toolRequirement: ToolRequirement(
                    toolId: "open_application",
                    riskLevel: .safe,
                    parameters: ["application": "Safari"]
                )
            )]
        } else if normalizedIntent.starts(with: "open ") || normalizedIntent.starts(with: "launch ") {
            let appName = normalizedIntent
                .replacingOccurrences(of: "open ", with: "")
                .replacingOccurrences(of: "launch ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let formattedAppName = appName.capitalized
            return [DailyOpsTask(
                title: "Opening \(formattedAppName)",
                description: "Launch \(formattedAppName) application",
                order: 0,
                toolRequirement: ToolRequirement(
                    toolId: "open_application",
                    riskLevel: .safe,
                    parameters: ["application": formattedAppName]
                )
            )]
        }

        // Create local note command (e.g. "create a local note")
        if normalizedIntent.contains("create") && (normalizedIntent.contains("note") || normalizedIntent.contains("local note")) {
            return [DailyOpsTask(
                title: "Create local note",
                description: "Create a persistent local note in DailyOps storage",
                order: 0,
                toolRequirement: ToolRequirement(
                    toolId: "create_local_note",
                    riskLevel: .confirmationRequired,
                    parameters: [
                        "title": "DailyOps Note",
                        "content": "DailyOps agent note created at \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))."
                    ]
                )
            )]
        }

        // Default: single task for simple goals
        return [DailyOpsTask(
            title: "Execute: \(goal.originalText)",
            description: goal.normalizedIntent,
            order: 0,
            toolRequirement: nil
        )]
    }

    private func buildWorkdayStartTasks(role: EmployeeRole) -> [DailyOpsTask] {
        switch role {
        case .developer:
            return [
                DailyOpsTask(title: "Review today's schedule", description: "Check calendar for meetings and commitments", order: 0, toolRequirement: ToolRequirement(toolId: "calendar_events", riskLevel: .safe)),
                DailyOpsTask(title: "Check active development tasks", description: "Review assigned issues and pull requests", order: 1, toolRequirement: ToolRequirement(toolId: "github_issues", riskLevel: .safe)),
                DailyOpsTask(title: "Inspect current project status", description: "Check build status and CI/CD pipelines", order: 2, toolRequirement: ToolRequirement(toolId: "system_status", riskLevel: .safe)),
                DailyOpsTask(title: "Identify blockers", description: "Find dependencies and blocking issues", order: 3),
                DailyOpsTask(title: "Prioritize work", description: "Order tasks by impact and urgency", order: 4),
                DailyOpsTask(title: "Prepare work summary", description: "Create brief plan for the day", order: 5)
            ]
        case .manager:
            return [
                DailyOpsTask(title: "Review today's meetings", description: "Check calendar and prepare agendas", order: 0),
                DailyOpsTask(title: "Check team blockers", description: "Review standup notes and escalations", order: 1),
                DailyOpsTask(title: "Review pending approvals", description: "Check PRs, budgets, and decisions needed", order: 2),
                DailyOpsTask(title: "Check deadlines", description: "Review project milestones and delivery dates", order: 3),
                DailyOpsTask(title: "Prepare communication", description: "Draft updates and announcements", order: 4),
                DailyOpsTask(title: "Set daily priorities", description: "Define top 3 outcomes for the day", order: 5)
            ]
        case .designer:
            return [
                DailyOpsTask(title: "Review design tasks", description: "Check assigned designs and feedback", order: 0),
                DailyOpsTask(title: "Check design reviews", description: "Review scheduled critiques and presentations", order: 1),
                DailyOpsTask(title: "Review asset pipeline", description: "Check export status and handoff readiness", order: 2),
                DailyOpsTask(title: "Check user feedback", description: "Review research insights and testing results", order: 3),
                DailyOpsTask(title: "Prioritize deliverables", description: "Order by deadline and stakeholder impact", order: 4),
                DailyOpsTask(title: "Prepare creative brief", description: "Outline focus areas for the day", order: 5)
            ]
        case .general:
            return [
                DailyOpsTask(title: "Review schedule", description: "Check calendar and commitments", order: 0),
                DailyOpsTask(title: "Check pending tasks", description: "Review to-do list and priorities", order: 1),
                DailyOpsTask(title: "Check communications", description: "Review messages and notifications", order: 2),
                DailyOpsTask(title: "Set daily focus", description: "Define 2-3 key outcomes", order: 3)
            ]
        }
    }

    private func buildReviewPrepTasks(role: EmployeeRole) -> [DailyOpsTask] {
        switch role {
        case .developer:
            return [
                DailyOpsTask(title: "Gather recent commits", description: "Collect changes since last review", order: 0),
                DailyOpsTask(title: "Run test suite", description: "Ensure all tests pass", order: 1),
                DailyOpsTask(title: "Check CI status", description: "Verify build and deployment health", order: 2),
                DailyOpsTask(title: "Prepare demo script", description: "Outline features to demonstrate", order: 3),
                DailyOpsTask(title: "Document known issues", description: "List blockers and workarounds", order: 4)
            ]
        case .manager:
            return [
                DailyOpsTask(title: "Review team metrics", description: "Check velocity, quality, and health indicators", order: 0),
                DailyOpsTask(title: "Gather project status", description: "Collect updates from leads", order: 1),
                DailyOpsTask(title: "Prepare decision log", description: "Document pending and recent decisions", order: 2),
                DailyOpsTask(title: "Review resource allocation", description: "Check capacity and assignments", order: 3),
                DailyOpsTask(title: "Draft talking points", description: "Prepare key discussion topics", order: 4)
            ]
        case .designer:
            return [
                DailyOpsTask(title: "Compile design iterations", description: "Gather version history and feedback", order: 0),
                DailyOpsTask(title: "Prepare prototype links", description: "Ensure all prototypes are accessible", order: 1),
                DailyOpsTask(title: "Gather user insights", description: "Collect research and testing data", order: 2),
                DailyOpsTask(title: "Check design system compliance", description: "Verify component usage", order: 3),
                DailyOpsTask(title: "Prepare rationale", description: "Document design decisions", order: 4)
            ]
        case .general:
            return [
                DailyOpsTask(title: "Gather relevant materials", description: "Collect documents and notes", order: 0),
                DailyOpsTask(title: "Outline key points", description: "Structure review topics", order: 1),
                DailyOpsTask(title: "Prepare questions", description: "List items needing clarification", order: 2)
            ]
        }
    }
}

public final class DeterministicVerifierAgent: VerifierAgent {
    public static let shared = DeterministicVerifierAgent()

    private init() {}

    public func verifyPlan(_ plan: DailyOpsPlan, roleProfile: RoleProfile) async throws -> VerificationResult {
        var issues: [String] = []
        var suggestions: [String] = []

        // Check for critical tools without approval path
        let criticalTasks = plan.tasks.filter { $0.toolRequirement?.riskLevel == .critical }
        if !criticalTasks.isEmpty {
            issues.append("Plan contains \(criticalTasks.count) critical-risk task(s) requiring explicit approval")
            suggestions.append("Add confirmation steps before critical actions")
        }

        // Check for logical ordering
        let orderedTasks = plan.tasks.sorted { $0.order < $1.order }
        let taskIndices = Dictionary(uniqueKeysWithValues: orderedTasks.enumerated().map { ($0.element.id, $0.offset) })
        for (index, task) in orderedTasks.enumerated() {
            for dep in task.dependencies {
                if let depIndex = taskIndices[dep], depIndex >= index {
                    issues.append("Task '\(task.title)' depends on future task")
                }
            }
        }

        // Role-specific checks
        if roleProfile.role == .developer {
            let hasTesting = plan.tasks.contains { $0.title.lowercased().contains("test") }
            if !hasTesting && plan.tasks.count > 2 {
                suggestions.append("Consider adding test verification step")
            }
        }

        return VerificationResult(
            approved: issues.isEmpty,
            issues: issues,
            suggestions: suggestions
        )
    }
}

public final class DeterministicRecoveryAgent: RecoveryAgent {
    public static let shared = DeterministicRecoveryAgent()

    private init() {}

    public func recover(from error: Error, in plan: DailyOpsPlan, roleProfile: RoleProfile) async throws -> RecoveryAction {
        let failedTasks = plan.tasks.filter { $0.status == .failed }

        if failedTasks.count == 1, let failed = failedTasks.first {
            if failed.toolRequirement?.riskLevel == .confirmationRequired {
                return .retry(taskId: failed.id)
            }
        }

        if failedTasks.count > 2 {
            return .abort(reason: "Multiple task failures - manual intervention required")
        }

        return .skip(taskId: failedTasks.first?.id ?? UUID())
    }
}