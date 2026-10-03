import Foundation

public final class ComplexityRouter: Sendable {
    public static let shared = ComplexityRouter()

    private let l0Patterns: [String] = [
        "open ",
        "launch ",
        "close ",
        "quit ",
        "copy ",
        "paste ",
        "show ",
        "hide ",
        "mute",
        "unmute",
        "volume",
        "brightness",
        "screenshot",
        "lock screen",
        "sleep",
        "restart",
        "shutdown"
    ]

    private let l1Patterns: [String] = [
        "rewrite",
        "rephrase",
        "summarize",
        "format",
        "clean up",
        "fix grammar",
        "translate"
    ]

    private let l2Patterns: [String] = [
        "analyze",
        "compare",
        "find ",
        "search ",
        "lookup",
        "calculate",
        "convert",
        "generate"
    ]

    private let l4Patterns: [String] = [
        "start my workday",
        "prepare me for",
        "plan my",
        "organize my",
        "review my",
        "catch me up",
        "daily standup",
        "weekly review",
        "end of day",
        "tomorrow's",
        "next week"
    ]

    private init() {}

    public func route(_ text: String, role: EmployeeRole) -> RoutingDecision {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if matchesAny(normalized, patterns: l4Patterns) {
            return RoutingDecision(
                level: .L4,
                reason: "Goal requires multi-step contextual planning with role awareness"
            )
        }

        if matchesAny(normalized, patterns: l2Patterns) {
            return RoutingDecision(
                level: .L2,
                reason: "Goal requires local reasoning or information synthesis"
            )
        }

        if matchesAny(normalized, patterns: l1Patterns) {
            return RoutingDecision(
                level: .L1,
                reason: "Goal requires local text transformation or classification"
            )
        }

        if matchesAny(normalized, patterns: l0Patterns) {
            return RoutingDecision(
                level: .L0,
                reason: "Simple deterministic command"
            )
        }

        // Default fallback based on text length and complexity hints
        if normalized.split(separator: " ").count > 8 {
            return RoutingDecision(
                level: .L2,
                reason: "Complex multi-part request"
            )
        }

        return RoutingDecision(
            level: .L1,
            reason: "Default classification for unrecognized patterns"
        )
    }

    private func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            if pattern.hasSuffix(" ") {
                return text.hasPrefix(pattern.trimmingCharacters(in: .whitespaces)) || text.contains(pattern)
            }
            return text.contains(pattern)
        }
    }
}