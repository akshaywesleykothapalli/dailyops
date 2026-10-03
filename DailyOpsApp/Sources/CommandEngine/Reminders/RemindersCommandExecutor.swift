import AppKit
import EventKit
import Foundation
import os

/// Summary of a reminder for display to the user.
struct ReminderSummary: Equatable, Sendable {
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
}

/// Abstract interface for Reminders operations.
@MainActor
protocol RemindersControlling: Sendable {
    func openReminders() throws
    func fetchReminders(for query: ReminderQuery) throws -> [ReminderSummary]
    func createReminder(_ request: ReminderRequest) throws
    func completeReminder(_ request: ReminderCompleteRequest) throws
    func deleteReminder(_ request: ReminderDeleteRequest) throws
}

/// Concrete Reminders controller using EventKit and NSWorkspace.
@MainActor
final class SystemRemindersControl: RemindersControlling {
    private let eventStore = EKEventStore()

    func openReminders() throws {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: "x-apple-reminderkit:") {
            NSWorkspace.shared.open(url)
        } else {
            throw CommandExecutionError.operationFailed("Reminders application could not be opened.")
        }
    }

    func fetchReminders(for query: ReminderQuery) throws -> [ReminderSummary] {
        try ensureRemindersAccess()

        let predicate: NSPredicate
        let calendar = Calendar.current

        if let dueDay = query.dueDay {
            let startDate: Date
            let endDate: Date
            switch dueDay {
            case .today:
                startDate = calendar.startOfDay(for: Date())
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            case .tomorrow:
                startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            case .specificDate:
                // Overdue: reminders due before today
                startDate = Date.distantPast
                endDate = calendar.startOfDay(for: Date())
            case .next:
                startDate = Date()
                endDate = calendar.date(byAdding: .day, value: 365, to: startDate) ?? startDate
            case .thisWeek:
                startDate = calendar.startOfDay(for: Date())
                endDate = calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate
            case .afternoon:
                // Reminders don't have afternoon-specific queries; treat as today
                startDate = calendar.startOfDay(for: Date())
                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
            }
            predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: startDate, ending: endDate, calendars: nil)
        } else {
            // No dueDay filter: return all incomplete reminders (combined today + overdue + future)
            predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var summaries: [ReminderSummary] = []

        eventStore.fetchReminders(matching: predicate) { found in
            let currentCal = Calendar.current
            let results = (found ?? []).map { reminder in
                let dueDate: Date?
                if let comps = reminder.dueDateComponents {
                    dueDate = currentCal.date(from: comps)
                } else {
                    dueDate = nil
                }
                return ReminderSummary(
                    title: reminder.title ?? "Untitled Reminder",
                    dueDate: dueDate,
                    isCompleted: reminder.isCompleted
                )
            }
            summaries = results
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5.0)
        return summaries
    }

    func createReminder(_ request: ReminderRequest) throws {
        try ensureRemindersAccess()

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = request.title

        let calendar = Calendar.current
        if let time = request.dueTime {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        } else if let date = request.dueDate {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        }

        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw CommandExecutionError.operationFailed("Could not create reminder: \(error.localizedDescription)")
        }
    }

    func completeReminder(_ request: ReminderCompleteRequest) throws {
        try ensureRemindersAccess()

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)

        let semaphore = DispatchSemaphore(value: 0)
        var foundReminders: [EKReminder] = []

        eventStore.fetchReminders(matching: predicate) { found in
            let results = (found ?? []).filter { $0.title?.localizedCaseInsensitiveCompare(request.title) == .orderedSame }
            foundReminders = results
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5.0)

        if foundReminders.isEmpty {
            throw CommandExecutionError.operationFailed("No incomplete reminder found matching \"\(request.title)\".")
        }

        if foundReminders.count > 1 {
            throw CommandExecutionError.operationFailed("Multiple reminders match \"\(request.title)\". Please be more specific.")
        }

        let reminder = foundReminders[0]
        reminder.isCompleted = true

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw CommandExecutionError.operationFailed("Could not complete reminder: \(error.localizedDescription)")
        }
    }

    func deleteReminder(_ request: ReminderDeleteRequest) throws {
        try ensureRemindersAccess()

        let predicate = eventStore.predicateForReminders(in: nil)

        let semaphore = DispatchSemaphore(value: 0)
        var foundReminders: [EKReminder] = []

        eventStore.fetchReminders(matching: predicate) { found in
            let results = (found ?? []).filter { $0.title?.localizedCaseInsensitiveCompare(request.title) == .orderedSame }
            foundReminders = results
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5.0)

        if foundReminders.isEmpty {
            throw CommandExecutionError.operationFailed("No reminder found matching \"\(request.title)\".")
        }

        if foundReminders.count > 1 {
            throw CommandExecutionError.operationFailed("Multiple reminders match \"\(request.title)\". Please be more specific.")
        }

        do {
            try eventStore.remove(foundReminders[0], commit: true)
        } catch {
            throw CommandExecutionError.operationFailed("Could not delete reminder: \(error.localizedDescription)")
        }
    }

    private func ensureRemindersAccess() throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                return
            }
        } else {
            if status == .authorized {
                return
            }
        }

        if status == .denied || status == .restricted {
            throw CommandExecutionError.operationFailed("Reminders access is denied. Enable it in System Settings → Privacy & Security → Reminders.")
        }

        if status == .notDetermined {
            let accessGranted = OSAllocatedUnfairLock(initialState: false)
            let semaphore = DispatchSemaphore(value: 0)
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToReminders { granted, _ in
                    accessGranted.withLock { $0 = granted }
                    semaphore.signal()
                }
            } else {
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    accessGranted.withLock { $0 = granted }
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + 5.0)
            guard accessGranted.withLock({ $0 }) else {
                throw CommandExecutionError.operationFailed("Reminders access is required. DailyOps needs Reminders access to create and view reminders.")
            }
            return
        }

        throw CommandExecutionError.operationFailed("Reminders access is unavailable.")
    }
}

/// Fake Reminders controller for tests.
@MainActor
final class FakeRemindersControl: RemindersControlling {
    var opened: Bool = false
    var remindersToReturn: [ReminderSummary] = []
    var createdReminders: [ReminderRequest] = []
    var completedReminders: [ReminderCompleteRequest] = []
    var deletedReminders: [ReminderDeleteRequest] = []
    var shouldFailWithAccessDenied: Bool = false

    func openReminders() throws {
        opened = true
    }

    func fetchReminders(for query: ReminderQuery) throws -> [ReminderSummary] {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Reminders access is required to view reminders.")
        }
        return remindersToReturn
    }

    func createReminder(_ request: ReminderRequest) throws {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Reminders access is required to create reminders.")
        }
        createdReminders.append(request)
    }

    func completeReminder(_ request: ReminderCompleteRequest) throws {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Reminders access is required to complete reminders.")
        }
        completedReminders.append(request)
    }

    func deleteReminder(_ request: ReminderDeleteRequest) throws {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Reminders access is required to delete reminders.")
        }
        deletedReminders.append(request)
    }
}

/// Executes Reminders commands.
@MainActor
struct RemindersCommandExecutor: CommandExecuting {
    private let control: RemindersControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .remindersOpen,
        .remindersList,
        .remindersCreate,
        .remindersComplete,
        .remindersDelete
    ]

    init(control: RemindersControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .remindersOpen:
            try control.openReminders()
            return "Opened Reminders"

        case .remindersList:
            guard case .reminderQuery(let query) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let reminders = try control.fetchReminders(for: query)
            let isToday = (query.dueDay == .today)
            let isOverdue = (query.dueDay == .specificDate)

            if reminders.isEmpty {
                if isOverdue {
                    return "No overdue reminders."
                }
                return isToday ? "No reminders due today." : "No reminders found."
            }

            if reminders.count == 1 {
                if isOverdue {
                    return "1 overdue reminder: \(reminders[0].title)."
                }
                return isToday ? "1 reminder due today: \(reminders[0].title)." : "1 reminder: \(reminders[0].title)."
            }

            let titles = reminders.prefix(3).map(\.title).joined(separator: ", ")
            if isOverdue {
                return "\(reminders.count) overdue reminders: \(titles)."
            }
            return isToday ? "\(reminders.count) reminders due today: \(titles)." : "\(reminders.count) reminders: \(titles)."

        case .remindersCreate:
            guard case .reminder(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.createReminder(request)
            return "Reminder created: \(request.title)"

        case .remindersComplete:
            guard case .reminderComplete(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.completeReminder(request)
            return "Reminder completed: \(request.title)"

        case .remindersDelete:
            guard case .reminderDelete(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.deleteReminder(request)
            return "Reminder deleted: \(request.title)"

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
