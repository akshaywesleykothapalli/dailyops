import Foundation

public enum IntelligenceLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case L0 // deterministic
    case L1 // local classifier
    case L2 // local reasoning
    case L3 // advanced/cloud reasoning
    case L4 // multi-agent workflow

    public static func < (lhs: IntelligenceLevel, rhs: IntelligenceLevel) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .L0: return 0
        case .L1: return 1
        case .L2: return 2
        case .L3: return 3
        case .L4: return 4
        }
    }

    public var displayName: String {
        switch self {
        case .L0: return "Deterministic"
        case .L1: return "Local Classifier"
        case .L2: return "Local Reasoning"
        case .L3: return "Advanced Reasoning"
        case .L4: return "Multi-Agent Workflow"
        }
    }
}

public struct RoutingDecision: Sendable, Codable {
    public let level: IntelligenceLevel
    public let reason: String

    public init(level: IntelligenceLevel, reason: String) {
        self.level = level
        self.reason = reason
    }
}