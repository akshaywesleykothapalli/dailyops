import XCTest
@testable import DailyOps

@MainActor
final class BrowserParserTests: XCTestCase {
    private var resolver: FakeApplicationResolver!
    private var parser: DeterministicCommandParser!

    override func setUp() async throws {
        try await super.setUp()
        resolver = FakeApplicationResolver(installed: [
            "WhatsApp", "Google Chrome", "Safari", "Finder", "Notes"
        ])
        parser = DeterministicCommandParser(applications: resolver)
    }

    // MARK: - Application Command Tests

    func testParsesApplicationLaunchPhrases() {
        let whatsAppPlan = parser.parse("open WhatsApp", context: .test())
        XCTAssertEqual(whatsAppPlan?.steps.first?.intent.identifier, .appOpen)
        guard case .application(let app) = whatsAppPlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected application argument")
        }
        XCTAssertEqual(app.displayName, "WhatsApp")

        let launchPlan = parser.parse("launch WhatsApp", context: .test())
        XCTAssertEqual(launchPlan?.steps.first?.intent.identifier, .appOpen)

        let startPlan = parser.parse("start WhatsApp", context: .test())
        XCTAssertEqual(startPlan?.steps.first?.intent.identifier, .appOpen)

        let safariPlan = parser.parse("launch Safari", context: .test())
        XCTAssertEqual(safariPlan?.steps.first?.intent.identifier, .appOpen)
    }

    // MARK: - Website & URL Navigation Tests

    func testParsesFullHTTPSURL() {
        let plan = parser.parse("open https://github.com", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenURL)
        guard case .url(let url) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected URL argument")
        }
        XCTAssertEqual(url.absoluteString, "https://github.com")
    }

    func testParsesBareDomainURL() {
        let plan = parser.parse("open github.com", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenURL)
        guard case .url(let url) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected URL argument")
        }
        XCTAssertEqual(url.absoluteString, "https://github.com")
    }

    func testParsesWWWBareDomain() {
        let plan = parser.parse("open www.github.com", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenURL)
        guard case .url(let url) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected URL argument")
        }
        XCTAssertEqual(url.absoluteString, "https://www.github.com")
    }

    func testParsesGoToWebsitePhrase() {
        let plan = parser.parse("go to github.com", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenURL)
        guard case .url(let url) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected URL argument")
        }
        XCTAssertEqual(url.absoluteString, "https://github.com")
    }

    func testParsesKnownWebsiteNames() {
        let youtubePlan = parser.parse("open YouTube", context: .test())
        XCTAssertEqual(youtubePlan?.steps.first?.intent.identifier, .browserOpenURL)
        guard case .url(let url) = youtubePlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected URL argument")
        }
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com")

        let googlePlan = parser.parse("open Google", context: .test())
        XCTAssertEqual(googlePlan?.steps.first?.intent.identifier, .browserOpenURL)
        guard case .url(let googleURL) = googlePlan?.steps.first?.intent.arguments else {
            return XCTFail("Expected URL argument")
        }
        XCTAssertEqual(googleURL.absoluteString, "https://www.google.com")
    }

    // MARK: - Web Search Tests

    func testParsesSearchGoogleForQuery() {
        let plan = parser.parse("search Google for machine learning", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserSearch)
        guard case .search(let request) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected search request")
        }
        XCTAssertEqual(request.provider, .google)
        XCTAssertEqual(request.query, "machine learning")
    }

    func testParsesGoogleSearchQuery() {
        let plan = parser.parse("Google search machine learning", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserSearch)
        guard case .search(let request) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected search request")
        }
        XCTAssertEqual(request.provider, .google)
        XCTAssertEqual(request.query, "machine learning")
    }

    func testParsesSearchYouTubeForQuery() {
        let plan = parser.parse("search YouTube for worship songs", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserSearch)
        guard case .search(let request) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected search request")
        }
        XCTAssertEqual(request.provider, .youtube)
        XCTAssertEqual(request.query, "worship songs")
    }

    func testParsesSearchForQueryDefaultsToGoogle() {
        let plan = parser.parse("search for SwiftUI tutorials", context: .test())
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserSearch)
        guard case .search(let request) = plan?.steps.first?.intent.arguments else {
            return XCTFail("Expected search request")
        }
        XCTAssertEqual(request.provider, .google)
        XCTAssertEqual(request.query, "SwiftUI tutorials")
    }

    // MARK: - Default Browser & Private Browsing Tests

    func testParsesDefaultBrowserPhrases() {
        let phrases = [
            "open my browser",
            "open default browser",
            "launch my browser",
            "open browser",
            "launch browser",
            "launch default browser"
        ]
        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenDefault, "Failed for phrase: \(phrase)")
        }
    }

    func testParsesPrivateBrowsingPhrases() {
        let phrases = [
            "open private tab",
            "open private browsing",
            "open incognito",
            "open private",
            "open an incognito window",
            "open incognito window",
            "open incognito tab",
            "open private window"
        ]
        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .browserOpenPrivate, "Failed for phrase: \(phrase)")
        }
    }

    // MARK: - Fallthrough to Dictation Tests

    func testAmbiguousNaturalSentencesAreIgnoredForDictation() {
        XCTAssertNil(parser.parse("Open the door when you get home.", context: .test()))
        XCTAssertNil(parser.parse("I opened the browser yesterday.", context: .test()))
        XCTAssertNil(parser.parse("Please search the living room for my keys.", context: .test()))
        XCTAssertNil(parser.parse("Go to the store and buy milk.", context: .test()))
    }
}
