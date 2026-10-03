import Foundation

/// Parses system power/session voice commands into structured CommandPlans.
@MainActor
struct SystemPowerCommandParser: CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // Sleep
        if isSleepQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemSleep))
        }

        // Lock
        if isLockQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemLock))
        }

        // Logout
        if isLogoutQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemLogout))
        }

        // Restart
        if isRestartQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemRestart))
        }

        // Shutdown
        if isShutdownQuery(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .systemShutdown))
        }

        return nil
    }

    // MARK: - Sleep

    private func isSleepQuery(_ lower: String) -> Bool {
        let phrases = [
            "sleep",
            "put my mac to sleep",
            "put the mac to sleep",
            "put mac to sleep",
            "sleep my mac",
            "sleep the mac",
            "go to sleep",
            "put this mac to sleep"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Lock

    private func isLockQuery(_ lower: String) -> Bool {
        let phrases = [
            "lock my mac",
            "lock the mac",
            "lock mac",
            "lock my screen",
            "lock the screen",
            "lock screen",
            "lock this mac"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Logout

    private func isLogoutQuery(_ lower: String) -> Bool {
        let phrases = [
            "log me out",
            "log out",
            "log out of my mac",
            "log out of the mac",
            "sign me out",
            "sign out of my mac"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Restart

    private func isRestartQuery(_ lower: String) -> Bool {
        let phrases = [
            "restart my mac",
            "restart the mac",
            "restart mac",
            "restart my computer",
            "restart the computer",
            "reboot my mac",
            "reboot the mac"
        ]
        return phrases.contains(lower)
    }

    // MARK: - Shutdown

    private func isShutdownQuery(_ lower: String) -> Bool {
        let phrases = [
            "shut down my mac",
            "shut down the mac",
            "shut down mac",
            "turn off my mac",
            "turn off the mac",
            "power off my mac",
            "power off the mac"
        ]
        return phrases.contains(lower)
    }
}