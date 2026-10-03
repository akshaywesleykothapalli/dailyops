import Foundation

public enum ToolCategory: String, Sendable, Codable, CaseIterable, Identifiable {
    case system
    case development
    case communication
    case productivity
    case knowledge

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .development: return "Development"
        case .communication: return "Communication"
        case .productivity: return "Productivity"
        case .knowledge: return "Knowledge"
        }
    }
}