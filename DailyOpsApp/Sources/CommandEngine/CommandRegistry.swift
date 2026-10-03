import Foundation

/// The set of commands the engine knows about. Injected rather than global so
/// tests can register a narrow set and assert on lookups without touching the
/// real command table.
final class CommandRegistry {
    private var definitions: [CommandIdentifier: CommandDefinition]

    init(definitions: [CommandDefinition] = []) {
        self.definitions = Dictionary(
            definitions.map { ($0.identifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Registering an identifier twice replaces the earlier definition, so a
    /// caller can override a default entry without removing it first.
    func register(_ definition: CommandDefinition) {
        definitions[definition.identifier] = definition
    }

    func definition(for identifier: CommandIdentifier) -> CommandDefinition? {
        definitions[identifier]
    }

    var registeredIdentifiers: Set<CommandIdentifier> {
        Set(definitions.keys)
    }

    /// The commands shipped with the app.
    static func standard() -> CommandRegistry {
        CommandRegistry(definitions: [
            CommandDefinition(
                identifier: .appOpen,
                name: "Open Application",
                risk: .safe,
                confirmation: .none,
                argumentKind: .application
            ),
            // Quitting can discard unsaved work in the target application, so
            // it is recorded as sensitive and requires mandatory confirmation.
            CommandDefinition(
                identifier: .appQuit,
                name: "Quit Application",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .application
            ),
            CommandDefinition(
                identifier: .appHide,
                name: "Hide Application",
                risk: .safe,
                confirmation: .none,
                argumentKind: .application
            ),
            CommandDefinition(
                identifier: .settingsOpen,
                name: "Open Settings",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .historyOpen,
                name: "Open History",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .dictationModeFormal,
                name: "Switch to Formal Mode",
                risk: .safe,
                confirmation: .none,
                argumentKind: .writingMode
            ),
            CommandDefinition(
                identifier: .dictationModeStandard,
                name: "Switch to Standard Mode",
                risk: .safe,
                confirmation: .none,
                argumentKind: .writingMode
            ),
            CommandDefinition(
                identifier: .clipboardCopyLast,
                name: "Copy Last Dictation",
                risk: .safe,
                confirmation: .none
            ),
            // Clearing the pasteboard throws away content the engine never saw
            // and cannot restore. Sensitive and requires mandatory confirmation.
            CommandDefinition(
                identifier: .clipboardClear,
                name: "Clear Clipboard",
                risk: .sensitive,
                confirmation: .mandatory
            ),
            CommandDefinition(
                identifier: .speechModelReload,
                name: "Reload Speech Model",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .browserOpenURL,
                name: "Open Website",
                risk: .safe,
                confirmation: .none,
                argumentKind: .url
            ),
            CommandDefinition(
                identifier: .browserSearch,
                name: "Search Web",
                risk: .safe,
                confirmation: .none,
                argumentKind: .search
            ),
            CommandDefinition(
                identifier: .browserOpenDefault,
                name: "Open Default Browser",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .browserOpenPrivate,
                name: "Open Private Browsing",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .whatsAppOpenChat,
                name: "Open WhatsApp Chat",
                risk: .safe,
                confirmation: .none,
                argumentKind: .whatsAppChat
            ),
            CommandDefinition(
                identifier: .whatsAppSendMessage,
                name: "Send WhatsApp Message",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .whatsAppMessage
            ),
            // Calendar
            CommandDefinition(
                identifier: .calendarOpen,
                name: "Open Calendar",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .calendarListEvents,
                name: "Show Calendar Events",
                risk: .safe,
                confirmation: .none,
                argumentKind: .calendarQuery
            ),
            CommandDefinition(
                identifier: .calendarCreateEvent,
                name: "Create Calendar Event",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .calendarEvent
            ),
            // Reminders
            CommandDefinition(
                identifier: .remindersOpen,
                name: "Open Reminders",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .remindersList,
                name: "Show Reminders",
                risk: .safe,
                confirmation: .none,
                argumentKind: .reminderQuery
            ),
            CommandDefinition(
                identifier: .remindersCreate,
                name: "Create Reminder",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .reminder
            ),
            // Notes
            CommandDefinition(
                identifier: .notesOpen,
                name: "Open Notes",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .notesCreate,
                name: "Create Note",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .note
            ),
            // Finder & File Navigation
            CommandDefinition(
                identifier: .finderOpenLocation,
                name: "Open Finder Location",
                risk: .safe,
                confirmation: .none,
                argumentKind: .finderLocation
            ),
            CommandDefinition(
                identifier: .finderFindFiles,
                name: "Find Files",
                risk: .safe,
                confirmation: .none,
                argumentKind: .fileSearch
            ),
            // App Control
            CommandDefinition(
                identifier: .appSwitch,
                name: "Switch Application",
                risk: .safe,
                confirmation: .none,
                argumentKind: .application
            ),
            // Calendar Extended
            CommandDefinition(
                identifier: .calendarDeleteEvent,
                name: "Delete Calendar Event",
                risk: .destructive,
                confirmation: .mandatory,
                argumentKind: .calendarDelete
            ),
            // Reminders Extended
            CommandDefinition(
                identifier: .remindersComplete,
                name: "Complete Reminder",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .reminderComplete
            ),
            CommandDefinition(
                identifier: .remindersDelete,
                name: "Delete Reminder",
                risk: .destructive,
                confirmation: .mandatory,
                argumentKind: .reminderDelete
            ),
            // Notes Extended
            CommandDefinition(
                identifier: .notesFind,
                name: "Find Notes",
                risk: .safe,
                confirmation: .none,
                argumentKind: .noteFind
            ),
            CommandDefinition(
                identifier: .notesOpenNote,
                name: "Open Note",
                risk: .safe,
                confirmation: .none,
                argumentKind: .noteOpen
            ),
            // Context Commands
            CommandDefinition(
                identifier: .contextOpen,
                name: "Open from Context",
                risk: .safe,
                confirmation: .none,
                argumentKind: .contextOpen
            ),
            CommandDefinition(
                identifier: .contextMessage,
                name: "Message from Context",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .contextMessage
            ),
            CommandDefinition(
                identifier: .contextCheck,
                name: "Check from Context",
                risk: .safe,
                confirmation: .none,
                argumentKind: .contextCheck
            ),
            // Contacts
            CommandDefinition(
                identifier: .contactsFind,
                name: "Find Contacts",
                risk: .safe,
                confirmation: .none,
                argumentKind: .contactsQuery
            ),
            CommandDefinition(
                identifier: .contactsShow,
                name: "Show Contact",
                risk: .safe,
                confirmation: .none,
                argumentKind: .contactsShow
            ),
            // Mail
            CommandDefinition(
                identifier: .mailOpen,
                name: "Open Mail",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .mailCompose,
                name: "Compose Email",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .mailCompose
            ),
            // Finder Extended
            CommandDefinition(
                identifier: .finderCreateFolder,
                name: "Create Folder",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .finderCreateFolder
            ),
            CommandDefinition(
                identifier: .finderCreateFile,
                name: "Create File",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .finderCreateFile
            ),
            CommandDefinition(
                identifier: .finderReveal,
                name: "Reveal in Finder",
                risk: .safe,
                confirmation: .none,
                argumentKind: .finderReveal
            ),
            CommandDefinition(
                identifier: .finderTrash,
                name: "Move to Trash",
                risk: .destructive,
                confirmation: .mandatory,
                argumentKind: .finderTrash
            ),
            CommandDefinition(
                identifier: .finderRename,
                name: "Rename File/Folder",
                risk: .destructive,
                confirmation: .mandatory,
                argumentKind: .finderRename
            ),
            CommandDefinition(
                identifier: .finderDuplicate,
                name: "Duplicate File/Folder",
                risk: .sensitive,
                confirmation: .mandatory,
                argumentKind: .finderDuplicate
            ),
            CommandDefinition(
                identifier: .clipboardInspect,
                name: "Inspect Clipboard",
                risk: .safe,
                confirmation: .none,
                argumentKind: .clipboardInspect
            ),
            // System Information
            CommandDefinition(
                identifier: .systemBattery,
                name: "Battery Status",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemMacOSVersion,
                name: "macOS Version",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemTime,
                name: "Current Time",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemDate,
                name: "Current Date",
                risk: .safe,
                confirmation: .none
            ),
            // System Audio
            CommandDefinition(
                identifier: .systemVolumeUp,
                name: "Volume Up",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemVolumeDown,
                name: "Volume Down",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemVolumeSet,
                name: "Set Volume",
                risk: .safe,
                confirmation: .none,
                argumentKind: .systemVolumeSet
            ),
            CommandDefinition(
                identifier: .systemVolumeMute,
                name: "Mute Volume",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemVolumeUnmute,
                name: "Unmute Volume",
                risk: .safe,
                confirmation: .none
            ),
            CommandDefinition(
                identifier: .systemVolumeGet,
                name: "Get Volume",
                risk: .safe,
                confirmation: .none
            ),
            // System Power & Session
            CommandDefinition(
                identifier: .systemSleep,
                name: "Sleep",
                risk: .sensitive,
                confirmation: .mandatory
            ),
            CommandDefinition(
                identifier: .systemLock,
                name: "Lock Screen",
                risk: .sensitive,
                confirmation: .mandatory
            ),
            CommandDefinition(
                identifier: .systemLogout,
                name: "Log Out",
                risk: .destructive,
                confirmation: .mandatory
            ),
            CommandDefinition(
                identifier: .systemRestart,
                name: "Restart",
                risk: .destructive,
                confirmation: .mandatory
            ),
            CommandDefinition(
                identifier: .systemShutdown,
                name: "Shut Down",
                risk: .destructive,
                confirmation: .mandatory
            ),
        ])
    }
}
