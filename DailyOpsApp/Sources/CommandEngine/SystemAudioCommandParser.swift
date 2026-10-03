import Foundation

/// Parses system audio/volume voice commands into structured CommandPlans.
@MainActor
struct SystemAudioCommandParser: CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // Volume Up
        if isVolumeUpQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemVolumeUp))
        }

        // Volume Down
        if isVolumeDownQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemVolumeDown))
        }

        // Mute
        if isMuteQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemVolumeMute))
        }

        // Unmute
        if isUnmuteQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemVolumeUnmute))
        }

        // Current Volume (Get)
        if isVolumeGetQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemVolumeGet))
        }

        // Set Volume (must be checked last to avoid catching "volume up/down" as set)
        if let percentage = extractVolumePercentage(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemVolumeSet, arguments: .systemVolumeSet(percentage)))
        }

        return nil
    }

    // MARK: - Volume Up

    private func isVolumeUpQuery(_ lower: String) -> Bool {
        let phrases = [
            "volume up",
            "turn the volume up",
            "turn up the volume",
            "increase the volume",
            "make it louder",
            "louder"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Volume Down

    private func isVolumeDownQuery(_ lower: String) -> Bool {
        let phrases = [
            "volume down",
            "turn the volume down",
            "turn down the volume",
            "decrease the volume",
            "make it quieter",
            "quieter"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Mute

    private func isMuteQuery(_ lower: String) -> Bool {
        let phrases = [
            "mute",
            "mute the volume",
            "mute audio",
            "mute sound",
            "mute my mac"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Unmute

    private func isUnmuteQuery(_ lower: String) -> Bool {
        let phrases = [
            "unmute",
            "unmute the volume",
            "unmute audio",
            "unmute sound",
            "unmute my mac"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Current Volume (Get)

    private func isVolumeGetQuery(_ lower: String) -> Bool {
        let phrases = [
            "what is my volume",
            "what's my volume",
            "what is the volume",
            "show volume",
            "check volume",
            "how loud is it"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Set Volume

    private func extractVolumePercentage(_ lower: String) -> Int? {
        // "set volume to 50", "set the volume to 50", "volume 50", "set volume to 75 percent", "set the volume to 25%"
        let patterns = [
            "set volume to ",
            "set the volume to ",
            "volume "
        ]

        for pattern in patterns {
            if lower.hasPrefix(pattern) {
                let remainder = String(lower.dropFirst(pattern.count))
                // Remove "percent" or "%" suffix
                let cleaned = remainder
                    .replacingOccurrences(of: "percent", with: "")
                    .replacingOccurrences(of: "%", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Int(cleaned), value >= 0, value <= 100 {
                    return value
                }
            }
        }
        return nil
    }
}