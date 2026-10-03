import Foundation

public enum PermissionDecision: String, Sendable, Codable, CaseIterable {
    case allowed
    case requiresConfirmation
    case denied
}

public final class PermissionManager: @unchecked Sendable {
    public static let shared = PermissionManager()

    private let queue = DispatchQueue(label: "com.dailyops.permissionmanager", attributes: .concurrent)
    private var customRules: [String: PermissionDecision] = [:]

    private init() {}

    public func decision(for riskLevel: ActionRiskLevel, toolId: String? = nil) -> PermissionDecision {
        queue.sync {
            if let toolId = toolId, let custom = customRules[toolId] {
                return custom
            }
            switch riskLevel {
            case .safe:
                return .allowed
            case .confirmationRequired:
                return .requiresConfirmation
            case .critical:
                return .denied
            }
        }
    }

    public func setCustomDecision(_ decision: PermissionDecision, forTool toolId: String) {
        queue.async(flags: .barrier) {
            self.customRules[toolId] = decision
        }
    }

    public func clearCustomDecision(forTool toolId: String) {
        queue.async(flags: .barrier) {
            self.customRules.removeValue(forKey: toolId)
        }
    }
}