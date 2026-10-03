import AppKit
import Foundation

/// Indexes installed applications and matches spoken names against them.
/// The command engine reaches this through `SystemApplicationResolver`; the
/// resolution rules below are unchanged.
@MainActor
final class ApplicationDiscovery {
    static let shared = ApplicationDiscovery()

    private var cachedApps: [String: URL] = [:]
    private var lastScanTime: Date?

    private let searchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]

    private let commonAliases: [String: String] = [
        "chrome": "google chrome",
        "calc": "calculator",
        "code": "visual studio code",
        "vscode": "visual studio code",
        "settings": "system settings",
        "preferences": "system settings",
        "sys pref": "system settings",
        "system preferences": "system settings",
        "terminal": "terminal",
        "sublime": "sublime text",
        "music": "music",
        "spotify": "spotify",
        "mail": "mail",
        "slack": "slack",
        "word": "microsoft word",
        "excel": "microsoft excel",
        "powerpoint": "microsoft powerpoint",
        "teams": "microsoft teams",
        "outlook": "microsoft outlook",
        "figma": "figma",
        "xcode": "xcode"
    ]

    func findApplication(named query: String) -> (name: String, url: URL)? {
        refreshIndexIfNeeded()
        let normalizedQuery = CommandModeService.normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }

        // 1. Direct match in discovered applications
        if let url = cachedApps[normalizedQuery] {
            return (normalizedQuery, url)
        }

        // 2. Alias resolution
        if let alias = commonAliases[normalizedQuery], let url = cachedApps[alias] {
            return (alias, url)
        }

        // Multi-step sequence queries containing conjunctions must not match prefixes or substrings
        if normalizedQuery.contains(" and ") ||
           normalizedQuery.contains(" then ") ||
           normalizedQuery.contains(" after that ") ||
           normalizedQuery.contains(",") {
            return nil
        }

        // Common particles and short words must not trigger prefix or substring matching against random apps
        let blockedParticles: Set<String> = [
            "a", "an", "the", "in", "on", "at", "to", "for", "of", "with", "by", "from",
            "up", "about", "into", "over", "after", "me", "my", "we", "us", "he", "him",
            "she", "her", "it", "its", "they", "them", "this", "that", "these", "those",
            "and", "or", "but", "if", "then", "so", "no", "not", "do", "go", "is", "be", "as"
        ]
        let allowFuzzy = normalizedQuery.count >= 3 && !blockedParticles.contains(normalizedQuery)
        guard allowFuzzy else { return nil }

        // 3. Deterministic prefix match (prioritize shortest matching application name, then alphabetical)
        let prefixMatches = cachedApps.filter { key, _ in key.hasPrefix(normalizedQuery) }
        if let best = prefixMatches.min(by: { a, b in
            if a.key.count != b.key.count { return a.key.count < b.key.count }
            return a.key < b.key
        }) {
            return (best.key, best.value)
        }

        // 4. Deterministic word-boundary contains match (requires query length >= 4 and whole-word boundary)
        if normalizedQuery.count >= 4 {
            let containsMatches = cachedApps.filter { key, _ in
                key.hasPrefix(normalizedQuery + " ") ||
                key.contains(" " + normalizedQuery + " ") ||
                key.hasSuffix(" " + normalizedQuery)
            }
            if let best = containsMatches.min(by: { a, b in
                if a.key.count != b.key.count { return a.key.count < b.key.count }
                return a.key < b.key
            }) {
                return (best.key, best.value)
            }
        }

        // 5. NSWorkspace fallback by bundle ID or name
        let bundleCandidates = [
            "com.apple.\(normalizedQuery)",
            "com.apple.\(normalizedQuery.capitalized)",
            "com.google.\(normalizedQuery)",
            "com.microsoft.\(normalizedQuery)"
        ]
        for candidate in bundleCandidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) {
                return (normalizedQuery, url)
            }
        }

        return nil
    }

    func findRunningApplication(named query: String) -> NSRunningApplication? {
        let normalizedQuery = CommandModeService.normalized(query)
        guard !normalizedQuery.isEmpty else { return nil }

        let running = NSWorkspace.shared.runningApplications
        // 1. Exact match on localizedName
        if let app = running.first(where: { app in
            guard let name = app.localizedName else { return false }
            return CommandModeService.normalized(name) == normalizedQuery
        }) {
            return app
        }

        // 2. Alias match
        if let alias = commonAliases[normalizedQuery], let app = running.first(where: { app in
            guard let name = app.localizedName else { return false }
            return CommandModeService.normalized(name) == alias
        }) {
            return app
        }

        // 3. Prefix or word-boundary contains for non-short words
        let blockedParticles: Set<String> = [
            "a", "an", "the", "in", "on", "at", "to", "for", "of", "with", "by", "from",
            "up", "about", "into", "over", "after", "me", "my", "we", "us", "he", "him",
            "she", "her", "it", "its", "they", "them", "this", "that", "these", "those",
            "and", "or", "but", "if", "then", "so", "no", "not", "do", "go", "is", "be", "as"
        ]
        let allowFuzzy = normalizedQuery.count >= 3 && !blockedParticles.contains(normalizedQuery)
        guard allowFuzzy else { return nil }

        let runningMatches = running.filter { app in
            guard let name = app.localizedName else { return false }
            let norm = CommandModeService.normalized(name)
            if norm.hasPrefix(normalizedQuery) { return true }
            if normalizedQuery.count >= 4 {
                return norm.hasPrefix(normalizedQuery + " ") ||
                       norm.contains(" " + normalizedQuery + " ") ||
                       norm.hasSuffix(" " + normalizedQuery)
            }
            return false
        }
        return runningMatches.min(by: { a, b in
            let aName = a.localizedName ?? ""
            let bName = b.localizedName ?? ""
            if aName.count != bName.count { return aName.count < bName.count }
            return aName < bName
        })
    }

    private func refreshIndexIfNeeded() {
        if let last = lastScanTime, Date().timeIntervalSince(last) < 300, !cachedApps.isEmpty {
            return
        }
        scanApplications()
    }

    func scanApplications() {
        var newIndex: [String: URL] = [:]
        let fm = FileManager.default

        for dir in searchDirectories {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    let baseName = url.deletingPathExtension().lastPathComponent
                    let normalizedBase = CommandModeService.normalized(baseName)
                    if !normalizedBase.isEmpty {
                        newIndex[normalizedBase] = url
                    }

                    // Check bundle display name
                    if let bundle = Bundle(url: url) {
                        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                            let normDisplay = CommandModeService.normalized(displayName)
                            if !normDisplay.isEmpty {
                                newIndex[normDisplay] = url
                            }
                        }
                        if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                            let normBundle = CommandModeService.normalized(bundleName)
                            if !normBundle.isEmpty {
                                newIndex[normBundle] = url
                            }
                        }
                    }
                }
            }
        }

        self.cachedApps = newIndex
        self.lastScanTime = Date()
    }
}

/// The dictation pipeline's entry point into the command engine. This stays a
/// thin adapter: it reads the user's Command Mode preference, builds the
/// context, and returns the engine's feedback. All interpretation, validation
/// and execution live in `CommandEngine`.
enum CommandModeService {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "commandModeEnabled") as? Bool ?? true
    }

    /// The controller owns its engine, so pending plans cannot migrate between sessions.
    @MainActor
    private static func engine(for controller: DictationController) -> CommandEngine {
        controller.commandEngine
    }

    @MainActor
    static func handle(_ transcript: String, controller: DictationController) -> Bool {
        execute(transcript, controller: controller) != nil
    }

    /// Processes a transcript through the command engine, returning its full outcome.
    @MainActor
    static func processTranscript(_ transcript: String, controller: DictationController) -> CommandEngineOutcome {
        if isEnabled, engine(for: controller).pendingConfirmation == nil,
           AgentSessionController.shared.voiceDecision(transcript).kind != .dictation,
           AgentActivation.matchGoal(transcript) != nil || CustomCommandStore.shared.findMatching(transcript: transcript) == nil {
            let session = AgentSessionController.shared
            guard session.canAcceptVoiceIntent else { return .failed(message: "DailyOps is busy. Finish or approve the current action first.") }
            Task {
                await session.handleVoiceIntent(session.voiceDecision(transcript), transcript: transcript)
            }
            MainWindow.show(controller: controller, selectedTab: .workspace)
            return .executed(feedback: "DailyOps: Received \(session.voiceDecision(transcript).action)")
        }
        if isEnabled, let custom = CustomCommandStore.shared.findMatching(transcript: transcript) {
            let result = CustomCommandExecutor.shared.execute(custom)
            switch result {
            case .success(let msg):
                return .executed(feedback: msg)
            case .failure(let err):
                return .failed(message: err)
            }
        }
        let context = CommandContext(
            frontmostApplicationName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
            timestamp: Date(),
            isCommandModeEnabled: isEnabled
        )
        return engine(for: controller).process(transcript, context: context)
    }

    /// Asynchronously processes a transcript through the command engine.
    @MainActor
    static func processTranscriptAsync(_ transcript: String, controller: DictationController) async -> CommandEngineOutcome {
        if isEnabled, engine(for: controller).pendingConfirmation == nil,
           AgentSessionController.shared.voiceDecision(transcript).kind != .dictation,
           AgentActivation.matchGoal(transcript) != nil || CustomCommandStore.shared.findMatching(transcript: transcript) == nil {
            let session = AgentSessionController.shared
            guard session.canAcceptVoiceIntent else { return .failed(message: "DailyOps is busy. Finish or approve the current action first.") }
            await session.handleVoiceIntent(session.voiceDecision(transcript), transcript: transcript)
            MainWindow.show(controller: controller, selectedTab: .workspace)
            return .executed(feedback: "DailyOps: Received \(session.voiceDecision(transcript).action)")
        }
        if isEnabled, let custom = CustomCommandStore.shared.findMatching(transcript: transcript) {
            let result = CustomCommandExecutor.shared.execute(custom)
            switch result {
            case .success(let msg):
                return .executed(feedback: msg)
            case .failure(let err):
                return .failed(message: err)
            }
        }
        let context = CommandContext(
            frontmostApplicationName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
            timestamp: Date(),
            isCommandModeEnabled: isEnabled
        )
        return await engine(for: controller).processAsync(transcript, context: context)
    }

    /// Confirms a pending confirmation request by ID and executes the validated plan.
    @MainActor
    static func confirmPending(id: ConfirmationRequestID, controller: DictationController) -> CommandResult {
        let context = CommandContext(
            frontmostApplicationName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
            timestamp: Date(),
            isCommandModeEnabled: isEnabled
        )
        return engine(for: controller).confirm(id: id, context: context)
    }

    /// Cancels a pending confirmation request by ID without executing anything.
    @discardableResult
    @MainActor
    static func cancelPending(id: ConfirmationRequestID, controller: DictationController) -> CommandResult {
        return engine(for: controller).cancel(id: id)
    }

    /// Feedback for a recognised command, or nil to let normal dictation
    /// continue with the transcript untouched.
    @MainActor
    static func execute(_ transcript: String, controller: DictationController) -> String? {
        if isEnabled, engine(for: controller).pendingConfirmation == nil,
           AgentSessionController.shared.voiceDecision(transcript).kind != .dictation,
           AgentActivation.matchGoal(transcript) != nil || CustomCommandStore.shared.findMatching(transcript: transcript) == nil {
            let session = AgentSessionController.shared
            guard session.canAcceptVoiceIntent else { return "DailyOps is busy. Finish or approve the current action first." }
            Task {
                await session.handleVoiceIntent(session.voiceDecision(transcript), transcript: transcript)
            }
            MainWindow.show(controller: controller, selectedTab: .workspace)
            return "DailyOps: Received \(session.voiceDecision(transcript).action)"
        }
        if isEnabled, let custom = CustomCommandStore.shared.findMatching(transcript: transcript) {
            let result = CustomCommandExecutor.shared.execute(custom)
            switch result {
            case .success(let msg):
                return msg
            case .failure(let err):
                return err
            }
        }
        let context = CommandContext(
            frontmostApplicationName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
            timestamp: Date(),
            isCommandModeEnabled: isEnabled
        )
        return engine(for: controller).handle(transcript, context: context)
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
