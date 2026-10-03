import Foundation

public struct RuntimeResult: Sendable, Codable {
    public let goal: DailyOpsGoal
    public let plan: DailyOpsPlan?
    public let routingDecision: RoutingDecision
    public let permissionDecisions: [String: PermissionDecision]
    public let verification: VerificationResult?
    public let error: String?

    public init(
        goal: DailyOpsGoal,
        plan: DailyOpsPlan?,
        routingDecision: RoutingDecision,
        permissionDecisions: [String: PermissionDecision],
        verification: VerificationResult?,
        error: String?
    ) {
        self.goal = goal
        self.plan = plan
        self.routingDecision = routingDecision
        self.permissionDecisions = permissionDecisions
        self.verification = verification
        self.error = error
    }
}

public final class DailyOpsRuntime: Sendable {
    public static let shared = DailyOpsRuntime()

    private let roleEngine = RoleEngine.shared
    private let complexityRouter = ComplexityRouter.shared
    private let toolRegistry = ToolRegistry.shared
    private let permissionManager = PermissionManager.shared
    private let plannerAgent = DeterministicPlannerAgent.shared
    private let verifierAgent = DeterministicVerifierAgent.shared

    private init() {}

    public func submitGoal(_ text: String, source: GoalSource = .text) async -> RuntimeResult {
        let role = roleEngine.activeRole
        let roleProfile = roleEngine.activeProfile

        let normalizedIntent = normalizeIntent(text)
        let complexity = complexityRouter.route(text, role: role)

        var goal = DailyOpsGoal(
            originalText: text,
            normalizedIntent: normalizedIntent,
            complexity: mapIntelligenceToComplexity(complexity.level),
            source: source,
            roleContext: RoleContext(role: role)
        )

        goal.status = .planning

        do {
            let availableTools = toolRegistry.allTools()
            let plan = try await plannerAgent.generatePlan(for: goal, roleProfile: roleProfile, availableTools: availableTools)

            var goalWithPlan = goal
            goalWithPlan.planID = plan.id
            goalWithPlan.status = .executing

            let permissionDecisions = checkPermissions(for: plan)

            let verification = try await verifierAgent.verifyPlan(plan, roleProfile: roleProfile)

            if !verification.approved {
                goalWithPlan.status = .waitingForApproval
            }

            return RuntimeResult(
                goal: goalWithPlan,
                plan: plan,
                routingDecision: complexity,
                permissionDecisions: permissionDecisions,
                verification: verification,
                error: nil
            )
        } catch {
            goal.status = .failed
            return RuntimeResult(
                goal: goal,
                plan: nil,
                routingDecision: complexity,
                permissionDecisions: [:],
                verification: nil,
                error: error.localizedDescription
            )
        }
    }

    private func normalizeIntent(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
    }

    private func mapIntelligenceToComplexity(_ level: IntelligenceLevel) -> GoalComplexity {
        switch level {
        case .L0: return .trivial
        case .L1: return .simple
        case .L2: return .moderate
        case .L3: return .complex
        case .L4: return .multiAgent
        }
    }

    private func checkPermissions(for plan: DailyOpsPlan) -> [String: PermissionDecision] {
        var decisions: [String: PermissionDecision] = [:]

        for task in plan.tasks {
            if let requirement = task.toolRequirement {
                decisions[requirement.toolId] = permissionManager.decision(
                    for: requirement.riskLevel,
                    toolId: requirement.toolId
                )
            }
        }

        return decisions
    }
}