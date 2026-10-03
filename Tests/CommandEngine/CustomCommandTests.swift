import XCTest
@testable import DailyOps

@MainActor
final class CustomCommandTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset custom commands for testing
        UserDefaults.standard.removeObject(forKey: "dailyops_custom_commands")
        CustomCommandStore.shared.loadCommands()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "dailyops_custom_commands")
        CustomCommandStore.shared.loadCommands()
        super.tearDown()
    }

    func testCustomCommandModelProperties() {
        let cmd = CustomCommand(
            triggerPhrase: "open my workspace",
            actionType: .openFolder,
            target: "~/Workspace",
            customDescription: "Opens local workspace folder",
            isEnabled: true
        )

        XCTAssertEqual(cmd.triggerPhrase, "open my workspace")
        XCTAssertEqual(cmd.actionType, .openFolder)
        XCTAssertEqual(cmd.target, "~/Workspace")
        XCTAssertEqual(cmd.customDescription, "Opens local workspace folder")
        XCTAssertTrue(cmd.isEnabled)
    }

    func testStoreAddUpdateDeleteToggle() {
        let store = CustomCommandStore.shared
        let initialCount = store.commands.count

        let newCmd = CustomCommand(
            triggerPhrase: "launch music",
            actionType: .openApplication,
            target: "Music",
            customDescription: "Opens Apple Music"
        )

        store.add(newCmd)
        XCTAssertEqual(store.commands.count, initialCount + 1)
        XCTAssertTrue(store.commands.contains(where: { $0.id == newCmd.id }))

        // Toggle
        store.toggle(id: newCmd.id)
        XCTAssertFalse(store.commands.first(where: { $0.id == newCmd.id })?.isEnabled ?? true)

        // Matching should be nil when disabled
        XCTAssertNil(store.findMatching(transcript: "launch music"))

        // Re-enable
        store.toggle(id: newCmd.id)
        XCTAssertTrue(store.commands.first(where: { $0.id == newCmd.id })?.isEnabled ?? false)
        XCTAssertNotNil(store.findMatching(transcript: "launch music"))

        // Update
        var updated = newCmd
        updated.customDescription = "Updated description"
        store.update(updated)
        XCTAssertEqual(store.commands.first(where: { $0.id == newCmd.id })?.customDescription, "Updated description")

        // Delete
        store.delete(id: newCmd.id)
        XCTAssertEqual(store.commands.count, initialCount)
        XCTAssertNil(store.findMatching(transcript: "launch music"))
    }

    func testMatchingNormalizedPunctuationAndCase() {
        let store = CustomCommandStore.shared
        let cmd = CustomCommand(
            triggerPhrase: "Open My Dashboard!",
            actionType: .openURL,
            target: "https://example.com/dash"
        )
        store.add(cmd)

        // Various pronunciations / normalizations
        XCTAssertNotNil(store.findMatching(transcript: "open my dashboard"))
        XCTAssertNotNil(store.findMatching(transcript: "OPEN MY DASHBOARD!"))
        XCTAssertNotNil(store.findMatching(transcript: "  open  my   dashboard.  "))

        XCTAssertNil(store.findMatching(transcript: "open dashboard"))
    }

    func testExecutorEmptyTarget() {
        let executor = CustomCommandExecutor.shared
        let cmd = CustomCommand(
            triggerPhrase: "invalid",
            actionType: .openURL,
            target: "   "
        )
        let result = executor.execute(cmd)
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.message, "Target cannot be empty.")
    }

    func testExecutorInvalidURL() {
        let executor = CustomCommandExecutor.shared
        let cmd = CustomCommand(
            triggerPhrase: "invalid url",
            actionType: .openURL,
            target: "not a valid scheme url ::/"
        )
        let result = executor.execute(cmd)
        XCTAssertFalse(result.isSuccess)
    }

    func testExecutorNonexistentFile() {
        let executor = CustomCommandExecutor.shared
        let cmd = CustomCommand(
            triggerPhrase: "missing file",
            actionType: .openFile,
            target: "/path/to/definitely/nonexistent_file_12345.xyz"
        )
        let result = executor.execute(cmd)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.message.contains("File does not exist"))
    }

    func testExecutorNonexistentFolder() {
        let executor = CustomCommandExecutor.shared
        let cmd = CustomCommand(
            triggerPhrase: "missing folder",
            actionType: .openFolder,
            target: "/path/to/definitely/nonexistent_folder_12345"
        )
        let result = executor.execute(cmd)
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.message.contains("Folder does not exist"))
    }
}
