import AppKit
import Foundation
import os

private let wtLog = Logger(subsystem: AppBrand.bundleIdentifier, category: "writingTools")

/// Real-time system availability status of Apple AppKit Writing Tools.
enum AppleWritingToolsStatus: Equatable {
    case available
    case unavailableOnMac
    case requiresMacOSUpdate

    var label: String {
        switch self {
        case .available: "Available"
        case .unavailableOnMac: "Unavailable on this Mac"
        case .requiresMacOSUpdate: "Requires macOS update"
        }
    }

    var detailMessage: String {
        switch self {
        case .available:
            "Apple on-device Writing Tools are supported."
        case .unavailableOnMac:
            "Writing Tools are unavailable on this hardware."
        case .requiresMacOSUpdate:
            "Writing Tools require macOS Sequoia 15.0 or later."
        }
    }

    var systemImage: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .unavailableOnMac: "slash.circle"
        case .requiresMacOSUpdate: "arrow.up.circle"
        }
    }

    var isReady: Bool {
        self == .available
    }

    /// Evaluates current macOS system and hardware capability using Apple AppKit APIs.
    @MainActor
    static var current: AppleWritingToolsStatus {
        guard #available(macOS 26.0, *) else {
            return .requiresMacOSUpdate
        }

        return NSWritingToolsCoordinator.isWritingToolsAvailable ? .available : .unavailableOnMac
    }
}

/// Official Writing Tools action modes.
enum AppleWritingToolsAction: String, CaseIterable, Identifiable {
    case proofread
    case rewrite
    case formal
    case concise
    case summarize

    var id: String { rawValue }

    var label: String {
        switch self {
        case .proofread: "Proofread"
        case .rewrite: "Rewrite"
        case .formal: "Professional / Formal"
        case .concise: "Concise"
        case .summarize: "Summarize"
        }
    }

    var description: String {
        switch self {
        case .proofread: "Correct spelling, grammar, and typography on-device."
        case .rewrite: "Rephrase for improved clarity and natural flow."
        case .formal: "Elevate tone into structured, professional prose."
        case .concise: "Remove redundancy and deliver the core message cleanly."
        case .summarize: "Generate a crisp, high-level summary of the key points."
        }
    }
}

/// Coordinates on-device text transformations using deterministic formatting.
struct AppleWritingToolsService {
    @MainActor
    static var status: AppleWritingToolsStatus {
        AppleWritingToolsStatus.current
    }

    @MainActor
    static var isAvailable: Bool {
        status.isReady
    }

    /// Transforms input text using local deterministic rules.
    static func transform(
        _ text: String,
        action: AppleWritingToolsAction = .proofread,
        vocabulary: [String] = []
    ) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        return CleanupService.cleanDeterministically(trimmed, vocabulary: vocabulary, formal: action == .formal)
    }
}
