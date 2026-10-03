import XCTest
@testable import DailyOps

@MainActor
final class MultiStepExecutionTests: XCTestCase {
    private var appControl: FakeApplicationControl!
    private var browserControl: FakeBrowserControl!
    private var router: CommandRouter!

    override func setUp() async throws {
        try await super.setUp()
        appControl = FakeApplicationControl()
        browserControl = FakeBrowserControl()

        let appExecutor = ApplicationCommandExecutor(control: appControl)
        let browserExecutor = BrowserCommandExecutor(control: browserControl)

        router = CommandRouter(
            parsers: [],
            validator: CommandValidator(registry: .standard()),
            executors: [appExecutor, browserExecutor]
        )
    }

    func testStepsExecuteStrictlyInOrder() {
        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Safari"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .browserOpenURL,
                arguments: .url(URL(string: "https://github.com")!)
            ))
        ])

        let result = router.run(plan, context: .test())

        guard case .success(let message) = result else {
            return XCTFail("Expected success for safe multi-step plan")
        }

        XCTAssertTrue(message.contains("Completed 2 actions"))
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(browserControl.openedURLs.count, 1)
        XCTAssertEqual(appControl.launched.first?.displayName, "Safari")
        XCTAssertEqual(browserControl.openedURLs.first?.absoluteString, "https://github.com")
    }

    func testFailureAtStepTwoHaltsAndSkipsStepThree() {
        browserControl.shouldFail = true // Step 2 will fail

        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Safari"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .browserOpenURL,
                arguments: .url(URL(string: "https://github.com")!)
            )),
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Google Chrome"))
            ))
        ])

        let result = router.run(plan, context: .test())

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure when step 2 fails")
        }

        // Partial completion is reported
        XCTAssertTrue(message.contains("Completed 1 of 3 actions"))
        XCTAssertTrue(message.contains("Step 2 failed"))

        // Step 1 completed
        XCTAssertEqual(appControl.launched.count, 1)
        XCTAssertEqual(appControl.launched.first?.displayName, "Safari")

        // Step 3 was skipped (Chrome was never launched)
        XCTAssertFalse(appControl.launched.contains { $0.displayName == "Google Chrome" })
    }

    func testFailureAtStepOneHaltsImmediatelyWithoutRunningStepTwo() {
        appControl.errorToThrow = .operationFailed("Could not launch application")

        let plan = CommandPlan(steps: [
            CommandStep(intent: CommandIntent(
                identifier: .appOpen,
                arguments: .application(ApplicationReference(displayName: "Safari"))
            )),
            CommandStep(intent: CommandIntent(
                identifier: .browserOpenURL,
                arguments: .url(URL(string: "https://github.com")!)
            ))
        ])

        let result = router.run(plan, context: .test())

        guard case .failure(let message) = result else {
            return XCTFail("Expected failure when step 1 fails")
        }

        XCTAssertTrue(message.contains("Step 1 failed"))
        XCTAssertEqual(browserControl.openedURLs.count, 0)
    }
}
