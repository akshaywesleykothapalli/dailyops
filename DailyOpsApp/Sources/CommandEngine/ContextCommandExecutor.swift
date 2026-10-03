import AppKit
import Foundation

/// Abstract interface for context-aware operations.
@MainActor
protocol ContextControlling: Sendable {
    func openFromContext(_ request: ContextOpenRequest, context: CommandContext) throws -> String
    func messageFromContext(_ request: ContextMessageRequest, context: CommandContext) throws -> String
    func checkFromContext(_ request: ContextCheckRequest, context: CommandContext) throws -> String
}

/// Concrete context controller using resolved context.
@MainActor
final class SystemContextControl: ContextControlling {
    func openFromContext(_ request: ContextOpenRequest, context: CommandContext) throws -> String {
        switch request.targetKind {
        case .file:
            if let url = context.resolvedFileURL {
                NSWorkspace.shared.open(url)
                return "Opened \(context.resolvedFileName ?? "file")"
            }
            return "No file was resolved from previous command."

        case .calendarEvent:
            if context.resolvedCalendarEventTitle != nil {
                return "Calendar event: \(context.resolvedCalendarEventTitle!)."
            }
            return "No calendar event was resolved from previous command."

        case .reminder:
            if context.resolvedReminderTitle != nil {
                return "Reminder: \(context.resolvedReminderTitle!)."
            }
            return "No reminder was resolved from previous command."

        case .contact:
            if context.resolvedContactName != nil {
                return "Contact: \(context.resolvedContactName!)."
            }
            return "No contact was resolved from previous command."

        case .note:
            if context.resolvedNoteTitle != nil {
                return "Note: \(context.resolvedNoteTitle!)."
            }
            return "No note was resolved from previous command."

        case .application:
            let appName = context.frontmostApplicationName
            if !appName.isEmpty {
                // We can't meaningfully "open" an already-open app, but we can report it
                return "Current app is \(appName)."
            }
            return "No frontmost application detected."
        }
    }

    func messageFromContext(_ request: ContextMessageRequest, context: CommandContext) throws -> String {
        guard let contactName = context.resolvedContactName, context.resolvedContactPhone != nil else {
            return "No contact was resolved from previous command."
        }
        // This would typically open WhatsApp and send the message
        // For now, we just report the intent
        return "Would send message to \(contactName): \"\(request.message)\""
    }

    func checkFromContext(_ request: ContextCheckRequest, context: CommandContext) throws -> String {
        switch request.targetKind {
        case .calendarEvent:
            if let title = context.resolvedCalendarEventTitle {
                return "Next meeting: \(title)."
            }
            return "No calendar event was resolved from previous command."

        case .reminder:
            if let title = context.resolvedReminderTitle {
                return "Reminder: \(title)."
            }
            return "No reminder was resolved from previous command."

        case .application:
            let appName = context.frontmostApplicationName
            if !appName.isEmpty {
                return "Current app: \(appName)."
            }
            return "No frontmost application detected."

        default:
            return "Context check for \(request.targetKind) is not supported."
        }
    }
}

/// Fake context controller for unit testing.
@MainActor
final class FakeContextControl: ContextControlling {
    var openedContexts: [ContextOpenRequest] = []
    var messagedContexts: [ContextMessageRequest] = []
    var checkedContexts: [ContextCheckRequest] = []
    var shouldFail: Bool = false

    func openFromContext(_ request: ContextOpenRequest, context: CommandContext) throws -> String {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Context open failed.")
        }
        openedContexts.append(request)
        
        switch request.targetKind {
        case .application:
            let appName = context.frontmostApplicationName
            if !appName.isEmpty {
                return "Current app is \(appName)."
            }
            return "No frontmost application detected."
        default:
            return "Opened from context"
        }
    }

    func messageFromContext(_ request: ContextMessageRequest, context: CommandContext) throws -> String {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Context message failed.")
        }
        messagedContexts.append(request)
        return "Messaged from context"
    }

    func checkFromContext(_ request: ContextCheckRequest, context: CommandContext) throws -> String {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Context check failed.")
        }
        checkedContexts.append(request)
        
        switch request.targetKind {
        case .application:
            let appName = context.frontmostApplicationName
            if !appName.isEmpty {
                return "Current app: \(appName)."
            }
            return "No frontmost application detected."
        case .calendarEvent:
            if let title = context.resolvedCalendarEventTitle {
                return "Next meeting: \(title)."
            }
            return "No calendar event was resolved from previous command."
        case .reminder:
            if let title = context.resolvedReminderTitle {
                return "Reminder: \(title)."
            }
            return "No reminder was resolved from previous command."
        default:
            return "Checked from context"
        }
    }
}

/// Executes context-aware commands.
@MainActor
struct ContextCommandExecutor: CommandExecuting {
    private let control: ContextControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .contextOpen,
        .contextMessage,
        .contextCheck
    ]

    init(control: ContextControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .contextOpen:
            guard case .contextOpen(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            return try control.openFromContext(request, context: context)

        case .contextMessage:
            guard case .contextMessage(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            return try control.messageFromContext(request, context: context)

        case .contextCheck:
            guard case .contextCheck(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            return try control.checkFromContext(request, context: context)

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}