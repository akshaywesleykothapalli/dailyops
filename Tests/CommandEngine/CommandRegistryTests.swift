import XCTest
@testable import DailyOps

@MainActor
final class CommandRegistryTests: XCTestCase {
    private let probe = CommandIdentifier(rawValue: "test.probe")

    func testEmptyRegistryKnowsNothing() {
        let registry = CommandRegistry()
        XCTAssertTrue(registry.registeredIdentifiers.isEmpty)
        XCTAssertNil(registry.definition(for: .settingsOpen))
    }

    func testRegistrationThenLookup() {
        let registry = CommandRegistry()
        let definition = CommandDefinition(
            identifier: probe,
            name: "Probe",
            risk: .safe,
            confirmation: .none
        )
        registry.register(definition)

        XCTAssertEqual(registry.definition(for: probe), definition)
        XCTAssertEqual(registry.registeredIdentifiers, [probe])
    }

    func testLookupOfUnknownIdentifierReturnsNil() {
        let registry = CommandRegistry(definitions: [
            CommandDefinition(identifier: .settingsOpen, name: "Open Settings", risk: .safe, confirmation: .none)
        ])
        XCTAssertNil(registry.definition(for: CommandIdentifier(rawValue: "app.does.not.exist")))
    }

    func testReRegisteringAnIdentifierReplacesTheDefinition() {
        let registry = CommandRegistry(definitions: [
            CommandDefinition(identifier: probe, name: "First", risk: .safe, confirmation: .none)
        ])
        registry.register(
            CommandDefinition(identifier: probe, name: "Second", risk: .destructive, confirmation: .mandatory)
        )

        XCTAssertEqual(registry.definition(for: probe)?.name, "Second")
        XCTAssertEqual(registry.definition(for: probe)?.risk, .destructive)
        XCTAssertEqual(registry.registeredIdentifiers.count, 1)
    }

    func testDuplicateIdentifiersAtInitKeepTheLastOne() {
        let registry = CommandRegistry(definitions: [
            CommandDefinition(identifier: probe, name: "First", risk: .safe, confirmation: .none),
            CommandDefinition(identifier: probe, name: "Second", risk: .safe, confirmation: .none),
        ])
        XCTAssertEqual(registry.definition(for: probe)?.name, "Second")
    }

    // MARK: - The shipped table

    func testStandardRegistryCoversEveryShippedCommand() {
        let registry = CommandRegistry.standard()
        let expected: Set<CommandIdentifier> = [
            // Foundation commands
            .appOpen, .appQuit, .appHide, .appSwitch,
            .settingsOpen, .historyOpen,
            .dictationModeFormal, .dictationModeStandard,
            .clipboardCopyLast, .clipboardClear, .clipboardInspect,
            .speechModelReload,
            // Browser
            .browserOpenURL, .browserSearch,
            .browserOpenDefault, .browserOpenPrivate,
            // WhatsApp
            .whatsAppOpenChat, .whatsAppSendMessage,
            // Calendar
            .calendarOpen, .calendarCreateEvent, .calendarListEvents, .calendarDeleteEvent,
            // Reminders
            .remindersOpen, .remindersCreate, .remindersList, .remindersComplete, .remindersDelete,
            // Notes
            .notesOpen, .notesCreate, .notesFind, .notesOpenNote,
            // Finder
            .finderOpenLocation, .finderFindFiles,
            .finderCreateFolder, .finderCreateFile, .finderReveal, .finderTrash, .finderRename, .finderDuplicate,
            // Context
            .contextOpen, .contextMessage, .contextCheck,
            // Contacts
            .contactsFind, .contactsShow,
            // Mail
            .mailOpen, .mailCompose,
            // System Information
            .systemBattery, .systemMacOSVersion, .systemTime, .systemDate,
            // System Audio
            .systemVolumeUp, .systemVolumeDown, .systemVolumeSet, .systemVolumeMute, .systemVolumeUnmute, .systemVolumeGet,
            // System Power & Session
            .systemSleep, .systemLock, .systemLogout, .systemRestart, .systemShutdown,
        ]
        XCTAssertEqual(registry.registeredIdentifiers, expected)
    }

    func testStandardRegistryDeclaresArgumentShapes() {
        let registry = CommandRegistry.standard()
        XCTAssertEqual(registry.definition(for: .appOpen)?.argumentKind, .application)
        XCTAssertEqual(registry.definition(for: .appQuit)?.argumentKind, .application)
        XCTAssertEqual(registry.definition(for: .appHide)?.argumentKind, .application)
        XCTAssertEqual(registry.definition(for: .appSwitch)?.argumentKind, .application)
        XCTAssertEqual(registry.definition(for: .dictationModeFormal)?.argumentKind, .writingMode)
        XCTAssertEqual(registry.definition(for: .dictationModeStandard)?.argumentKind, .writingMode)
        // Spelled out: a bare `.none` here would resolve to `Optional.none`
        // and assert the definition is missing rather than argument-free.
        XCTAssertEqual(registry.definition(for: .settingsOpen)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .historyOpen)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .clipboardCopyLast)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .clipboardClear)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .speechModelReload)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .browserOpenURL)?.argumentKind, .url)
        XCTAssertEqual(registry.definition(for: .browserSearch)?.argumentKind, .search)
        XCTAssertEqual(registry.definition(for: .whatsAppOpenChat)?.argumentKind, .whatsAppChat)
        XCTAssertEqual(registry.definition(for: .whatsAppSendMessage)?.argumentKind, .whatsAppMessage)
        XCTAssertEqual(registry.definition(for: .calendarOpen)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .calendarCreateEvent)?.argumentKind, .calendarEvent)
        XCTAssertEqual(registry.definition(for: .calendarListEvents)?.argumentKind, .calendarQuery)
        XCTAssertEqual(registry.definition(for: .calendarDeleteEvent)?.argumentKind, .calendarDelete)
        XCTAssertEqual(registry.definition(for: .remindersOpen)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .remindersCreate)?.argumentKind, .reminder)
        XCTAssertEqual(registry.definition(for: .remindersList)?.argumentKind, .reminderQuery)
        XCTAssertEqual(registry.definition(for: .remindersComplete)?.argumentKind, .reminderComplete)
        XCTAssertEqual(registry.definition(for: .remindersDelete)?.argumentKind, .reminderDelete)
        XCTAssertEqual(registry.definition(for: .notesOpen)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .notesCreate)?.argumentKind, .note)
        XCTAssertEqual(registry.definition(for: .notesFind)?.argumentKind, .noteFind)
        XCTAssertEqual(registry.definition(for: .notesOpenNote)?.argumentKind, .noteOpen)
        XCTAssertEqual(registry.definition(for: .finderOpenLocation)?.argumentKind, .finderLocation)
        XCTAssertEqual(registry.definition(for: .finderFindFiles)?.argumentKind, .fileSearch)
        XCTAssertEqual(registry.definition(for: .contextOpen)?.argumentKind, .contextOpen)
        XCTAssertEqual(registry.definition(for: .contextMessage)?.argumentKind, .contextMessage)
        XCTAssertEqual(registry.definition(for: .contextCheck)?.argumentKind, .contextCheck)
        XCTAssertEqual(registry.definition(for: .contactsFind)?.argumentKind, .contactsQuery)
        XCTAssertEqual(registry.definition(for: .contactsShow)?.argumentKind, .contactsShow)
        XCTAssertEqual(registry.definition(for: .mailOpen)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .mailCompose)?.argumentKind, .mailCompose)
        XCTAssertEqual(registry.definition(for: .clipboardInspect)?.argumentKind, .clipboardInspect)
        // System Information
        XCTAssertEqual(registry.definition(for: .systemBattery)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemMacOSVersion)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemTime)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemDate)?.argumentKind, CommandArgumentKind.none)
        // System Audio
        XCTAssertEqual(registry.definition(for: .systemVolumeUp)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemVolumeDown)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemVolumeSet)?.argumentKind, .systemVolumeSet)
        XCTAssertEqual(registry.definition(for: .systemVolumeMute)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemVolumeUnmute)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemVolumeGet)?.argumentKind, CommandArgumentKind.none)
        // System Power & Session
        XCTAssertEqual(registry.definition(for: .systemSleep)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemLock)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemLogout)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemRestart)?.argumentKind, CommandArgumentKind.none)
        XCTAssertEqual(registry.definition(for: .systemShutdown)?.argumentKind, CommandArgumentKind.none)
    }

    /// Quitting an application and clearing the pasteboard can both lose work
    /// the app never saw. Recording them as sensitive is what makes them
    /// visible if a confirmation surface is added later.
    func testCommandsThatCanLoseWorkAreNotMarkedSafe() {
        let registry = CommandRegistry.standard()
        XCTAssertEqual(registry.definition(for: .appQuit)?.risk, .sensitive)
        XCTAssertEqual(registry.definition(for: .clipboardClear)?.risk, .sensitive)
        XCTAssertEqual(registry.definition(for: .whatsAppSendMessage)?.risk, .sensitive)
    }

    /// Destructive commands are explicitly marked as such.
    func testDestructiveCommandsAreMarked() {
        let registry = CommandRegistry.standard()
        XCTAssertEqual(registry.definition(for: .calendarDeleteEvent)?.risk, .destructive)
        XCTAssertEqual(registry.definition(for: .remindersDelete)?.risk, .destructive)
        XCTAssertEqual(registry.definition(for: .finderTrash)?.risk, .destructive)
        XCTAssertEqual(registry.definition(for: .finderRename)?.risk, .destructive)
        XCTAssertEqual(registry.definition(for: .systemLogout)?.risk, .destructive)
        XCTAssertEqual(registry.definition(for: .systemRestart)?.risk, .destructive)
        XCTAssertEqual(registry.definition(for: .systemShutdown)?.risk, .destructive)
        // All other commands should not be destructive
        let destructiveIdentifiers: Set<CommandIdentifier> = [
            .calendarDeleteEvent, .remindersDelete, .finderTrash, .finderRename,
            .systemLogout, .systemRestart, .systemShutdown
        ]
        for identifier in registry.registeredIdentifiers {
            guard let definition = registry.definition(for: identifier) else {
                return XCTFail("missing definition for \(identifier.rawValue)")
            }
            if !destructiveIdentifiers.contains(identifier) {
                XCTAssertNotEqual(definition.risk, .destructive, "\(identifier.rawValue) should not be destructive")
            }
        }
    }

    func testWhatsAppSendMessageRequiresMandatoryConfirmation() {
        let registry = CommandRegistry.standard()
        let definition = registry.definition(for: .whatsAppSendMessage)
        XCTAssertEqual(definition?.confirmation, .mandatory)
        XCTAssertEqual(definition?.risk, .sensitive)
    }

    func testAppQuitRequiresMandatoryConfirmation() {
        let registry = CommandRegistry.standard()
        let definition = registry.definition(for: .appQuit)
        XCTAssertEqual(definition?.confirmation, .mandatory)
        XCTAssertEqual(definition?.risk, .sensitive)
    }

    func testClipboardClearRequiresMandatoryConfirmation() {
        let registry = CommandRegistry.standard()
        let definition = registry.definition(for: .clipboardClear)
        XCTAssertEqual(definition?.confirmation, .mandatory)
        XCTAssertEqual(definition?.risk, .sensitive)
    }
}
