import Foundation

/// Turns a transcript into a plan, or returns nil when the transcript is not a
/// command. Parsers only ever produce data; they never perform side effects,
/// which is what allows additional parsing strategies to be added later
/// without widening the engine's execution surface.
/// Main-actor bound because application lookup consults the shared installed
/// application index, which is main-actor state.
@MainActor
protocol CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan?
}

/// Resolves a spoken application name to something concrete. Behind a protocol
/// so parsing can be tested without scanning `/Applications`.
@MainActor
protocol ApplicationResolving {
    /// An installed application that can be launched.
    func installedApplication(named query: String) -> ApplicationReference?
    /// A currently running application that can be quit or hidden.
    func runningApplication(named query: String) -> ApplicationReference?
}

/// Normalisation shared by parsing and application lookup: case-folds, strips
/// punctuation and collapses whitespace so "Open Safari." and "open  safari"
/// are the same input.
enum CommandTextNormalizer {
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Exact-phrase and prefix matching only. Nothing here guesses: a transcript
/// either matches a known phrase, or names an application that actually
/// resolves, or it is not a command. Fuzzy scoring is deliberately absent
/// because a near-miss would silently execute instead of being dictated.
@MainActor
struct DeterministicCommandParser: CommandParsing {
    private let applications: ApplicationResolving

    /// Phrases that map to a fixed command with no arguments.
    private static let exactPhrases: [String: CommandIntent] = {
        var table: [String: CommandIntent] = [:]

        func add(_ phrases: [String], _ intent: CommandIntent) {
            for phrase in phrases {
                table[CommandTextNormalizer.normalize(phrase)] = intent
            }
        }

        add(
            ["open settings", "show settings", "dailyops settings", "preferences"],
            CommandIntent(identifier: .settingsOpen)
        )
        add(
            ["open history", "show history", "dictation history", "view history"],
            CommandIntent(identifier: .historyOpen)
        )
        add(
            ["copy last dictation", "copy last", "copy transcript"],
            CommandIntent(identifier: .clipboardCopyLast)
        )
        add(
            ["reload speech model", "reload model", "restart speech model"],
            CommandIntent(identifier: .speechModelReload)
        )
        add(
            ["clear clipboard", "empty clipboard"],
            CommandIntent(identifier: .clipboardClear)
        )
        add(
            ["formal mode", "switch to formal mode", "enable formal mode", "formal writing mode"],
            CommandIntent(identifier: .dictationModeFormal, arguments: .writingMode(.formal))
        )
        add(
            ["standard mode", "switch to standard mode", "enable standard mode", "standard writing mode"],
            CommandIntent(identifier: .dictationModeStandard, arguments: .writingMode(.standard))
        )
        add(
            [
                "open my browser", "open default browser", "launch my browser",
                "open browser", "launch browser", "launch default browser"
            ],
            CommandIntent(identifier: .browserOpenDefault)
        )
        add(
            [
                "open private tab", "open private browsing", "open incognito", "open private",
                "open an incognito window", "open incognito window", "open incognito tab", "open private window"
            ],
            CommandIntent(identifier: .browserOpenPrivate)
        )
        return table
    }()

    private static let launchPrefixes = ["open ", "launch ", "start ", "show "]
    private static let switchPrefixes = ["switch to ", "go to ", "activate "]
    private static let quitPrefixes = ["quit ", "close ", "kill "]
    private static let hidePrefixes = ["hide "]

    init(applications: ApplicationResolving) {
        self.applications = applications
    }

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        var command = CommandTextNormalizer.normalize(transcript)
        guard !command.isEmpty else { return nil }
        if command.hasSuffix(" please") {
            command = String(command.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // 1. Exact fixed phrases
        if let intent = Self.exactPhrases[command] {
            return CommandPlan(intent: intent)
        }

        // 2. Web search queries ("search Google for cats", "Google search machine learning", "search YouTube for...")
        if let searchPlan = Self.parseSearch(from: transcript) {
            return searchPlan
        }

        // 3. Application switch ("switch to WhatsApp", "go to VS Code", "activate Safari")
        if let name = Self.argument(in: command, afterAnyOf: Self.switchPrefixes),
           let app = applications.runningApplication(named: name) ?? applications.installedApplication(named: name) {
            return CommandPlan(intent: CommandIntent(identifier: .appSwitch, arguments: .application(app)))
        }

        // 4. Application commands ("open WhatsApp", "launch Safari", "start Chrome")
        if let name = Self.argument(in: command, afterAnyOf: Self.launchPrefixes),
           let app = applications.installedApplication(named: name) {
            return CommandPlan(intent: CommandIntent(identifier: .appOpen, arguments: .application(app)))
        }

        // 5. Website and URL navigation ("open github.com", "open https://...", "go to github.com", "open YouTube")
        if let webPlan = Self.parseWebsiteOrURL(from: transcript) {
            return webPlan
        }

        // 6. Application quit / hide
        if let name = Self.argument(in: command, afterAnyOf: Self.quitPrefixes),
           let app = applications.runningApplication(named: name) {
            return CommandPlan(intent: CommandIntent(identifier: .appQuit, arguments: .application(app)))
        }
        if let name = Self.argument(in: command, afterAnyOf: Self.hidePrefixes),
           let app = applications.runningApplication(named: name) {
            return CommandPlan(intent: CommandIntent(identifier: .appHide, arguments: .application(app)))
        }

        // 7. Context-aware commands
        if let contextPlan = Self.parseContextCommand(command, context: context) {
            return contextPlan
        }

        return nil
    }

    private static func parseContextCommand(_ command: String, context: CommandContext) -> CommandPlan? {
        // "open it" / "open that" / "open the file" - resolves to resolvedFileURL
        if command == "open it" || command == "open that" || command == "open the file" || command == "open this file" {
            if context.resolvedFileURL != nil {
                return CommandPlan(intent: CommandIntent(
                    identifier: .contextOpen,
                    arguments: .contextOpen(ContextOpenRequest(targetKind: .file))
                ))
            }
            return nil
        }

        // "message him" / "message her" / "text him" / "text her" - resolves to resolvedContact
        if command == "message him" || command == "message her" || command == "text him" || command == "text her" {
            if let _ = context.resolvedContactName, let _ = context.resolvedContactPhone {
                return CommandPlan(intent: CommandIntent(
                    identifier: .contextMessage,
                    arguments: .contextMessage(ContextMessageRequest(message: ""))
                ))
            }
            return nil
        }

        // "message him saying X" / "text him saying X" / "message her that X"
        if let message = extractMessageFromContextCommand(command) {
            if let _ = context.resolvedContactName, let _ = context.resolvedContactPhone {
                return CommandPlan(intent: CommandIntent(
                    identifier: .contextMessage,
                    arguments: .contextMessage(ContextMessageRequest(message: message))
                ))
            }
            return nil
        }

        // "check my next meeting" / "what's my next meeting" / "check calendar"
        if command == "check my next meeting" || command == "what is my next meeting" || command == "whats my next meeting" || command == "check calendar" || command == "check my calendar" {
            if context.resolvedCalendarEventTitle != nil || context.resolvedCalendarEventDate != nil {
                return CommandPlan(intent: CommandIntent(
                    identifier: .contextCheck,
                    arguments: .contextCheck(ContextCheckRequest(targetKind: .calendarEvent))
                ))
            }
            // Also allow without prior context - will query calendar for next event
            return CommandPlan(intent: CommandIntent(
                identifier: .contextCheck,
                arguments: .contextCheck(ContextCheckRequest(targetKind: .calendarEvent))
            ))
        }

        // "check my reminders" / "what are my reminders"
        if command == "check my reminders" || command == "what are my reminders" || command == "check reminders" {
            if context.resolvedReminderTitle != nil {
                return CommandPlan(intent: CommandIntent(
                    identifier: .contextCheck,
                    arguments: .contextCheck(ContextCheckRequest(targetKind: .reminder))
                ))
            }
            return CommandPlan(intent: CommandIntent(
                identifier: .contextCheck,
                arguments: .contextCheck(ContextCheckRequest(targetKind: .reminder))
            ))
        }

        // "what app am I in" / "what app is open" / "which app am I using" - frontmost application
        if command == "what app am i in" || command == "what app is open" || command == "which app am i using" || command == "which application is open" || command == "what is my current app" || command == "check my current app" || command == "check current app" {
            return CommandPlan(intent: CommandIntent(
                identifier: .contextCheck,
                arguments: .contextCheck(ContextCheckRequest(targetKind: .application))
            ))
        }

        // "open this app" / "open the current app" - open the frontmost application
        if command == "open this app" || command == "open the current app" {
            return CommandPlan(intent: CommandIntent(
                identifier: .contextOpen,
                arguments: .contextOpen(ContextOpenRequest(targetKind: .application))
            ))
        }

        return nil
    }

    private static func extractMessageFromContextCommand(_ command: String) -> String? {
        let sayingPrefixes = ["message him saying ", "message her saying ", "text him saying ", "text her saying "]
        for prefix in sayingPrefixes {
            if command.hasPrefix(prefix) {
                return String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        let thatPrefixes = ["message him that ", "message her that ", "text him that ", "text her that "]
        for prefix in thatPrefixes {
            if command.hasPrefix(prefix) {
                return String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func parseSearch(from transcript: String) -> CommandPlan? {
        let cleanText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))

        let searchPatterns: [(prefix: String, provider: SearchProvider)] = [
            ("search google for ", .google),
            ("search youtube for ", .youtube),
            ("google search for ", .google),
            ("google search ", .google),
            ("youtube search for ", .youtube),
            ("youtube search ", .youtube),
            ("search for ", .google)
        ]

        for (prefix, provider) in searchPatterns {
            if let range = cleanText.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                let query = String(cleanText[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return CommandPlan(intent: CommandIntent(
                        identifier: .browserSearch,
                        arguments: .search(SearchRequest(query: query, provider: provider))
                    ))
                }
            }
        }
        return nil
    }

    private static func parseWebsiteOrURL(from transcript: String) -> CommandPlan? {
        let cleanText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))

        let websitePrefixes = ["open ", "go to ", "visit "]
        // Spoken qualifiers the user might append when they want a URL opened in
        // the browser rather than a native app. Strip them before URL normalisation
        // so "open YouTube in my browser" works identically to "open YouTube".
        let browserQualifierSuffixes = [
            " in my browser", " in the browser", " in my default browser",
            " on my browser", " in browser", " in a browser"
        ]
        for prefix in websitePrefixes {
            if let range = cleanText.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                var candidate = String(cleanText[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else { continue }
                // Strip browser qualifier suffix (case-insensitive comparison on lowercased).
                let lower = candidate.lowercased()
                for suffix in browserQualifierSuffixes where lower.hasSuffix(suffix) {
                    candidate = String(candidate.dropLast(suffix.count))
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
                if candidate.lowercased().hasSuffix(" please") {
                    candidate = String(candidate.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
                }
                guard !candidate.isEmpty else { continue }
                if let url = URLNormalizer.normalize(candidate) {
                    return CommandPlan(intent: CommandIntent(
                        identifier: .browserOpenURL,
                        arguments: .url(url)
                    ))
                }
            }
        }
        return nil
    }

    private static func argument(in command: String, afterAnyOf prefixes: [String]) -> String? {
        for prefix in prefixes where command.hasPrefix(prefix) {
            let argument = String(command.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            if !argument.isEmpty { return argument }
        }
        return nil
    }
}
