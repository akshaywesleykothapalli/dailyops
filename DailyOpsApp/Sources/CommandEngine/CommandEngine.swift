import Foundation

/// Assembles the engine and is the only type the dictation pipeline talks to.
/// Construction is explicit so a test can build an engine from fakes, and the
/// live wiring in `live(controller:)` is the only place that reaches for real
/// system services.
/// The outcome of processing a transcript through the command engine.
enum CommandEngineOutcome: Equatable {
    /// The command was recognised, authorized/safe, and executed.
    case executed(feedback: String)
    /// The command was recognised, but requires explicit confirmation before execution.
    case confirmationRequired(request: ConfirmationRequest)
    /// The command was recognised, but failed validation or execution.
    case failed(message: String)
    /// The transcript is not a recognised command; caller should proceed with normal dictation.
    case ignored
}

@MainActor
final class CommandEngine {
    private let router: CommandRouter

    init(router: CommandRouter) {
        self.router = router
    }

    /// Exposes the currently pending confirmation request, if any.
    var pendingConfirmation: ConfirmationRequest? {
        router.pendingConfirmation
    }

    /// Processes a transcript, returning whether it was executed, requires confirmation, failed, or was ignored.
    func process(_ transcript: String, context: CommandContext) -> CommandEngineOutcome {
        let result = router.handle(transcript, context: context)
        switch result {
        case .success(let message):
            return .executed(feedback: message)
        case .failure(let message):
            return .failed(message: message)
        case .confirmationRequired(let plan, let message):
            if let pending = router.pendingConfirmation {
                return .confirmationRequired(request: pending)
            }
            let fallbackRequest = ConfirmationRequest(
                plan: plan,
                title: "Confirm Command",
                details: message,
                risk: .sensitive
            )
            return .confirmationRequired(request: fallbackRequest)
        case .ignored:
            return .ignored
        }
    }

    /// Asynchronously processes a transcript through the command engine.
    func processAsync(_ transcript: String, context: CommandContext) async -> CommandEngineOutcome {
        let result = await router.handleAsync(transcript, context: context)
        switch result {
        case .success(let message):
            return .executed(feedback: message)
        case .failure(let message):
            return .failed(message: message)
        case .confirmationRequired(let plan, let message):
            if let pending = router.pendingConfirmation {
                return .confirmationRequired(request: pending)
            }
            let fallbackRequest = ConfirmationRequest(
                plan: plan,
                title: "Confirm Command",
                details: message,
                risk: .sensitive
            )
            return .confirmationRequired(request: fallbackRequest)
        case .ignored:
            return .ignored
        }
    }

    /// Confirms a pending confirmation request by ID and executes the plan.
    func confirm(id: ConfirmationRequestID, context: CommandContext) -> CommandResult {
        router.confirm(id: id, context: context)
    }

    /// Cancels a pending confirmation request by ID.
    @discardableResult
    func cancel(id: ConfirmationRequestID) -> CommandResult {
        router.cancel(id: id)
    }

    /// Returns feedback for a recognised command, or nil when the transcript is
    /// not one. Nil is the signal for the caller to continue with normal
    /// dictation, so an unrecognised transcript is never consumed here.
    func handle(_ transcript: String, context: CommandContext) -> String? {
        switch process(transcript, context: context) {
        case .executed(let feedback):
            return feedback
        case .failed(let message):
            return message
        case .confirmationRequired(let request):
            return request.details
        case .ignored:
            return nil
        }
    }

    /// Asynchronously returns feedback for a recognised command, or nil to continue normal dictation.
    func handleAsync(_ transcript: String, context: CommandContext) async -> String? {
        switch await processAsync(transcript, context: context) {
        case .executed(let feedback):
            return feedback
        case .failed(let message):
            return message
        case .confirmationRequired(let request):
            return request.details
        case .ignored:
            return nil
        }
    }

    /// The engine as the app runs it: deterministic parsing, the standard
    /// command table, and executors bound to the live controller.
    static func live(controller: DictationController) -> CommandEngine {
        let resolver = SystemApplicationResolver()
        let host = SystemCommandHost(controller: controller)
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let emailContacts = SystemEmailContactResolver()
        let whatsAppParser = WhatsAppCommandParser(contactResolver: whatsAppContacts)
        let calendarParser = CalendarCommandParser()
        let remindersParser = RemindersCommandParser()
        let notesParser = NotesCommandParser()
        let finderParser = FinderCommandParser()
        let contactsParser = ContactsCommandParser(contactResolver: whatsAppContacts)
        let mailParser = MailCommandParser(contactResolver: whatsAppContacts, emailResolver: emailContacts)
        let clipboardParser = ClipboardCommandParser()
        let systemInfoParser = SystemInformationCommandParser()
        let systemAudioParser = SystemAudioCommandParser()
        let systemPowerParser = SystemPowerCommandParser()
        let deterministicParser = DeterministicCommandParser(applications: resolver)
        let multiStepParser = MultiStepCommandParser(parsers: [
            whatsAppParser,
            calendarParser,
            remindersParser,
            notesParser,
            finderParser,
            contactsParser,
            mailParser,
            clipboardParser,
            systemInfoParser,
            systemAudioParser,
            systemPowerParser,
            deterministicParser
        ])

        let router = CommandRouter(
            parsers: [
                multiStepParser,
                whatsAppParser,
                calendarParser,
                remindersParser,
                notesParser,
                finderParser,
                contactsParser,
                mailParser,
                clipboardParser,
                systemInfoParser,
                systemAudioParser,
                systemPowerParser,
                deterministicParser,
            ],
            validator: CommandValidator(
                registry: .standard(),
                contactResolver: whatsAppContacts,
                applications: resolver
            ),
            executors: [
                ApplicationCommandExecutor(control: SystemApplicationControl(resolver: resolver)),
                NavigationCommandExecutor(host: host),
                DictationCommandExecutor(host: host),
                BrowserCommandExecutor(control: SystemBrowserControl()),
                WhatsAppCommandExecutor(control: SystemWhatsAppControl()),
                CalendarCommandExecutor(control: SystemCalendarControl()),
                RemindersCommandExecutor(control: SystemRemindersControl()),
                NotesCommandExecutor(control: SystemNotesControl()),
                FinderCommandExecutor(control: SystemFinderControl()),
                ContextCommandExecutor(control: SystemContextControl()),
                ContactsCommandExecutor(control: SystemContactsControl(whatsAppResolver: whatsAppContacts)),
                MailCommandExecutor(control: SystemMailControl()),
                ClipboardCommandExecutor(control: SystemClipboardControl()),
                SystemInformationCommandExecutor(control: SystemSystemInformationControl()),
                SystemAudioCommandExecutor(control: SystemAudioControl()!),
                SystemPowerCommandExecutor(control: SystemPowerControl()),
            ]
        )
        return CommandEngine(router: router)
    }
}
