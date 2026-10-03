import Foundation

public struct RoleWorkflowStep: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case application, project, url, gitStatus }
    public var id = UUID()
    public var kind: Kind
    public var value: String
    public var application: String = ""
    public var enabled: Bool = true
    public var title: String { "\(kind.rawValue): \(value.isEmpty ? "Not configured" : value)" }
    public var toolID: String {
        switch kind { case .application: "open_application"; case .project: "open_path"; case .url: "open_url"; case .gitStatus: "git_status" }
    }
    public var parameters: [String: String] {
        switch kind {
        case .application: ["application": value]
        case .project: ["path": value, "application": application]
        case .url: ["url": value]
        case .gitStatus: ["path": value]
        }
    }
}
public struct RoleWorkflow: Codable, Sendable, Equatable { public var steps: [RoleWorkflowStep] }
public struct RoleWorkspaceProfile: Codable, Sendable, Equatable, Identifiable {
    public var role: EmployeeRole
    public var workflowName: String
    public var voicePhrases: [String]
    public var defaultProjectPath: String
    public var projectEditor: String
    public var workflow: RoleWorkflow
    public var id: String { role.rawValue }
    public static func defaults(_ role: EmployeeRole) -> Self {
        let apps: [String]
        switch role {
        case .developer: apps = ["Visual Studio Code", "Terminal", "ChatGPT", "Codex", "OpenCode", "Safari"]
        case .manager: apps = ["Calendar", "Mail", "Microsoft Teams", "Slack", "Notes", "Safari"]
        case .designer: apps = ["Figma", "Notes", "Safari"]
        case .general: apps = ["Safari", "Notes", "Calendar"]
        }
        return Self(role: role, workflowName: "\(role.displayName) setup", voicePhrases: [], defaultProjectPath: "", projectEditor: role == .developer ? "Visual Studio Code" : "", workflow: RoleWorkflow(steps: apps.map { .init(kind: .application, value: $0) }))
    }
    public var resolvedWorkflow: RoleWorkflow {
        var result = workflow
        if !defaultProjectPath.isEmpty { result.steps.append(.init(kind: .project, value: defaultProjectPath, application: projectEditor)) }
        return result
    }
}
/// Versioned Codable profiles in DailyOps-owned preferences; no arbitrary file writes.
public final class RoleWorkspaceStore: @unchecked Sendable {
    public static let shared = RoleWorkspaceStore()
    private let defaults: UserDefaults
    private let lock = NSLock()
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> [RoleWorkspaceProfile] {
        lock.lock(); defer { lock.unlock() }
        let saved = defaults.data(forKey: "DailyOps.roleWorkspaces.v1").flatMap { try? JSONDecoder().decode([RoleWorkspaceProfile].self, from: $0) } ?? []
        return EmployeeRole.allCases.map { role in saved.first { $0.role == role } ?? .defaults(role) }
    }
    public func save(_ profiles: [RoleWorkspaceProfile]) throws {
        let data = try JSONEncoder().encode(profiles)
        lock.lock(); defer { lock.unlock() }
        defaults.set(data, forKey: "DailyOps.roleWorkspaces.v1")
    }
}
