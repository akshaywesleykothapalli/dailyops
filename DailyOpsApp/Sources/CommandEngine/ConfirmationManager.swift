import Foundation

/// Protocol governing confirmation request lifecycle and single-resolution safety.
@MainActor
protocol ConfirmationManaging: AnyObject {
    /// The currently pending confirmation request waiting for user approval.
    var pendingConfirmation: ConfirmationRequest? { get }

    /// Creates and tracks a confirmation request for a validated plan and definition,
    /// invalidating any previously pending request.
    @discardableResult
    func requestConfirmation(
        for plan: CommandPlan,
        definition: CommandDefinition,
        context: CommandContext,
        reason: String
    ) -> ConfirmationRequest

    /// Registers a fully specified confirmation request, invalidating any previous request.
    @discardableResult
    func requestConfirmation(_ request: ConfirmationRequest) -> ConfirmationRequest

    /// Resolves the confirmation request with the given ID and explicit decision.
    /// Guarantees exact-once resolution, rejecting duplicates, stale IDs, or missing requests.
    func resolve(id: ConfirmationRequestID, decision: ConfirmationDecision) -> ConfirmationResolution

    /// Cancels any currently pending confirmation without executing anything.
    func cancelCurrent()

    /// Completely resets all pending and historical confirmation state.
    func reset()
}

/// Concrete implementation of `ConfirmationManaging`.
/// All operations are isolated to `@MainActor`, preventing race conditions.
@MainActor
final class ConfirmationManager: ConfirmationManaging {
    private var currentPending: ConfirmationRequest?
    private var resolvedHistory: [ConfirmationRequestID: ConfirmationDecision] = [:]

    init() {}

    var pendingConfirmation: ConfirmationRequest? {
        currentPending
    }

    @discardableResult
    func requestConfirmation(
        for plan: CommandPlan,
        definition: CommandDefinition,
        context: CommandContext,
        reason: String
    ) -> ConfirmationRequest {
        var confirmLabel: String
        switch definition.identifier {
        case .appQuit:
            confirmLabel = "Quit"
        case .clipboardClear:
            confirmLabel = "Clear"
        case .whatsAppSendMessage:
            confirmLabel = "Send"
        case .mailCompose:
            confirmLabel = "Compose"
        default:
            confirmLabel = "Confirm"
        }

        var title: String = definition.name
        var subtitle: String? = nil
        var details: String = reason
        var preview: String? = nil

        if plan.steps.count > 1 {
            title = "Confirm \(plan.steps.count) Actions"
            details = plan.steps.enumerated().map { index, step in
                "\(index + 1). \(stepDescription(step.intent))"
            }.joined(separator: "\n")
            preview = "\(plan.steps.count) actions to confirm"
            confirmLabel = "Confirm"
        } else if let firstStep = plan.steps.first {
            switch firstStep.intent.arguments {
            case .application(let app):
                preview = app.displayName
                subtitle = app.displayName
            case .writingMode(let mode):
                preview = mode.rawValue.capitalized
            case .url(let url):
                preview = url.host ?? url.absoluteString
                subtitle = url.host ?? url.absoluteString
            case .search(let request):
                preview = "\(request.provider.displayName): \(request.query)"
                subtitle = request.provider.displayName
            case .whatsAppChat(let target):
                preview = target.recipient.displayName
                subtitle = target.recipient.displayName
            case .whatsAppMessage(let target):
                title = "Send WhatsApp message?"
                let recipientLine: String
                if let contact = target.recipient.resolvedContact {
                    recipientLine = "\(contact.name) · +\(contact.phoneNumber)"
                } else {
                    recipientLine = target.recipient.displayName
                }
                subtitle = recipientLine
                details = "To: \(target.recipient.displayName)\nMessage: \"\(target.message)\""
                preview = "To \(target.recipient.displayName): \"\(target.message)\""
                confirmLabel = "Send"
            case .calendarEvent(let event):
                title = "Create Calendar Event?"
                subtitle = event.title
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = event.startTime != nil ? .short : .none
                let dateStr = df.string(from: event.startTime ?? event.date)
                details = "Event: \(event.title) (\(dateStr))"
                preview = event.title
                confirmLabel = "Create Event"
            case .calendarQuery(let query):
                title = "Check Calendar"
                preview = "\(query.day)"
                subtitle = "Calendar"
            case .calendarDelete(let request):
                title = "Delete Calendar Event?"
                subtitle = request.title
                if let date = request.date {
                    let df = DateFormatter()
                    df.dateStyle = .medium
                    df.timeStyle = request.startTime != nil ? .short : .none
                    let dateStr = df.string(from: date)
                    details = "Event: \(request.title) (\(dateStr))"
                } else {
                    details = "Event: \(request.title)"
                }
                preview = request.title
                confirmLabel = "Delete Event"
            case .reminder(let reminder):
                title = "Create Reminder?"
                subtitle = reminder.title
                var detailsStr = "Reminder: \(reminder.title)"
                if let due = reminder.dueTime ?? reminder.dueDate {
                    let df = DateFormatter()
                    df.dateStyle = .medium
                    df.timeStyle = reminder.dueTime != nil ? .short : .none
                    detailsStr += " (Due: \(df.string(from: due)))"
                }
                details = detailsStr
                preview = reminder.title
                confirmLabel = "Create Reminder"
            case .reminderQuery:
                title = "Check Reminders"
                subtitle = "Reminders"
            case .reminderComplete(let request):
                title = "Complete Reminder?"
                subtitle = request.title
                details = "Mark \"\(request.title)\" as completed."
                preview = request.title
                confirmLabel = "Complete"
            case .reminderDelete(let request):
                title = "Delete Reminder?"
                subtitle = request.title
                details = "Permanently delete \"\(request.title)\"."
                preview = request.title
                confirmLabel = "Delete"
            case .note(let note):
                title = "Create Note?"
                subtitle = note.title
                details = note.body != nil ? "Title: \(note.title)\n\n\(note.body!)" : "Title: \(note.title)"
                preview = note.title
                confirmLabel = "Create Note"
            case .noteFind(let request):
                title = "Find Notes"
                subtitle = "Notes"
                details = "Search notes for \"\(request.query)\""
                preview = request.query
            case .noteOpen(let request):
                title = "Open Note"
                subtitle = "Notes"
                details = "Open note matching \"\(request.query)\""
                preview = request.query
            case .finderLocation(let target):
                preview = target.customName ?? "\(target.location)"
                subtitle = "Finder"
            case .fileSearch(let req):
                preview = "\(req.filter) in \(req.scope)"
                subtitle = "Files"
            case .contactsQuery(let request):
                title = "Find Contacts"
                subtitle = "Contacts"
                details = "Search contacts for \"\(request.query)\""
                preview = request.query
            case .contactsShow(let request):
                title = "Show Contact"
                subtitle = "Contacts"
                details = "Show contact matching \"\(request.query)\""
                preview = request.query
case .mailCompose(let request):
                title = "Compose Email?"
                subtitle = request.to.map { "To: \($0)" } ?? "New Email"
                var detailsParts: [String] = []
                if let to = request.to {
                    detailsParts.append("To: \(to)")
                }
                if let subject = request.subject {
                    detailsParts.append("Subject: \(subject)")
                }
                if let body = request.body {
                    detailsParts.append("Body: \(body)")
                }
                details = detailsParts.joined(separator: "\n")
                if details.isEmpty {
                    details = "Compose a new email."
                }
                preview = request.to.map { "To: \($0)" } ?? "New Email"
                confirmLabel = "Compose"
            case .finderCreateFolder(let request):
                title = "Create Folder?"
                subtitle = request.folderName
                details = "Create folder \"\(request.folderName)\"\(request.parentPath.map { " in \($0)" } ?? "")"
                preview = request.folderName
                confirmLabel = "Create"
            case .finderCreateFile(let request):
                title = "Create File?"
                subtitle = request.fileName
                details = "Create file \"\(request.fileName)\"\(request.parentPath.map { " in \($0)" } ?? "")"
                preview = request.fileName
                confirmLabel = "Create"
            case .finderReveal(let request):
                title = "Reveal in Finder?"
                subtitle = request.path
                details = "Reveal \"\(request.path)\" in Finder."
                preview = request.path
                confirmLabel = "Reveal"
            case .finderTrash(let request):
                title = "Move to Trash?"
                subtitle = request.path
                details = "Move \"\(request.path)\" to Trash."
                preview = request.path
                confirmLabel = "Move to Trash"
            case .finderRename(let request):
                title = "Rename File/Folder?"
                subtitle = "\(request.oldPath) → \(request.newName)"
                details = "Rename \"\(request.oldPath)\" to \"\(request.newName)\"."
                preview = request.newName
                confirmLabel = "Rename"
            case .finderDuplicate(let request):
                title = "Duplicate File/Folder?"
                subtitle = request.path
                details = "Duplicate \"\(request.path)\"."
                preview = request.path
                confirmLabel = "Duplicate"
            case .clipboardInspect:
                title = "Inspect Clipboard?"
                subtitle = "Clipboard"
                details = "View the current clipboard contents."
                preview = "Clipboard"
            case .systemBattery:
                title = "Battery Status"
                subtitle = "Battery"
                details = "View current battery level and charging status."
                preview = "Battery"
            case .systemMacOSVersion:
                title = "macOS Version"
                subtitle = "System"
                details = "View the macOS version and build information."
                preview = "macOS Version"
            case .systemTime:
                title = "Current Time"
                subtitle = "Time"
                details = "View the current system time."
                preview = "Time"
            case .systemDate:
                title = "Current Date"
                subtitle = "Date"
                details = "View the current date."
                preview = "Date"
            case .systemVolumeUp:
                title = "Volume Up"
                subtitle = "Volume"
                details = "Increase the system volume."
                preview = "Volume Up"
            case .systemVolumeDown:
                title = "Volume Down"
                subtitle = "Volume"
                details = "Decrease the system volume."
                preview = "Volume Down"
            case .systemVolumeSet(let percentage):
                title = "Set Volume"
                subtitle = "Volume"
                details = "Set the system volume to \(percentage)%."
                preview = "Set to \(percentage)%"
            case .systemVolumeMute:
                title = "Mute Volume"
                subtitle = "Volume"
                details = "Mute the system volume."
                preview = "Mute"
            case .systemVolumeUnmute:
                title = "Unmute Volume"
                subtitle = "Volume"
                details = "Unmute the system volume."
                preview = "Unmute"
            case .systemVolumeGet:
                title = "Current Volume"
                subtitle = "Volume"
                details = "View the current system volume level."
                preview = "Volume"
            case .systemSleep:
                title = "Put Mac to Sleep?"
                subtitle = "Power"
                details = "Put this Mac to sleep."
                preview = "Sleep"
                confirmLabel = "Sleep"
            case .systemLock:
                title = "Lock Mac?"
                subtitle = "Security"
                details = "Lock the screen of this Mac."
                preview = "Lock"
                confirmLabel = "Lock"
            case .systemLogout:
                title = "Log Out of Mac?"
                subtitle = "Session"
                details = "Log out of your user account on this Mac."
                preview = "Log Out"
                confirmLabel = "Log Out"
            case .systemRestart:
                title = "Restart Mac?"
                subtitle = "Power"
                details = "Restart this Mac."
                preview = "Restart"
                confirmLabel = "Restart"
            case .systemShutdown:
                title = "Shut Down Mac?"
                subtitle = "Power"
                details = "Shut down this Mac."
                preview = "Shut Down"
                confirmLabel = "Shut Down"
            case .contextOpen(let request):
                title = "Open from Context"
                subtitle = request.targetKind.rawValue.capitalized
                details = "Open the resolved \(request.targetKind.rawValue)."
                preview = request.targetKind.rawValue.capitalized
            case .contextMessage:
                title = "Message from Context"
                subtitle = "Contact"
                details = "Send message to resolved contact."
                preview = "Message contact"
            case .contextCheck(let request):
                title = "Check from Context"
                subtitle = request.targetKind.rawValue.capitalized
                details = "Check \(request.targetKind.rawValue)."
                preview = request.targetKind.rawValue.capitalized
            case .none:
                preview = nil
            }
        }

        let request = ConfirmationRequest(
            requestId: ConfirmationRequestID(),
            plan: plan,
            title: title,
            subtitle: subtitle,
            details: details,
            risk: definition.risk,
            preview: preview,
            confirmActionLabel: confirmLabel,
            cancelActionLabel: "Cancel",
            createdAt: Date()
        )

        return requestConfirmation(request)
    }

    @discardableResult
    func requestConfirmation(_ request: ConfirmationRequest) -> ConfirmationRequest {
        // Invalidate any previously pending request so its ID cannot be approved later
        if let previous = currentPending {
            resolvedHistory[previous.id] = .cancel
        }
        currentPending = request
        return request
    }

    func resolve(id: ConfirmationRequestID, decision: ConfirmationDecision) -> ConfirmationResolution {
        // 1. If this ID was already resolved previously, reject as already resolved
        if resolvedHistory[id] != nil {
            return .rejected(.alreadyResolved)
        }

        // 2. Check currently pending request
        guard let pending = currentPending else {
            return .rejected(.noPendingRequest)
        }

        // 3. Reject if the ID does not match the pending request (stale ID)
        guard pending.id == id else {
            return .rejected(.staleId)
        }

        // 4. Mark resolved exactly once
        currentPending = nil
        resolvedHistory[id] = decision

        switch decision {
        case .confirm:
            return .confirmed(pending)
        case .cancel:
            return .cancelled(pending)
        }
    }

    func cancelCurrent() {
        guard let pending = currentPending else { return }
        currentPending = nil
        resolvedHistory[pending.id] = .cancel
    }

    func reset() {
        currentPending = nil
        resolvedHistory.removeAll()
    }

    private func stepDescription(_ intent: CommandIntent) -> String {
        switch intent.arguments {
        case .application(let app):
            return "Open \(app.displayName)"
        case .writingMode(let mode):
            return "Switch to \(mode.rawValue.capitalized) Mode"
        case .url(let url):
            return "Open \(url.host ?? url.absoluteString)"
        case .search(let req):
            return "Search \(req.provider.displayName) for \(req.query)"
        case .whatsAppChat(let target):
            return "Open WhatsApp chat with \(target.recipient.displayName)"
        case .whatsAppMessage(let target):
            return "Send WhatsApp message to \(target.recipient.displayName): \"\(target.message)\""
        case .calendarEvent(let event):
            return "Create calendar event \"\(event.title)\""
        case .calendarQuery(let query):
            return "Check calendar for \(query.day)"
        case .calendarDelete(let request):
            return "Delete calendar event \"\(request.title)\""
        case .reminder(let reminder):
            return "Create reminder \"\(reminder.title)\""
        case .reminderQuery:
            return "Check reminders"
        case .reminderComplete(let request):
            return "Complete reminder \"\(request.title)\""
        case .reminderDelete(let request):
            return "Delete reminder \"\(request.title)\""
        case .note(let note):
            return "Create note \"\(note.title)\""
        case .noteFind(let request):
            return "Find notes about \"\(request.query)\""
        case .noteOpen(let request):
            return "Open note about \"\(request.query)\""
        case .finderLocation(let target):
            return "Open \(target.customName ?? "\(target.location)") in Finder"
        case .fileSearch(let req):
            return "Search \(req.scope) files"
        case .contactsQuery(let request):
            return "Find contacts for \"\(request.query)\""
        case .contactsShow(let request):
            return "Show contact for \"\(request.query)\""
        case .mailCompose(let request):
            if let to = request.to {
                return "Compose email to \(to)"
            } else {
                return "Compose new email"
            }
        case .finderCreateFolder(let request):
            return "Create folder \"\(request.folderName)\""
        case .finderCreateFile(let request):
            return "Create file \"\(request.fileName)\""
        case .finderReveal(let request):
            return "Reveal \"\(request.path)\" in Finder"
        case .finderTrash(let request):
            return "Move \"\(request.path)\" to Trash"
        case .finderRename(let request):
            return "Rename \"\(request.oldPath)\" to \"\(request.newName)\""
        case .finderDuplicate(let request):
            return "Duplicate \"\(request.path)\""
        case .clipboardInspect:
            return "Inspect clipboard"
        case .systemBattery:
            return "Check battery status"
        case .systemMacOSVersion:
            return "Check macOS version"
        case .systemTime:
            return "Check current time"
        case .systemDate:
            return "Check current date"
        case .systemVolumeUp:
            return "Increase volume"
        case .systemVolumeDown:
            return "Decrease volume"
        case .systemVolumeSet(let percentage):
            return "Set volume to \(percentage)%"
        case .systemVolumeMute:
            return "Mute volume"
        case .systemVolumeUnmute:
            return "Unmute volume"
        case .systemVolumeGet:
            return "Check current volume"
        case .systemSleep:
            return "Put Mac to sleep"
        case .systemLock:
            return "Lock Mac"
        case .systemLogout:
            return "Log out of Mac"
        case .systemRestart:
            return "Restart Mac"
        case .systemShutdown:
            return "Shut down Mac"
        case .contextOpen(let request):
            return "Open \(request.targetKind.rawValue) from context"
        case .contextMessage:
            return "Message contact from context"
        case .contextCheck(let request):
            return "Check \(request.targetKind.rawValue) from context"
        case .none:
            return intent.identifier.rawValue
        }
    }
}
