import AppKit
import EventKit
import Foundation
import os

/// Summary of a calendar event for display to the user.
struct CalendarEventSummary: Equatable, Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

/// Abstract interface for Calendar operations.
@MainActor
protocol CalendarControlling: Sendable {
    func openCalendar() throws
    func fetchEvents(for query: CalendarQuery) throws -> [CalendarEventSummary]
    func createEvent(_ request: CalendarEventRequest) throws
    func deleteEvent(_ request: CalendarEventDeleteRequest) throws
}

/// Concrete Calendar controller using EventKit and NSWorkspace.
@MainActor
final class SystemCalendarControl: CalendarControlling {
    private let eventStore = EKEventStore()

    func openCalendar() throws {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: "ical:") {
            NSWorkspace.shared.open(url)
        } else {
            throw CommandExecutionError.operationFailed("Calendar application could not be opened.")
        }
    }

    func fetchEvents(for query: CalendarQuery) throws -> [CalendarEventSummary] {
        try ensureCalendarAccess()

        let calendar = Calendar.current
        let startDate: Date
        let endDate: Date

        switch query.day {
        case .today:
            startDate = calendar.startOfDay(for: Date())
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .tomorrow:
            startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .specificDate:
            startDate = calendar.startOfDay(for: query.date ?? Date())
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .next:
            startDate = Date()
            endDate = calendar.date(byAdding: .day, value: 365, to: startDate) ?? startDate
        case .thisWeek:
            // ISO week: Monday 00:00 through next Monday 00:00
            var isoCalendar = Calendar(identifier: .iso8601)
            isoCalendar.timeZone = calendar.timeZone
            let startOfISOWeek = isoCalendar.date(from: isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? calendar.startOfDay(for: Date())
            startDate = startOfISOWeek
            endDate = isoCalendar.date(byAdding: .day, value: 7, to: startOfISOWeek) ?? startOfISOWeek
        case .afternoon:
            let today = calendar.startOfDay(for: Date())
            guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today),
                  let fivePM = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today) else {
                throw CommandExecutionError.operationFailed("Could not calculate afternoon time range.")
            }
            startDate = noon
            endDate = fivePM
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let summaries = events.map { event in
            CalendarEventSummary(
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay
            )
        }

        // For "next" query, return only the single next upcoming event
        if query.day == .next {
            let now = Date()
            let upcomingEvents = summaries.filter { event in
                // Event qualifies if it hasn't ended yet (endDate > now)
                // This includes events currently in progress and future events
                event.endDate > now
            }.sorted { $0.startDate < $1.startDate }

            // Return only the earliest upcoming event
            if let nextEvent = upcomingEvents.first {
                return [nextEvent]
            }
            return []
        }

        return summaries
    }

    func createEvent(_ request: CalendarEventRequest) throws {
        try ensureCalendarAccess()

        let event = EKEvent(eventStore: eventStore)
        event.title = request.title

        let calendar = Calendar.current
        let startDate: Date
        if let time = request.startTime {
            startDate = time
        } else {
            startDate = request.date
        }

        let duration = request.duration ?? 3600 // Default to 1 hour
        let endDate = calendar.date(byAdding: .second, value: Int(duration), to: startDate) ?? startDate.addingTimeInterval(duration)

        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = (request.startTime == nil)
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw CommandExecutionError.operationFailed("Could not save calendar event: \(error.localizedDescription)")
        }
    }

    func deleteEvent(_ request: CalendarEventDeleteRequest) throws {
        try ensureCalendarAccess()

        let calendar = Calendar.current
        let searchStart: Date
        if let date = request.date {
            searchStart = calendar.startOfDay(for: date)
        } else {
            searchStart = calendar.startOfDay(for: Date())
        }
        guard let searchEnd = calendar.date(byAdding: .day, value: 1, to: searchStart) else {
            throw CommandExecutionError.operationFailed("Could not calculate date range for calendar.")
        }

        let predicate = eventStore.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: nil)
        let events = eventStore.events(matching: predicate)

        // Find matching events by title and optionally start time
        let matches = events.filter { event in
            let titleMatch = event.title?.localizedCaseInsensitiveCompare(request.title) == .orderedSame
            if let startTime = request.startTime {
                let timeMatch = calendar.compare(event.startDate, to: startTime, toGranularity: .minute) == .orderedSame
                return titleMatch && timeMatch
            }
            return titleMatch
        }

        if matches.isEmpty {
            throw CommandExecutionError.operationFailed("No matching calendar event found for \"\(request.title)\".")
        }

        if matches.count > 1 {
            let titles = matches.map { $0.title ?? "Untitled" }.joined(separator: ", ")
            throw CommandExecutionError.operationFailed("Multiple events match \"\(request.title)\" (\(titles)). Please specify the time.")
        }

        do {
            try eventStore.remove(matches[0], span: .thisEvent)
        } catch {
            throw CommandExecutionError.operationFailed("Could not delete calendar event: \(error.localizedDescription)")
        }
    }

    private func ensureCalendarAccess() throws {
        let status = EKEventStore.authorizationStatus(for: .event)
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
            throw CommandExecutionError.operationFailed("Calendar access is required to read your events.")
        }

        if status == .notDetermined {
            // Prompt access request synchronously
            let accessGranted = OSAllocatedUnfairLock(initialState: false)
            let semaphore = DispatchSemaphore(value: 0)
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { granted, _ in
                    accessGranted.withLock { $0 = granted }
                    semaphore.signal()
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, _ in
                    accessGranted.withLock { $0 = granted }
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + 5.0)
            guard accessGranted.withLock({ $0 }) else {
                throw CommandExecutionError.operationFailed("Calendar access is required to manage events.")
            }
            return
        }

        throw CommandExecutionError.operationFailed("Calendar access is unavailable.")
    }
}

/// Fake Calendar controller for tests.
@MainActor
final class FakeCalendarControl: CalendarControlling {
    var opened: Bool = false
    var eventsToReturn: [CalendarEventSummary] = []
    var createdEvents: [CalendarEventRequest] = []
    var deletedEvents: [CalendarEventDeleteRequest] = []
    var shouldFailWithAccessDenied: Bool = false

    func openCalendar() throws {
        opened = true
    }

    func fetchEvents(for query: CalendarQuery) throws -> [CalendarEventSummary] {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Calendar access is required to read your events.")
        }
        let events = eventsToReturn
        // For "next" query, filter to only the next upcoming event
        if query.day == .next {
            let now = Date()
            let upcomingEvents = events.filter { event in
                event.endDate > now
            }.sorted { $0.startDate < $1.startDate }
            if let nextEvent = upcomingEvents.first {
                return [nextEvent]
            }
            return []
        }
        // For "thisWeek" query, filter to events in the current ISO week (Monday-Sunday)
        if query.day == .thisWeek {
            let calendar = Calendar.current
            var isoCalendar = Calendar(identifier: .iso8601)
            isoCalendar.timeZone = calendar.timeZone
            let startOfISOWeek = isoCalendar.date(from: isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? calendar.startOfDay(for: Date())
            let endOfISOWeek = isoCalendar.date(byAdding: .day, value: 7, to: startOfISOWeek) ?? startOfISOWeek
            return events.filter { event in
                event.startDate >= startOfISOWeek && event.startDate < endOfISOWeek
            }
        }
        return events
    }

    func createEvent(_ request: CalendarEventRequest) throws {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Calendar access is required to read your events.")
        }
        createdEvents.append(request)
    }

    func deleteEvent(_ request: CalendarEventDeleteRequest) throws {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Calendar access is required to read your events.")
        }
        let calendar = Calendar.current
        let searchStart: Date
        if let date = request.date {
            searchStart = calendar.startOfDay(for: date)
        } else {
            searchStart = calendar.startOfDay(for: Date())
        }
        guard calendar.date(byAdding: .day, value: 1, to: searchStart) != nil else {
            throw CommandExecutionError.operationFailed("Could not calculate date range for calendar.")
        }

        let matches = eventsToReturn.filter { event in
            let titleMatch = event.title.localizedCaseInsensitiveCompare(request.title) == .orderedSame
            if let startTime = request.startTime {
                let timeMatch = calendar.compare(event.startDate, to: startTime, toGranularity: .minute) == .orderedSame
                return titleMatch && timeMatch
            }
            return titleMatch
        }

        if matches.isEmpty {
            throw CommandExecutionError.operationFailed("No matching calendar event found for \"\(request.title)\".")
        }

        if matches.count > 1 {
            let titles = matches.map { $0.title }.joined(separator: ", ")
            throw CommandExecutionError.operationFailed("Multiple events match \"\(request.title)\" (\(titles)). Please specify the time.")
        }

        deletedEvents.append(request)
    }
}

/// Executes Calendar commands.
@MainActor
struct CalendarCommandExecutor: CommandExecuting {
    private let control: CalendarControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .calendarOpen,
        .calendarListEvents,
        .calendarCreateEvent,
        .calendarDeleteEvent
    ]

    init(control: CalendarControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .calendarOpen:
            try control.openCalendar()
            return "Opened Calendar"

        case .calendarListEvents:
            guard case .calendarQuery(let query) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let events = try control.fetchEvents(for: query)
            let dayWord: String
            switch query.day {
            case .today: dayWord = "today"
            case .tomorrow: dayWord = "tomorrow"
            case .next: dayWord = "next"
            case .thisWeek: dayWord = "this week"
            case .afternoon: dayWord = "this afternoon"
            case .specificDate:
                if let date = query.date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    dayWord = "on \(formatter.string(from: date))"
                } else {
                    dayWord = "today"
                }
            }

            if events.isEmpty {
                return "No events scheduled for \(dayWord)."
            }

            if events.count == 1 {
                return "1 event \(dayWord): \(events[0].title)."
            }

            let titles = events.prefix(4).map(\.title).joined(separator: ", ")
            return "\(events.count) events \(dayWord): \(titles)."

        case .calendarCreateEvent:
            guard case .calendarEvent(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.createEvent(request)
            return "Calendar event created: \(request.title)"

        case .calendarDeleteEvent:
            guard case .calendarDelete(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            try control.deleteEvent(request)
            return "Calendar event deleted: \(request.title)"

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
