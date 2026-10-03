import Foundation

/// Explicit activation helper for DailyOps agent workflows.
///
/// Safety guarantee: Normal dictation is NEVER routed through the agent runtime.
/// Only explicit goal phrases submitted through Agent Mode / Command Mode are recognized.
public enum AgentActivation {

    /// Matches explicit phrases intended to trigger DailyOps agent workflows.
    /// Returns the normalized goal text if matched, or nil to let normal dictation proceed.
    public static func matchGoal(_ transcript: String) -> String? {
        let cleaned = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!;:\"'"))
        guard !cleaned.isEmpty else { return nil }

        let normalized = cleaned.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Workday kickoff triggers
        if normalized == "start my workday" ||
           normalized == "begin workday" ||
           normalized == "start workday" ||
           normalized == "begin my workday" {
            return "Start my workday"
        }

        // Review prep triggers
        if normalized == "prepare me for tomorrow's review" ||
           normalized == "prepare me for tomorrows review" ||
           normalized == "prepare for tomorrow's review" ||
           normalized == "prepare for tomorrows review" ||
           normalized == "prepare me for tomorrow review" ||
           normalized == "prepare me for review" ||
           normalized == "prepare for review" {
            return "Prepare me for tomorrow's review"
        }

        // Generic non-agent text must NEVER match
        return nil
    }
}
