import Foundation

/// Stable, machine-facing command identity. User-facing phrasing changes with
/// wording and localisation; these values do not, so they are what the
/// registry, validator and router key off.
struct CommandIdentifier: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CommandIdentifier {
    static let appOpen = CommandIdentifier(rawValue: "app.open")
    static let appQuit = CommandIdentifier(rawValue: "app.quit")
    static let appHide = CommandIdentifier(rawValue: "app.hide")
    static let settingsOpen = CommandIdentifier(rawValue: "settings.open")
    static let historyOpen = CommandIdentifier(rawValue: "history.open")
    static let dictationModeFormal = CommandIdentifier(rawValue: "dictation.mode.formal")
    static let dictationModeStandard = CommandIdentifier(rawValue: "dictation.mode.standard")
    static let clipboardCopyLast = CommandIdentifier(rawValue: "clipboard.copyLast")
    static let clipboardClear = CommandIdentifier(rawValue: "clipboard.clear")
    static let speechModelReload = CommandIdentifier(rawValue: "speech.model.reload")
    static let browserOpenURL = CommandIdentifier(rawValue: "browser.openURL")
    static let browserSearch = CommandIdentifier(rawValue: "browser.search")
    static let browserOpenDefault = CommandIdentifier(rawValue: "browser.openDefault")
    static let browserOpenPrivate = CommandIdentifier(rawValue: "browser.openPrivate")
    static let whatsAppOpenChat = CommandIdentifier(rawValue: "whatsapp.openChat")
    static let whatsAppSendMessage = CommandIdentifier(rawValue: "whatsapp.sendMessage")

    // Calendar
    static let calendarOpen = CommandIdentifier(rawValue: "calendar.open")
    static let calendarListEvents = CommandIdentifier(rawValue: "calendar.listEvents")
    static let calendarCreateEvent = CommandIdentifier(rawValue: "calendar.createEvent")

    // Reminders
    static let remindersOpen = CommandIdentifier(rawValue: "reminders.open")
    static let remindersList = CommandIdentifier(rawValue: "reminders.list")
    static let remindersCreate = CommandIdentifier(rawValue: "reminders.create")

    // Notes
    static let notesOpen = CommandIdentifier(rawValue: "notes.open")
    static let notesCreate = CommandIdentifier(rawValue: "notes.create")

    // Finder & File Navigation
    static let finderOpenLocation = CommandIdentifier(rawValue: "finder.openLocation")
    static let finderFindFiles = CommandIdentifier(rawValue: "finder.findFiles")

    // App Control
    static let appSwitch = CommandIdentifier(rawValue: "app.switch")

    // Calendar Extended
    static let calendarDeleteEvent = CommandIdentifier(rawValue: "calendar.deleteEvent")

    // Reminders Extended
    static let remindersComplete = CommandIdentifier(rawValue: "reminders.complete")
    static let remindersDelete = CommandIdentifier(rawValue: "reminders.delete")

    // Notes Extended
    static let notesFind = CommandIdentifier(rawValue: "notes.find")
    static let notesOpenNote = CommandIdentifier(rawValue: "notes.openNote")

    // Context Commands
    static let contextOpen = CommandIdentifier(rawValue: "context.open")
    static let contextMessage = CommandIdentifier(rawValue: "context.message")
    static let contextCheck = CommandIdentifier(rawValue: "context.check")

    // Contacts
    static let contactsFind = CommandIdentifier(rawValue: "contacts.find")
    static let contactsShow = CommandIdentifier(rawValue: "contacts.show")

    // Mail
    static let mailOpen = CommandIdentifier(rawValue: "mail.open")
    static let mailCompose = CommandIdentifier(rawValue: "mail.compose")

    // Finder Extended
    static let finderCreateFolder = CommandIdentifier(rawValue: "finder.createFolder")
    static let finderCreateFile = CommandIdentifier(rawValue: "finder.createFile")
    static let finderReveal = CommandIdentifier(rawValue: "finder.reveal")
    static let finderTrash = CommandIdentifier(rawValue: "finder.trash")
    static let finderRename = CommandIdentifier(rawValue: "finder.rename")
    static let finderDuplicate = CommandIdentifier(rawValue: "finder.duplicate")

    // System & Clipboard
    static let clipboardInspect = CommandIdentifier(rawValue: "clipboard.inspect")

    // System Information
    static let systemBattery = CommandIdentifier(rawValue: "system.battery")
    static let systemMacOSVersion = CommandIdentifier(rawValue: "system.macOSVersion")
    static let systemTime = CommandIdentifier(rawValue: "system.time")
    static let systemDate = CommandIdentifier(rawValue: "system.date")

    // System Audio
    static let systemVolumeUp = CommandIdentifier(rawValue: "system.volumeUp")
    static let systemVolumeDown = CommandIdentifier(rawValue: "system.volumeDown")
    static let systemVolumeSet = CommandIdentifier(rawValue: "system.volumeSet")
    static let systemVolumeMute = CommandIdentifier(rawValue: "system.volumeMute")
    static let systemVolumeUnmute = CommandIdentifier(rawValue: "system.volumeUnmute")
    static let systemVolumeGet = CommandIdentifier(rawValue: "system.volumeGet")

    // System Power & Session
    static let systemSleep = CommandIdentifier(rawValue: "system.sleep")
    static let systemLock = CommandIdentifier(rawValue: "system.lock")
    static let systemLogout = CommandIdentifier(rawValue: "system.logout")
    static let systemRestart = CommandIdentifier(rawValue: "system.restart")
    static let systemShutdown = CommandIdentifier(rawValue: "system.shutdown")
}

/// How much a command can affect the user's system or data. The registry
/// declares it; the validator is what enforces it.
enum CommandRisk: String, Codable, Sendable {
    /// Reversible, no data loss: opening a window, switching a mode.
    case safe
    /// Touches user data or running applications; worth confirming.
    case sensitive
    /// Irreversible or system-altering; must be confirmed before it runs.
    case destructive
}

/// Whether a command needs explicit user approval before execution.
enum ConfirmationRequirement: String, Codable, Sendable {
    /// Runs immediately.
    case none
    /// Runs immediately unless its risk level demands otherwise.
    case optional
    /// Always requires approval, regardless of risk level.
    case mandatory
}

/// Search engine or content provider to query.
enum SearchProvider: String, Codable, Sendable {
    case google
    case youtube

    var displayName: String {
        switch self {
        case .google: "Google"
        case .youtube: "YouTube"
        }
    }
}

/// Web search request containing the target provider and query string.
struct SearchRequest: Equatable, Codable, Sendable {
    let query: String
    let provider: SearchProvider

    init(query: String, provider: SearchProvider = .google) {
        self.query = query
        self.provider = provider
    }
}

/// Day target for calendar queries and reminders.
enum CalendarDayTarget: String, Codable, Sendable {
    case today
    case tomorrow
    case specificDate
    case next
    case thisWeek
    case afternoon
}

/// Calendar events list query.
struct CalendarQuery: Equatable, Codable, Sendable {
    let day: CalendarDayTarget
    let date: Date?

    init(day: CalendarDayTarget = .today, date: Date? = nil) {
        self.day = day
        self.date = date
    }
}

/// Request to create a new calendar event.
struct CalendarEventRequest: Equatable, Codable, Sendable {
    let title: String
    let date: Date
    let startTime: Date?
    let duration: TimeInterval?

    init(title: String, date: Date, startTime: Date? = nil, duration: TimeInterval? = nil) {
        self.title = title
        self.date = date
        self.startTime = startTime
        self.duration = duration
    }
}

/// Reminders list query.
struct ReminderQuery: Equatable, Codable, Sendable {
    let dueDay: CalendarDayTarget?

    init(dueDay: CalendarDayTarget? = nil) {
        self.dueDay = dueDay
    }
}

/// Request to create a new reminder.
struct ReminderRequest: Equatable, Codable, Sendable {
    let title: String
    let dueDate: Date?
    let dueTime: Date?

    init(title: String, dueDate: Date? = nil, dueTime: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.dueTime = dueTime
    }
}

/// Request to create or append a note.
struct NoteRequest: Equatable, Codable, Sendable {
    let title: String
    let body: String?

    init(title: String, body: String? = nil) {
        self.title = title
        self.body = body
    }
}

/// Target location for Finder navigation.
enum FinderLocationKind: String, Codable, Sendable {
    case downloads
    case desktop
    case documents
    case applications
    case home
    case finder
    case custom
    case pictures
}

/// Finder location navigation target.
struct FinderLocationTarget: Equatable, Codable, Sendable {
    let location: FinderLocationKind
    let customName: String?

    init(location: FinderLocationKind, customName: String? = nil) {
        self.location = location
        self.customName = customName
    }
}

/// Search directory scope for file searches.
enum FileSearchScope: String, Codable, Sendable {
    case downloads
    case desktop
    case documents
    case home
    case pictures
}

/// Filter condition for safe file queries.
enum FileSearchFilter: String, Codable, Sendable {
    case all
    case screenshots
    case pdfs
    case modifiedToday
    case modifiedYesterday
    case modifiedThisWeek
}

/// Request to search files locally and safely.
struct FileSearchRequest: Equatable, Codable, Sendable {
    let scope: FileSearchScope
    let filter: FileSearchFilter
    let query: String?

    init(scope: FileSearchScope = .downloads, filter: FileSearchFilter = .all, query: String? = nil) {
        self.scope = scope
        self.filter = filter
        self.query = query
    }
}

/// Request to delete a calendar event.
struct CalendarEventDeleteRequest: Equatable, Codable, Sendable {
    let title: String
    let date: Date?
    let startTime: Date?

    init(title: String, date: Date? = nil, startTime: Date? = nil) {
        self.title = title
        self.date = date
        self.startTime = startTime
    }
}

/// Request to complete a reminder.
struct ReminderCompleteRequest: Equatable, Codable, Sendable {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// Request to delete a reminder.
struct ReminderDeleteRequest: Equatable, Codable, Sendable {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// Request to find a note by topic.
struct NoteFindRequest: Equatable, Codable, Sendable {
    let query: String

    init(query: String) {
        self.query = query
    }
}

/// Request to open a specific note by topic.
struct NoteOpenRequest: Equatable, Codable, Sendable {
    let query: String

    init(query: String) {
        self.query = query
    }
}

/// Context-aware open request (e.g., "open it" after finding a file).
struct ContextOpenRequest: Equatable, Codable, Sendable {
    let targetKind: ContextTargetKind

    init(targetKind: ContextTargetKind) {
        self.targetKind = targetKind
    }
}

/// Context-aware message request (e.g., "message him" after resolving a contact).
struct ContextMessageRequest: Equatable, Codable, Sendable {
    let message: String

    init(message: String) {
        self.message = message
    }
}

/// Context-aware check request (e.g., "check my next meeting").
struct ContextCheckRequest: Equatable, Codable, Sendable {
    let targetKind: ContextTargetKind

    init(targetKind: ContextTargetKind) {
        self.targetKind = targetKind
    }
}

/// Request to compose a new email.
struct MailComposeRequest: Equatable, Codable, Sendable {
    let to: String?
    let subject: String?
    let body: String?

    init(to: String? = nil, subject: String? = nil, body: String? = nil) {
        self.to = to
        self.subject = subject
        self.body = body
    }
}

/// Request to create a new folder.
struct FinderCreateFolderRequest: Equatable, Codable, Sendable {
    let folderName: String
    let parentPath: String?

    init(folderName: String, parentPath: String? = nil) {
        self.folderName = folderName
        self.parentPath = parentPath
    }
}

/// Request to create a new file.
struct FinderCreateFileRequest: Equatable, Codable, Sendable {
    let fileName: String
    let parentPath: String?

    init(fileName: String, parentPath: String? = nil) {
        self.fileName = fileName
        self.parentPath = parentPath
    }
}

/// Request to reveal a file/folder in Finder.
struct FinderRevealRequest: Equatable, Codable, Sendable {
    let path: String

    init(path: String) {
        self.path = path
    }
}

/// Request to move a file/folder to Trash.
struct FinderTrashRequest: Equatable, Codable, Sendable {
    let path: String

    init(path: String) {
        self.path = path
    }
}

/// Request to rename a file/folder.
struct FinderRenameRequest: Equatable, Codable, Sendable {
    let oldPath: String
    let newName: String

    init(oldPath: String, newName: String) {
        self.oldPath = oldPath
        self.newName = newName
    }
}

/// Request to duplicate a file/folder.
struct FinderDuplicateRequest: Equatable, Codable, Sendable {
    let path: String

    init(path: String) {
        self.path = path
    }
}

/// Types of context targets that can be resolved from previous commands.
enum ContextTargetKind: String, Codable, Sendable {
    case file
    case calendarEvent
    case reminder
    case contact
    case note
    case application
}

/// Query for finding/searching contacts.
struct ContactQuery: Equatable, Codable, Sendable {
    let query: String

    init(query: String) {
        self.query = query
    }
}

/// Request to show contact information.
struct ContactShowRequest: Equatable, Codable, Sendable {
    let query: String

    init(query: String) {
        self.query = query
    }
}

/// Command arguments, modelled as a closed set of cases rather than a string
/// dictionary so the compiler checks every payload and no executor has to
/// guess at key names or parse values back out of strings.
enum CommandArguments: Equatable, Codable, Sendable {
    /// The command takes no arguments.
    case none
    /// An application the user named, already resolved against the
    /// installed-application index by the parser.
    case application(ApplicationReference)
    /// A dictation writing mode.
    case writingMode(WritingMode)
    /// A web URL to open.
    case url(URL)
    /// A web search query and provider.
    case search(SearchRequest)
    /// A WhatsApp chat opening target.
    case whatsAppChat(WhatsAppChatTarget)
    /// A WhatsApp message sending target.
    case whatsAppMessage(WhatsAppMessageTarget)
    /// A Calendar query for viewing events.
    case calendarQuery(CalendarQuery)
    /// A Calendar event creation request.
    case calendarEvent(CalendarEventRequest)
    /// A Reminders query for viewing reminders.
    case reminderQuery(ReminderQuery)
    /// A Reminder creation request.
    case reminder(ReminderRequest)
    /// A Note creation request.
    case note(NoteRequest)
    /// A Finder location target to open.
    case finderLocation(FinderLocationTarget)
    /// A local file search request.
    case fileSearch(FileSearchRequest)
    /// A Calendar event deletion request.
    case calendarDelete(CalendarEventDeleteRequest)
    /// A Reminder completion request.
    case reminderComplete(ReminderCompleteRequest)
    /// A Reminder deletion request.
    case reminderDelete(ReminderDeleteRequest)
    /// A Notes find request.
    case noteFind(NoteFindRequest)
    /// A Notes open specific note request.
    case noteOpen(NoteOpenRequest)
    /// A context-aware open command.
    case contextOpen(ContextOpenRequest)
    /// A context-aware message command.
    case contextMessage(ContextMessageRequest)
    /// A context-aware check command.
    case contextCheck(ContextCheckRequest)
    /// A contacts find/search query.
    case contactsQuery(ContactQuery)
    /// A contacts show request.
    case contactsShow(ContactShowRequest)
    /// A mail compose request.
    case mailCompose(MailComposeRequest)
    /// A Finder create folder request.
    case finderCreateFolder(FinderCreateFolderRequest)
    /// A Finder create file request.
    case finderCreateFile(FinderCreateFileRequest)
    /// A Finder reveal request.
    case finderReveal(FinderRevealRequest)
    /// A Finder trash request.
    case finderTrash(FinderTrashRequest)
    /// A Finder rename request.
    case finderRename(FinderRenameRequest)
    /// A Finder duplicate request.
    case finderDuplicate(FinderDuplicateRequest)
    /// A clipboard inspect request.
    case clipboardInspect
    /// A system battery status request.
    case systemBattery
    /// A system macOS version request.
    case systemMacOSVersion
    /// A system time request.
    case systemTime
    /// A system date request.
    case systemDate
    /// A system volume up request.
    case systemVolumeUp
    /// A system volume down request.
    case systemVolumeDown
    /// A system volume set request with percentage (0-100).
    case systemVolumeSet(Int)
    /// A system volume mute request.
    case systemVolumeMute
    /// A system volume unmute request.
    case systemVolumeUnmute
    /// A system volume get request.
    case systemVolumeGet
    /// A system sleep request.
    case systemSleep
    /// A system lock screen request.
    case systemLock
    /// A system logout request.
    case systemLogout
    /// A system restart request.
    case systemRestart
    /// A system shutdown request.
    case systemShutdown
}

/// A resolved reference to an application on disk. Parsing resolves the
/// spoken name to a concrete bundle up front, so an intent can never reach an
/// executor carrying a name that does not exist.
struct ApplicationReference: Equatable, Codable, Sendable {
    /// Name suitable for showing back to the user.
    let displayName: String
    /// Location of the application bundle, when known. Absent for commands
    /// that act on an already-running process.
    let bundleURL: URL?

    init(displayName: String, bundleURL: URL? = nil) {
        self.displayName = displayName
        self.bundleURL = bundleURL
    }
}

/// What the user asked for: a stable identifier plus its structured
/// arguments. This is the only shape a parser is allowed to produce, which is
/// what keeps interpretation separate from execution.
struct CommandIntent: Equatable, Codable, Sendable {
    let identifier: CommandIdentifier
    let arguments: CommandArguments

    init(identifier: CommandIdentifier, arguments: CommandArguments = .none) {
        self.identifier = identifier
        self.arguments = arguments
    }
}

/// One unit of work inside a plan.
struct CommandStep: Equatable, Codable, Sendable {
    let intent: CommandIntent

    init(intent: CommandIntent) {
        self.intent = intent
    }
}

/// An ordered set of steps. The type is deliberately multi-step so the model
/// does not need reshaping later, but nothing in the current pipeline executes
/// more than the first step — see `CommandRouter`.
struct CommandPlan: Equatable, Codable, Sendable {
    let steps: [CommandStep]

    init(steps: [CommandStep]) {
        self.steps = steps
    }

    init(intent: CommandIntent) {
        self.init(steps: [CommandStep(intent: intent)])
    }

    var isMultiStep: Bool { steps.count > 1 }
}

/// Environment a command was issued in. Passed in rather than read from global
/// state so tests can describe any situation they need.
struct CommandContext: Sendable {
    /// Application that had focus when the user spoke.
    let frontmostApplicationName: String
    /// When the transcript was produced.
    let timestamp: Date
    /// Whether command recognition is turned on at all.
    let isCommandModeEnabled: Bool

    /// Resolved file from a previous find command, for "open it" context.
    let resolvedFileURL: URL?
    /// Resolved file name from a previous find command.
    let resolvedFileName: String?
    /// Resolved calendar event from a previous query.
    let resolvedCalendarEventTitle: String?
    let resolvedCalendarEventDate: Date?
    /// Resolved reminder from a previous query.
    let resolvedReminderTitle: String?
    /// Resolved contact from a previous WhatsApp command.
    let resolvedContactName: String?
    let resolvedContactPhone: String?
    /// Resolved note from a previous query.
    let resolvedNoteTitle: String?

    init(
        frontmostApplicationName: String,
        timestamp: Date,
        isCommandModeEnabled: Bool,
        resolvedFileURL: URL? = nil,
        resolvedFileName: String? = nil,
        resolvedCalendarEventTitle: String? = nil,
        resolvedCalendarEventDate: Date? = nil,
        resolvedReminderTitle: String? = nil,
        resolvedContactName: String? = nil,
        resolvedContactPhone: String? = nil,
        resolvedNoteTitle: String? = nil
    ) {
        self.frontmostApplicationName = frontmostApplicationName
        self.timestamp = timestamp
        self.isCommandModeEnabled = isCommandModeEnabled
        self.resolvedFileURL = resolvedFileURL
        self.resolvedFileName = resolvedFileName
        self.resolvedCalendarEventTitle = resolvedCalendarEventTitle
        self.resolvedCalendarEventDate = resolvedCalendarEventDate
        self.resolvedReminderTitle = resolvedReminderTitle
        self.resolvedContactName = resolvedContactName
        self.resolvedContactPhone = resolvedContactPhone
        self.resolvedNoteTitle = resolvedNoteTitle
    }
}

/// Outcome of handing a transcript to the engine.
enum CommandResult: Equatable {
    /// The command ran. `message` is short user-facing feedback.
    case success(message: String)
    /// The transcript is not a command. The caller must fall back to normal
    /// dictation and must not discard the transcript.
    case ignored
    /// The command was recognised but could not run.
    case failure(message: String)
    /// Recognised, but the user has to approve it first. The plan is returned
    /// so it can be run unchanged once approved.
    case confirmationRequired(plan: CommandPlan, message: String)
}

/// Reasons a command can be refused before any side effect happens.
enum CommandValidationError: Error, Equatable {
    /// No registry entry for the identifier.
    case unknownCommand(CommandIdentifier)
    /// Arguments do not match what the command declares it needs.
    case invalidArguments(CommandIdentifier)
    /// The plan is empty.
    case emptyPlan
    /// The plan needs step-by-step execution, which this stage does not do.
    case multiStepNotSupported
    /// Multiple contacts matched the query.
    case ambiguousRecipient(query: String, matches: [String])
    /// No contact was found for the query.
    case recipientNotFound(query: String)
    /// Contacts access or phone number is unavailable.
    case contactsUnavailable(reason: String)
}

/// What a command needs to be handed in order to run.
enum CommandArgumentKind: String, Sendable {
    case none
    case application
    case writingMode
    case url
    case search
    case whatsAppChat
    case whatsAppMessage
    case calendarQuery
    case calendarEvent
    case reminderQuery
    case reminder
    case note
    case finderLocation
    case fileSearch
    case calendarDelete
    case reminderComplete
    case reminderDelete
    case noteFind
    case noteOpen
    case contextOpen
    case contextMessage
    case contextCheck
    case contactsQuery
    case contactsShow
    case mailCompose
    case finderCreateFolder
    case finderCreateFile
    case finderReveal
    case finderTrash
    case finderRename
    case finderDuplicate
    case clipboardInspect
    case systemBattery
    case systemMacOSVersion
    case systemTime
    case systemDate
    case systemVolumeUp
    case systemVolumeDown
    case systemVolumeSet
    case systemVolumeMute
    case systemVolumeUnmute
    case systemVolumeGet
    case systemSleep
    case systemLock
    case systemLogout
    case systemRestart
    case systemShutdown
}

/// Registry metadata: identity, risk, confirmation policy and argument shape.
struct CommandDefinition: Equatable, Sendable {
    let identifier: CommandIdentifier
    /// Human-readable name for UI and diagnostics, never used as identity.
    let name: String
    let risk: CommandRisk
    let confirmation: ConfirmationRequirement
    let argumentKind: CommandArgumentKind

    init(
        identifier: CommandIdentifier,
        name: String,
        risk: CommandRisk,
        confirmation: ConfirmationRequirement,
        argumentKind: CommandArgumentKind = .none
    ) {
        self.identifier = identifier
        self.name = name
        self.risk = risk
        self.confirmation = confirmation
        self.argumentKind = argumentKind
    }
}

extension CommandArguments {
    /// The argument shape actually present, checked against the definition.
    var kind: CommandArgumentKind {
        switch self {
        case .none: .none
        case .application: .application
        case .writingMode: .writingMode
        case .url: .url
        case .search: .search
        case .whatsAppChat: .whatsAppChat
        case .whatsAppMessage: .whatsAppMessage
        case .calendarQuery: .calendarQuery
        case .calendarEvent: .calendarEvent
        case .reminderQuery: .reminderQuery
        case .reminder: .reminder
        case .note: .note
        case .finderLocation: .finderLocation
        case .fileSearch: .fileSearch
        case .calendarDelete: .calendarDelete
        case .reminderComplete: .reminderComplete
        case .reminderDelete: .reminderDelete
        case .noteFind: .noteFind
        case .noteOpen: .noteOpen
        case .contextOpen: .contextOpen
        case .contextMessage: .contextMessage
        case .contextCheck: .contextCheck
        case .contactsQuery: .contactsQuery
        case .contactsShow: .contactsShow
        case .mailCompose: .mailCompose
        case .finderCreateFolder: .finderCreateFolder
        case .finderCreateFile: .finderCreateFile
        case .finderReveal: .finderReveal
        case .finderTrash: .finderTrash
        case .finderRename: .finderRename
        case .finderDuplicate: .finderDuplicate
        case .clipboardInspect: .clipboardInspect
        case .systemBattery: .systemBattery
        case .systemMacOSVersion: .systemMacOSVersion
        case .systemTime: .systemTime
        case .systemDate: .systemDate
        case .systemVolumeUp: .systemVolumeUp
        case .systemVolumeDown: .systemVolumeDown
        case .systemVolumeSet: .systemVolumeSet
        case .systemVolumeMute: .systemVolumeMute
        case .systemVolumeUnmute: .systemVolumeUnmute
        case .systemVolumeGet: .systemVolumeGet
        case .systemSleep: .systemSleep
        case .systemLock: .systemLock
        case .systemLogout: .systemLogout
        case .systemRestart: .systemRestart
        case .systemShutdown: .systemShutdown
        }
    }
}

