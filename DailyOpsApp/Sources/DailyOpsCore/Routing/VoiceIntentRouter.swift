import Foundation

public enum VoiceIntentKind: String, Codable, Sendable {
    case dictation, directCommand, roleWorkflow, localAgentTask, dailyOpsGoal
}
public struct VoiceIntentDecision: Sendable, Equatable {
    public let kind: VoiceIntentKind
    public let action: String
    public let role: EmployeeRole
    public let steps: [RoleWorkflowStep]
}
public struct VoiceIntentRouter: Sendable {
    public init() {}
    public static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    public func route(_ text: String, role: EmployeeRole, profiles: [RoleWorkspaceProfile], enabled: Bool = true) -> VoiceIntentDecision {
        let value = Self.normalize(text)
        func decision(_ kind: VoiceIntentKind, _ action: String, _ steps: [RoleWorkflowStep] = [], _ chosenRole: EmployeeRole? = nil) -> VoiceIntentDecision {
            VoiceIntentDecision(kind: kind, action: action, role: chosenRole ?? role, steps: steps)
        }
        guard enabled else { return decision(.dictation, text) }
        let profile = profiles.first { $0.role == role } ?? .defaults(role)
        if ["open the dailyops project and check git status", "open my dailyops project and check git status", "check git status for my dailyops project"].contains(value) {
            var steps: [RoleWorkflowStep] = []
            if value.hasPrefix("open") { steps.append(.init(kind: .project, value: profile.defaultProjectPath, application: profile.projectEditor)) }
            steps.append(.init(kind: .gitStatus, value: profile.defaultProjectPath))
            return decision(.localAgentTask, text, steps)
        }
        for candidate in profiles {
            let phrases = candidate.voicePhrases + ["open my \(candidate.role.rawValue) setup", "start my \(candidate.role.rawValue) setup", "open my \(candidate.workflowName)", "start my \(candidate.workflowName)"]
            if phrases.map(Self.normalize).contains(value) {
                return decision(.roleWorkflow, candidate.workflowName, candidate.resolvedWorkflow.steps.filter(\.enabled), candidate.role)
            }
        }
        if ["open my work setup", "start my work setup"].contains(value) {
            return decision(.roleWorkflow, profile.workflowName, profile.resolvedWorkflow.steps.filter(\.enabled))
        }
        if ["open my project", "open my dailyops project", "open the dailyops project"].contains(value) {
            return decision(.directCommand, "Open project", [.init(kind: .project, value: profile.defaultProjectPath, application: profile.projectEditor)])
        }
        let aliases = ["vs code": "Visual Studio Code", "visual studio code": "Visual Studio Code", "terminal": "Terminal", "xcode": "Xcode", "safari": "Safari", "chatgpt": "ChatGPT", "codex": "Codex", "opencode": "OpenCode"]
        if value.hasPrefix("open ") {
            let name = String(value.dropFirst(5))
            let configured = profiles.flatMap { $0.workflow.steps }.filter { $0.kind == .application }.first { Self.normalize($0.value) == name }?.value
            if let app = aliases[name] ?? configured {
                return decision(.directCommand, "Open \(app)", [.init(kind: .application, value: app)])
            }
        }
        if value == "prepare my standup" { return decision(.dailyOpsGoal, "Prepare my standup") }
        if let goal = AgentActivation.matchGoal(text) { return decision(.dailyOpsGoal, goal) }
        return decision(.dictation, text)
    }
}

public struct LocalAgentTaskPlanner: Sendable {
    public init() {}
    public func plan(_ decision: VoiceIntentDecision, goalID: UUID, applicationAvailability: [String: Bool] = [:]) -> DailyOpsPlan {
        let tasks = decision.steps.filter(\.enabled).enumerated().map { index, step in
            let unavailable = decision.kind == .roleWorkflow && step.kind == .application && applicationAvailability[step.value] == false
            return DailyOpsTask(title: step.title, description: step.value, order: index,
                status: unavailable ? .skipped : .pending,
                toolRequirement: ToolRequirement(toolId: step.toolID, riskLevel: .safe, parameters: step.parameters),
                error: unavailable ? "Application unavailable: \(step.value); skipped" : nil)
        }
        return DailyOpsPlan(goalID: goalID, tasks: tasks)
    }
}
