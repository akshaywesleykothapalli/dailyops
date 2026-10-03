import Foundation

public enum EmployeeRole: String, Sendable, Codable, CaseIterable, Identifiable {
    case developer
    case manager
    case designer
    case general

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .manager: return "Manager"
        case .designer: return "Designer"
        case .general: return "General"
        }
    }
}