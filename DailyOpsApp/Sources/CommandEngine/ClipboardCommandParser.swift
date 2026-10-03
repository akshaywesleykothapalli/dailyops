import Foundation

/// Parses clipboard voice commands into structured CommandPlans.
@MainActor
struct ClipboardCommandParser: CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // "what is on my clipboard" / "what's on my clipboard" / "show my clipboard"
        // "read my clipboard" / "what's in my clipboard"
        let inspectPrefixes = [
            "what is on my clipboard",
            "what's on my clipboard",
            "show my clipboard",
            "read my clipboard",
            "what's in my clipboard",
            "what is in my clipboard",
            "show clipboard",
            "read clipboard",
            "what clipboard"
        ]

        for prefix in inspectPrefixes {
            if lower == prefix || lower.hasPrefix(prefix + " ") {
                return CommandPlan(intent: CommandIntent(identifier: .clipboardInspect, arguments: .clipboardInspect))
            }
        }

        return nil
    }
}