import Foundation

/// Verdict on a plan, produced before anything is executed.
enum CommandValidation: Equatable {
    /// Safe to hand to an executor as-is.
    case approved
    /// Recognised and well-formed, but the user must approve it first.
    case requiresConfirmation(reason: String)
}

/// The single gate between interpretation and execution. Every plan passes
/// through here, and the router will not call an executor for a plan this
/// type rejects or defers — that is what makes the risk boundary real rather
/// than advisory metadata on the registry.
@MainActor
struct CommandValidator {
    private let registry: CommandRegistry
    private let contactResolver: WhatsAppContactResolving?
    private let applications: ApplicationResolving?

    init(
        registry: CommandRegistry,
        contactResolver: WhatsAppContactResolving? = nil,
        applications: ApplicationResolving? = nil
    ) {
        self.registry = registry
        self.contactResolver = contactResolver
        self.applications = applications
    }

    func definition(for identifier: CommandIdentifier) -> CommandDefinition? {
        registry.definition(for: identifier)
    }

    /// Resolves any unresolved entities (such as WhatsApp contacts or application references)
    /// against DailyOps's local system resolvers before validation and execution.
    func resolve(_ plan: CommandPlan) -> CommandPlan {
        var resolvedSteps: [CommandStep] = []

        for step in plan.steps {
            var resolvedIntent = step.intent

            switch step.intent.arguments {
            case .application(let ref):
                if ref.bundleURL == nil, let apps = applications {
                    if let found = apps.installedApplication(named: ref.displayName) ?? apps.runningApplication(named: ref.displayName) {
                        resolvedIntent = CommandIntent(identifier: step.intent.identifier, arguments: .application(found))
                    }
                }

            case .whatsAppChat(let target):
                if target.recipient.resolution == .unresolved, let resolver = contactResolver {
                    let resolution = resolver.resolve(nameOrQuery: target.recipient.rawQuery)
                    let newRecipient = WhatsAppRecipient(rawQuery: target.recipient.rawQuery, resolution: resolution)
                    resolvedIntent = CommandIntent(identifier: step.intent.identifier, arguments: .whatsAppChat(WhatsAppChatTarget(recipient: newRecipient)))
                }

            case .whatsAppMessage(let target):
                if target.recipient.resolution == .unresolved, let resolver = contactResolver {
                    let resolution = resolver.resolve(nameOrQuery: target.recipient.rawQuery)
                    let newRecipient = WhatsAppRecipient(rawQuery: target.recipient.rawQuery, resolution: resolution)
                    resolvedIntent = CommandIntent(identifier: step.intent.identifier, arguments: .whatsAppMessage(WhatsAppMessageTarget(recipient: newRecipient, message: target.message)))
                }

            case .none, .writingMode, .url, .search, .calendarQuery, .calendarEvent, .reminderQuery, .reminder, .note, .finderLocation, .fileSearch, .calendarDelete, .reminderComplete, .reminderDelete, .noteFind, .noteOpen, .contextOpen, .contextMessage, .contextCheck, .contactsQuery, .contactsShow, .mailCompose, .finderCreateFolder, .finderCreateFile, .finderReveal, .finderTrash, .finderRename, .finderDuplicate, .clipboardInspect, .systemBattery, .systemMacOSVersion, .systemTime, .systemDate, .systemVolumeUp, .systemVolumeDown, .systemVolumeSet, .systemVolumeMute, .systemVolumeUnmute, .systemVolumeGet, .systemSleep, .systemLock, .systemLogout, .systemRestart, .systemShutdown:
                break
            }

            resolvedSteps.append(CommandStep(intent: resolvedIntent))
        }

        return CommandPlan(steps: resolvedSteps)
    }

    func validate(_ plan: CommandPlan, context: CommandContext) throws -> CommandValidation {
        guard !plan.steps.isEmpty else {
            throw CommandValidationError.emptyPlan
        }

        var requiresConfirmation = false
        var confirmationReasons: [String] = []

        for step in plan.steps {
            let intent = step.intent
            guard let definition = registry.definition(for: intent.identifier) else {
                throw CommandValidationError.unknownCommand(intent.identifier)
            }
            guard intent.arguments.kind == definition.argumentKind else {
                throw CommandValidationError.invalidArguments(intent.identifier)
            }

            if case .whatsAppChat(let target) = intent.arguments {
                try validateRecipient(target.recipient)
            } else if case .whatsAppMessage(let target) = intent.arguments {
                try validateRecipient(target.recipient)
            } else if case .calendarEvent(let event) = intent.arguments {
                guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .reminder(let reminder) = intent.arguments {
                guard !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .note(let note) = intent.arguments {
                guard !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .contactsQuery(let query) = intent.arguments {
                guard !query.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .contactsShow(let request) = intent.arguments {
                guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .mailCompose = intent.arguments {
                // Mail compose is valid even with empty fields (blank compose)
            } else if case .finderCreateFolder(let request) = intent.arguments {
                guard !request.folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .finderCreateFile(let request) = intent.arguments {
                guard !request.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .finderReveal(let request) = intent.arguments {
                guard !request.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .finderTrash(let request) = intent.arguments {
                guard !request.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .finderRename(let request) = intent.arguments {
                guard !request.oldPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
                guard !request.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .finderDuplicate(let request) = intent.arguments {
                guard !request.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            } else if case .systemVolumeSet(let percentage) = intent.arguments {
                guard percentage >= 0 && percentage <= 100 else {
                    throw CommandValidationError.invalidArguments(intent.identifier)
                }
            }

            switch (definition.risk, definition.confirmation) {
            case (_, .mandatory):
                requiresConfirmation = true
                confirmationReasons.append("\(definition.name) needs your approval.")
            case (.destructive, _):
                requiresConfirmation = true
                confirmationReasons.append("\(definition.name) cannot be undone. Confirm to continue.")
            case (.sensitive, .optional):
                requiresConfirmation = true
                confirmationReasons.append("\(definition.name)?")
            case (.sensitive, .none), (.safe, _):
                break
            }
        }

        if requiresConfirmation {
            let reason = confirmationReasons.joined(separator: " ")
            return .requiresConfirmation(reason: reason)
        } else {
            return .approved
        }
    }

    private func validateRecipient(_ recipient: WhatsAppRecipient) throws {
        switch recipient.resolution {
        case .resolved:
            return
        case .ambiguous(let matches):
            throw CommandValidationError.ambiguousRecipient(
                query: recipient.rawQuery,
                matches: matches.map(\.name)
            )
        case .notFound(let query):
            throw CommandValidationError.recipientNotFound(query: query)
        case .unavailable(let reason):
            throw CommandValidationError.contactsUnavailable(reason: reason)
        case .unresolved:
            throw CommandValidationError.recipientNotFound(query: recipient.rawQuery)
        }
    }
}
