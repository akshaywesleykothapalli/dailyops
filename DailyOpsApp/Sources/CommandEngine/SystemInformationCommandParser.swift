import Foundation

/// Parses system information voice commands into structured CommandPlans.
@MainActor
struct SystemInformationCommandParser: CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // Battery
        if isBatteryQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemBattery))
        }

        // macOS Version
        if isMacOSVersionQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemMacOSVersion))
        }

        // Time
        if isTimeQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemTime))
        }

        // Date
        if isDateQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemDate))
        }

        return nil
    }

    // MARK: - Battery

    private func isBatteryQuery(_ lower: String) -> Bool {
        let batteryPhrases = [
            "what is my battery status",
            "what's my battery status",
            "battery status",
            "what is my battery",
            "what's my battery",
            "how much battery do i have",
            "how much battery is left",
            "how much battery is remaining",
            "show my battery",
            "check my battery"
        ]
        return batteryPhrases.contains(lower)
    }

    // MARK: - macOS Version

    private func isMacOSVersionQuery(_ lower: String) -> Bool {
        let versionPhrases = [
            "what macos version am i running",
            "what macos version am i running",
            "what version of macos am i running",
            "what version of macos is this",
            "what macos version is this",
            "which macos version do i have",
            "show my macos version",
            "check my macos version",
            "what mac os version am i running",
            "what mac os version am i running",
            "what version of mac os am i running",
            "what version of mac os is this",
            "what mac os version is this",
            "which mac os version do i have",
            "show my mac os version",
            "check my mac os version"
        ]
        return versionPhrases.contains(lower)
    }

    // MARK: - Time

    private func isTimeQuery(_ lower: String) -> Bool {
        let timePhrases = [
            "what time is it",
            "what's the time",
            "what is the current time",
            "current time",
            "tell me the time",
            "show me the time"
        ]
        return timePhrases.contains(lower)
    }

    // MARK: - Date

    private func isDateQuery(_ lower: String) -> Bool {
        let datePhrases = [
            "what date is it",
            "what's today's date",
            "what is today's date",
            "what is the date today",
            "today's date",
            "current date",
            "tell me today's date"
        ]
        return datePhrases.contains(lower)
    }
}