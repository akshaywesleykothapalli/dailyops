import XCTest
@testable import DailyOps

@MainActor
final class ApplicationRegistryTests: XCTestCase {
    private var registry: ApplicationRegistry!

    override func setUp() async throws {
        try await super.setUp()
        registry = ApplicationRegistry()
    }

    func testResolvesKnownStandardApplications() {
        let expectedNames = [
            "whatsapp": "WhatsApp",
            "safari": "Safari",
            "google chrome": "Google Chrome",
            "finder": "Finder",
            "system settings": "System Settings",
            "notes": "Notes",
            "calendar": "Calendar",
            "reminders": "Reminders",
            "music": "Music",
            "terminal": "Terminal"
        ]

        for (query, expectedDisplayName) in expectedNames {
            let app = registry.findKnownApplication(named: query)
            XCTAssertNotNil(app, "Expected to find known application for query: \(query)")
            XCTAssertEqual(app?.displayName, expectedDisplayName)
        }
    }

    func testResolvesApplicationAliases() {
        XCTAssertEqual(registry.findKnownApplication(named: "chrome")?.displayName, "Google Chrome")
        XCTAssertEqual(registry.findKnownApplication(named: "googlechrome")?.displayName, "Google Chrome")
        XCTAssertEqual(registry.findKnownApplication(named: "settings")?.displayName, "System Settings")
        XCTAssertEqual(registry.findKnownApplication(named: "preferences")?.displayName, "System Settings")
        XCTAssertEqual(registry.findKnownApplication(named: "sys pref")?.displayName, "System Settings")
        XCTAssertEqual(registry.findKnownApplication(named: "ical")?.displayName, "Calendar")
        XCTAssertEqual(registry.findKnownApplication(named: "whats app")?.displayName, "WhatsApp")
        XCTAssertEqual(registry.findKnownApplication(named: "apple notes")?.displayName, "Notes")
        XCTAssertEqual(registry.findKnownApplication(named: "apple music")?.displayName, "Music")
    }

    func testCaseAndPunctuationInsensitiveLookup() {
        XCTAssertEqual(registry.findKnownApplication(named: "   WhAtSaPp.  ")?.displayName, "WhatsApp")
        XCTAssertEqual(registry.findKnownApplication(named: "CHROME")?.displayName, "Google Chrome")
        XCTAssertEqual(registry.findKnownApplication(named: "System   Settings")?.displayName, "System Settings")
    }

    func testUnknownApplicationReturnsNil() {
        XCTAssertNil(registry.findKnownApplication(named: "nonexistent.fake.app"))
        XCTAssertNil(registry.findKnownApplication(named: "arbitrary shell command"))
        XCTAssertNil(registry.resolve(named: "nonexistent.fake.app"))
    }

    func testCustomApplicationRegistration() {
        let custom = KnownApplication(
            id: "slack",
            displayName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            aliases: ["slack", "team chat"]
        )
        registry.register(custom)

        XCTAssertEqual(registry.findKnownApplication(named: "team chat")?.displayName, "Slack")
        XCTAssertEqual(registry.findKnownApplication(named: "slack")?.displayName, "Slack")
    }
}
