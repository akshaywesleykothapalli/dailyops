import XCTest
@testable import DailyOps

/// Parsing is the boundary that decides whether speech becomes an action or
/// text. These tests pin both directions: recognised phrases produce the right
/// intent, and everything else is left alone for dictation.
@MainActor
final class DeterministicCommandParserTests: XCTestCase {
    private func parser(
        installed: [String] = [],
        running: [String] = []
    ) -> (DeterministicCommandParser, FakeApplicationResolver) {
        let resolver = FakeApplicationResolver(installed: installed, running: running)
        return (DeterministicCommandParser(applications: resolver), resolver)
    }

    private func identifier(
        _ parser: DeterministicCommandParser,
        _ transcript: String
    ) -> CommandIdentifier? {
        parser.parse(transcript, context: .test())?.steps.first?.intent.identifier
    }

    // MARK: - Valid phrases

    func testRecognisesExactPhrases() {
        let (parser, _) = self.parser()
        let cases: [(String, CommandIdentifier)] = [
            ("open settings", .settingsOpen),
            ("preferences", .settingsOpen),
            ("open history", .historyOpen),
            ("view history", .historyOpen),
            ("copy last dictation", .clipboardCopyLast),
            ("copy transcript", .clipboardCopyLast),
            ("clear clipboard", .clipboardClear),
            ("empty clipboard", .clipboardClear),
            ("formal mode", .dictationModeFormal),
            ("standard mode", .dictationModeStandard),
            ("reload speech model", .speechModelReload),
        ]
        for (transcript, expected) in cases {
            XCTAssertEqual(identifier(parser, transcript), expected, "phrase: \(transcript)")
        }
    }

    func testWritingModePhrasesCarryTheirMode() {
        let (parser, _) = self.parser()

        let formal = parser.parse("formal mode", context: .test())?.steps.first?.intent
        XCTAssertEqual(formal?.arguments, .writingMode(.formal))

        let standard = parser.parse("standard mode", context: .test())?.steps.first?.intent
        XCTAssertEqual(standard?.arguments, .writingMode(.standard))
    }

    // MARK: - Capitalisation, whitespace, punctuation

    func testIgnoresCapitalisation() {
        let (parser, _) = self.parser()
        XCTAssertEqual(identifier(parser, "OPEN SETTINGS"), .settingsOpen)
        XCTAssertEqual(identifier(parser, "Open Settings"), .settingsOpen)
        XCTAssertEqual(identifier(parser, "oPeN sEtTiNgS"), .settingsOpen)
    }

    func testIgnoresSurroundingAndRepeatedWhitespace() {
        let (parser, _) = self.parser()
        XCTAssertEqual(identifier(parser, "   open settings   "), .settingsOpen)
        XCTAssertEqual(identifier(parser, "open    settings"), .settingsOpen)
        XCTAssertEqual(identifier(parser, "\topen\nsettings\n"), .settingsOpen)
    }

    func testIgnoresTrailingPunctuation() {
        let (parser, _) = self.parser()
        XCTAssertEqual(identifier(parser, "Open settings."), .settingsOpen)
        XCTAssertEqual(identifier(parser, "open settings!"), .settingsOpen)
        XCTAssertEqual(identifier(parser, "Open history?"), .historyOpen)
    }

    func testEmptyAndPunctuationOnlyTranscriptsAreNotCommands() {
        let (parser, _) = self.parser()
        XCTAssertNil(parser.parse("", context: .test()))
        XCTAssertNil(parser.parse("   ", context: .test()))
        XCTAssertNil(parser.parse("...", context: .test()))
    }

    // MARK: - Application commands

    func testOpenResolvesInstalledApplication() {
        let (parser, _) = self.parser(installed: ["calculator"])
        let intent = parser.parse("Open Calculator", context: .test())?.steps.first?.intent
        XCTAssertEqual(intent?.identifier, .appOpen)
        XCTAssertEqual(intent?.arguments, .application(
            ApplicationReference(
                displayName: "calculator",
                bundleURL: URL(fileURLWithPath: "/Applications/calculator.app")
            )
        ))
    }

    func testLaunchSynonymsAllResolve() {
        let (parser, _) = self.parser(installed: ["calculator"])
        for phrase in ["open calculator", "launch calculator", "start calculator"] {
            XCTAssertEqual(identifier(parser, phrase), .appOpen, "phrase: \(phrase)")
        }
    }

    func testQuitAndHideActOnRunningApplications() {
        let (parser, _) = self.parser(running: ["safari"])
        for phrase in ["quit safari", "close safari", "kill safari"] {
            XCTAssertEqual(identifier(parser, phrase), .appQuit, "phrase: \(phrase)")
        }
        XCTAssertEqual(identifier(parser, "hide safari"), .appHide)
    }

    func testQuitIsNotACommandWhenTheApplicationIsNotRunning() {
        // Only installed, never running: quitting must not resolve.
        let (parser, _) = self.parser(installed: ["safari"])
        XCTAssertNil(parser.parse("quit safari", context: .test()))
        XCTAssertNil(parser.parse("hide safari", context: .test()))
    }

    func testExactPhrasesWinOverApplicationPrefixes() {
        // "show " is a launch prefix and "show settings" is an exact phrase.
        // The phrase must win, and no application lookup should be attempted.
        let (parser, resolver) = self.parser(installed: ["settings"])
        XCTAssertEqual(identifier(parser, "show settings"), .settingsOpen)
        XCTAssertTrue(resolver.installedQueries.isEmpty)
    }

    // MARK: - Dictation fallback (§18)

    func testUnrecognisedSentencesAreLeftForDictation() {
        let (parser, _) = self.parser(installed: ["calculator"], running: ["safari"])
        let dictation = [
            "Please remind me to buy milk tomorrow.",
            "Open the discussion tomorrow with the pricing slide.",
            "Let's close the loop on this next week.",
            "Start by introducing yourself to the team.",
            "I hid the spare key under the mat.",
            "The settings we agreed on last quarter are fine.",
            "Copy that and send it over.",
            "Hey, can you show me the history of this project?",
        ]
        for transcript in dictation {
            XCTAssertNil(parser.parse(transcript, context: .test()), "should be dictation: \(transcript)")
        }
    }

    func testPrefixWithUnresolvableNameIsNotACommand() {
        let (parser, _) = self.parser()
        XCTAssertNil(parser.parse("open the pod bay doors", context: .test()))
        XCTAssertNil(parser.parse("launch a new initiative", context: .test()))
    }

    func testBarePrefixWithNoArgumentIsNotACommand() {
        let (parser, _) = self.parser(installed: ["calculator"])
        XCTAssertNil(parser.parse("open", context: .test()))
        XCTAssertNil(parser.parse("open ", context: .test()))
    }

    func testNothingParsesWhileCommandModeIsOff() {
        let (parser, _) = self.parser(installed: ["calculator"])
        let context = CommandContext.test(isCommandModeEnabled: false)
        XCTAssertNil(parser.parse("open settings", context: context))
        XCTAssertNil(parser.parse("open calculator", context: context))
    }

    // MARK: - Application Discovery Guardrails & False-Positive Tests

    func testSystemApplicationResolverResolvesStandardApps() {
        let systemResolver = SystemApplicationResolver(
            discovery: ApplicationDiscovery.shared,
            registry: ApplicationRegistry()
        )
        let parser = DeterministicCommandParser(applications: systemResolver)

        let apps = [
            "open WhatsApp",
            "launch Safari",
            "open Google Chrome",
            "open System Settings"
        ]
        for phrase in apps {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Expected valid plan for \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .appOpen, "Expected appOpen for \(phrase)")
        }
    }

    func testSystemApplicationResolverRejectsShortWordsAndParticles() {
        let systemResolver = SystemApplicationResolver(
            discovery: ApplicationDiscovery.shared,
            registry: ApplicationRegistry()
        )
        let parser = DeterministicCommandParser(applications: systemResolver)

        let negativePhrases = [
            "open a",
            "open in",
            "open me",
            "open the",
            "open to",
            "open at",
            "open it",
            "open on"
        ]
        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNil(plan, "Short particle/word phrase '\(phrase)' must NOT resolve to an app")
        }
    }
}
