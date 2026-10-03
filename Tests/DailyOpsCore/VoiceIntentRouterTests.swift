import XCTest
@testable import DailyOps

final class VoiceIntentRouterTests: XCTestCase {
    let router = VoiceIntentRouter()
    var profiles: [RoleWorkspaceProfile] { EmployeeRole.allCases.map(RoleWorkspaceProfile.defaults) }
    func testDirectCommands() {
        for app in ["VS Code", "Visual Studio Code", "Terminal", "Xcode", "Safari", "ChatGPT", "Codex", "OpenCode"] {
            let result = router.route("open \(app)", role: .developer, profiles: profiles)
            XCTAssertEqual(result.kind, .directCommand)
            XCTAssertEqual(result.steps.first?.toolID, "open_application")
        }
        XCTAssertEqual(router.route("open VS Code", role: .developer, profiles: profiles).steps.first?.value, "Visual Studio Code")
    }
    func testRoleWorkflows() {
        XCTAssertEqual(router.route("open my developer setup", role: .general, profiles: profiles).role, .developer)
        XCTAssertEqual(router.route("start my manager setup", role: .developer, profiles: profiles).kind, .roleWorkflow)
        XCTAssertEqual(router.route("open my work setup", role: .manager, profiles: profiles).role, .manager)
        XCTAssertNotEqual(RoleWorkspaceProfile.defaults(.developer).workflow, RoleWorkspaceProfile.defaults(.manager).workflow)
    }
    func testDictationSafety() {
        for text in ["I need to open Terminal later", "open the door", "Tomorrow I will start my workday", "Please prepare a report about my manager setup", "ordinary dictated text", "open Safari and delete files"] {
            XCTAssertEqual(router.route(text, role: .developer, profiles: profiles).kind, .dictation)
        }
        XCTAssertEqual(router.route("open VS Code", role: .developer, profiles: profiles, enabled: false).kind, .dictation)
    }
    func testGoals() {
        for text in ["start my workday", "prepare my standup", "prepare me for tomorrow's review"] {
            XCTAssertEqual(router.route(text, role: .developer, profiles: profiles).kind, .dailyOpsGoal)
        }
    }
    func testLocalPlanAndProject() {
        var configured = profiles
        configured[0].defaultProjectPath = "/tmp/DailyOps"
        let decision = router.route("open the DailyOps project and check git status", role: .developer, profiles: configured)
        XCTAssertEqual(decision.kind, .localAgentTask)
        let plan = LocalAgentTaskPlanner().plan(decision, goalID: UUID())
        XCTAssertEqual(plan.tasks.map { $0.toolRequirement?.toolId }, ["open_path", "git_status"])
        XCTAssertEqual(plan.tasks.last?.toolRequirement?.parameters["path"], "/tmp/DailyOps")
        XCTAssertEqual(plan.tasks.first?.toolRequirement?.parameters["application"], "Visual Studio Code")
        let setup = router.route("open my developer setup", role: .developer, profiles: configured)
        XCTAssertEqual(setup.steps.last?.kind, .project)
    }
    func testProfilePersistenceAndConfiguredApp() throws {
        let suite = "DailyOps.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var values = profiles
        values[0].defaultProjectPath = "/tmp/project"
        values[0].workflow.steps.append(.init(kind: .application, value: "My Editor"))
        values[0].voicePhrases = ["begin coding setup"]
        try RoleWorkspaceStore(defaults: defaults).save(values)
        let restored = RoleWorkspaceStore(defaults: defaults).load()
        XCTAssertEqual(restored, values)
        XCTAssertEqual(router.route("open My Editor", role: .developer, profiles: restored).kind, .directCommand)
        XCTAssertEqual(router.route("begin coding setup", role: .developer, profiles: restored).kind, .roleWorkflow)
    }
    func testDisabledStepsAndOrder() {
        var values = profiles
        values[0].workflow.steps[0].enabled = false
        let decision = router.route("open my developer setup", role: .developer, profiles: values)
        XCTAssertEqual(decision.steps.first?.value, "Terminal")
        XCTAssertFalse(decision.steps.contains { $0.value == "Visual Studio Code" })
    }
    func testUnavailableSetupAppSkippedTruthfully() {
        let decision = router.route("open my developer setup", role: .developer, profiles: profiles)
        let plan = LocalAgentTaskPlanner().plan(decision, goalID: UUID(), applicationAvailability: ["Codex": false])
        let task = plan.tasks.first { $0.toolRequirement?.parameters["application"] == "Codex" }
        XCTAssertEqual(task?.status, .skipped)
        XCTAssertTrue(task?.error?.contains("unavailable") == true)
        XCTAssertEqual(plan.tasks.first?.status, .pending)
    }
    @MainActor func testActualCommandModeTranscriptFallback() async {
        let old = UserDefaults.standard.object(forKey: "commandModeEnabled")
        defer {
            if let old { UserDefaults.standard.set(old, forKey: "commandModeEnabled") }
            else { UserDefaults.standard.removeObject(forKey: "commandModeEnabled") }
        }
        let controller = DictationController()
        UserDefaults.standard.set(false, forKey: "commandModeEnabled")
        if case .ignored = await CommandModeService.processTranscriptAsync("open VS Code", controller: controller) {} else { XCTFail("Disabled Command Mode must preserve dictation") }
        UserDefaults.standard.set(true, forKey: "commandModeEnabled")
        if case .ignored = await CommandModeService.processTranscriptAsync("ordinary dictated text", controller: controller) {} else { XCTFail("Ordinary speech must preserve dictation") }
    }
    func testUnavailableApplication() async throws {
        let result = try await OpenApplicationTool().execute(parameters: ["application": "DailyOpsNonexistentApp-\(UUID())"])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.error?.contains("unavailable") == true)
    }
    func testGitStatusReadOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", directory.path]; git.standardOutput = Pipe(); git.standardError = Pipe()
        try git.run(); git.waitUntilExit(); XCTAssertEqual(git.terminationStatus, 0)
        let file = directory.appendingPathComponent("example.txt")
        try "unchanged".write(to: file, atomically: true, encoding: .utf8)
        let result = try await GitStatusTool().execute(parameters: ["path": directory.path, "command": "rm -rf anything"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output?.contains("example.txt") == true)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "unchanged")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git/index").path))
    }
    func testLocalToolsAndURLSafety() async throws {
        XCTAssertNil(ToolRegistry.shared.tool(id: "shell"))
        for id in ["git_status", "git_branch", "open_path", "open_url", "read_clipboard", "copy_to_clipboard"] { XCTAssertNotNil(ToolRegistry.shared.tool(id: id)) }
        let result = try await OpenURLTool().execute(parameters: ["url": "file:///tmp/example"])
        XCTAssertFalse(result.success)
        XCTAssertEqual(CopyToClipboardTool().riskLevel, .confirmationRequired)
    }
    @MainActor func testSharedVoiceEntryAndRuntime() async {
        let session = AgentSessionController()
        XCTAssertEqual(session.voiceDecision("open VS Code").kind, .directCommand)
        XCTAssertEqual(session.voiceDecision("a sentence", enabled: false).kind, .dictation)
        let result = await session.submitGoal("open my developer setup", source: .voice)
        XCTAssertEqual(result.plan?.tasks.first?.toolRequirement?.toolId, "open_application")
        XCTAssertEqual(result.verification?.approved, true)
    }
}
