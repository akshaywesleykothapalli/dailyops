import SwiftUI

enum AppBrand {
    static let displayName = "DailyOps"
    static let compactName = "DailyOps"
    static let bundleIdentifier = "com.akshaywesley.DailyOps"
    static let applicationSupportDirectoryName = "DailyOps"
    static let minimumSystemVersion = "macOS 14"
}

extension Color {
    static let wesleyMint = Color(red: 0.40, green: 0.94, blue: 0.76)
    static let wesleyBlue = Color(red: 0.30, green: 0.48, blue: 0.98)
    static let wesleyCoral = Color(red: 1.00, green: 0.35, blue: 0.24)
    static let wesleyInk = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let wesleyCharcoal = Color(red: 0.15, green: 0.16, blue: 0.18)
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// `Codable` lets the mode travel inside command arguments. The raw values are
// unchanged, so anything already persisted keeps decoding.
enum WritingMode: String, CaseIterable, Identifiable, Codable {
    case standard = "Standard"
    case formal = "Formal"
    
    var id: String { rawValue }
    var label: String { rawValue }
    
    var description: String {
        switch self {
        case .standard:
            return "Natural dictation with automatic punctuation and capitalization."
        case .formal:
            return "Polished, professional rewrite preserving meaning with enhanced clarity."
        }
    }
}
