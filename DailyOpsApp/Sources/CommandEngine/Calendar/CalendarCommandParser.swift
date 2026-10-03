import Foundation

/// Parses Calendar voice commands into structured CommandPlans.
@MainActor
struct CalendarCommandParser: CommandParsing {
    private let dateTimeParser: DateTimeParser

    init(dateTimeParser: DateTimeParser = DateTimeParser()) {
        self.dateTimeParser = dateTimeParser
    }

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // 1. Open Calendar
        if isOpenCalendarCommand(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .calendarOpen))
        }

        // 2. Read / List Calendar Events
        if let query = parseListEventsCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .calendarListEvents,
                arguments: .calendarQuery(query)
            ))
        }

        // 3. Create Calendar Event
        if let eventRequest = parseCreateEventCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .calendarCreateEvent,
                arguments: .calendarEvent(eventRequest)
            ))
        }

        // 4. Delete / Cancel Calendar Event
        if let deleteRequest = parseDeleteEventCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .calendarDeleteEvent,
                arguments: .calendarDelete(deleteRequest)
            ))
        }

        return nil
    }

    // MARK: - Open Calendar

    private func isOpenCalendarCommand(_ lower: String) -> Bool {
        let openPhrases = [
            "open calendar", "launch calendar", "start calendar", "show calendar", "go to calendar", "open my calendar"
        ]
        return openPhrases.contains(lower)
    }

    // MARK: - Read Calendar

    private func parseListEventsCommand(raw: String, lower: String) -> CalendarQuery? {
        // "what's on my calendar today", "what is on my calendar today", "show my calendar", "what do I have today"
        // "what's on my calendar tomorrow", "show calendar for tomorrow", "what do I have tomorrow"
        // "show my events", "show events"
let isTodayQuery = lower == "what's on my calendar today"
            || lower == "what is on my calendar today"
            || lower == "what's on my calendar"
            || lower == "show my calendar"
            || lower == "show calendar"
            || lower == "show calendar today"
            || lower == "show my calendar today"
            || lower == "show my events"
            || lower == "show events"
            || lower == "show my events today"
            || lower == "show events today"
            || lower == "show today's events"
            || lower == "list my events"
            || lower == "list events"
            || lower == "what are my events today"
            || lower == "what are my events"
            || lower == "what do i have today"
            || lower == "what do i have on my calendar today"
            || lower == "what's my schedule today"
            || lower == "what is my schedule today"
            || lower == "my schedule today"
            || lower == "what's my schedule"
            || lower == "what is my schedule"
            || lower == "my schedule"
            || lower == "show today's calendar"
            || lower == "calendar today"

        if isTodayQuery {
            return CalendarQuery(day: .today)
        }

        let isTomorrowQuery = lower == "what's on my calendar tomorrow"
            || lower == "what is on my calendar tomorrow"
            || lower == "show my calendar tomorrow"
            || lower == "show calendar for tomorrow"
            || lower == "show calendar tomorrow"
            || lower == "show my events tomorrow"
            || lower == "show events tomorrow"
            || lower == "what are my events tomorrow"
            || lower == "what do i have tomorrow"
            || lower == "what do i have on my calendar tomorrow"
            || lower == "what's my schedule tomorrow"
            || lower == "what is my schedule tomorrow"
            || lower == "my schedule tomorrow"
            // New phrases for tomorrow
            || lower == "calendar tomorrow"

        if isTomorrowQuery {
            return CalendarQuery(day: .tomorrow)
        }

        // Next meeting / next event
        if lower == "what's my next meeting"
            || lower == "what is my next meeting"
            || lower == "whats my next meeting"
            || lower == "what's my next event"
            || lower == "what is my next event"
            || lower == "show my next meeting"
            || lower == "show next meeting"
            || lower == "next meeting"
            || lower == "next event"
            // New phrases for next meeting
            || lower == "when is my next meeting" {
            return CalendarQuery(day: .next)
        }

        // This week
        if lower == "what's on my calendar this week"
            || lower == "what is on my calendar this week"
            || lower == "show my calendar this week"
            || lower == "show calendar this week"
            || lower == "what do i have this week"
            || lower == "my schedule this week"
            || lower == "what's my schedule this week"
            || lower == "what is my schedule this week"
            // New phrases for this week
            || lower == "calendar this week" {
            return CalendarQuery(day: .thisWeek)
        }

        // Afternoon queries
        let isAfternoonQuery = lower == "show my afternoon meetings"
            || lower == "what meetings do i have this afternoon"
            || lower == "what's on my calendar this afternoon"
            || lower == "what is on my calendar this afternoon"
            || lower == "show my calendar this afternoon"
            || lower == "what do i have this afternoon"
            || lower == "what's my afternoon schedule"
            || lower == "what is my afternoon schedule"
            || lower == "my afternoon schedule"
            || lower == "show afternoon meetings"

        if isAfternoonQuery {
            return CalendarQuery(day: .afternoon)
        }

        // Generic "what's on my calendar" or "check calendar" or "show calendar" or "show events"
        if lower.hasPrefix("what's on my calendar")
            || lower.hasPrefix("what is on my calendar")
            || lower.hasPrefix("show calendar")
            || lower.hasPrefix("check calendar")
            || lower.hasPrefix("check my calendar")
            || lower.hasPrefix("show events")
            || lower.hasPrefix("show my events")
            || lower.hasPrefix("list events")
            || lower.hasPrefix("list my events") {
            let target = dateTimeParser.parseDayTarget(from: lower) ?? .today
            var resolvedDate: Date? = nil
            if target == .specificDate {
                let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
                for day in weekdays {
                    if lower.contains(day) {
                        resolvedDate = dateTimeParser.resolveDate(from: day)
                        break
                    }
                }
            }
            return CalendarQuery(day: target, date: resolvedDate)
        }

        return nil
    }

    // MARK: - Create Calendar Event

    private func parseCreateEventCommand(raw: String, lower: String) -> CalendarEventRequest? {
        var contentClause: String? = nil
        var matchedPrefix: String? = nil

        let createPrefixes = [
            "create a calendar event called ",
            "create a calendar event named ",
            "create a calendar event ",
            "create calendar event called ",
            "create calendar event named ",
            "create calendar event ",
            "create an event called ",
            "create an event named ",
            "create an event ",
            "create event called ",
            "create event named ",
            "create event ",
            "add an event called ",
            "add an event named ",
            "add an event ",
            "add event called ",
            "add event named ",
            "add event ",
            "schedule a calendar event called ",
            "schedule a calendar event ",
            "schedule a meeting called ",
            "schedule a meeting named ",
            "schedule a meeting ",
            "schedule an event called ",
            "schedule an event named ",
            "schedule an event ",
            "schedule "
        ]

        for prefix in createPrefixes {
            if lower.hasPrefix(prefix) {
                matchedPrefix = prefix
                contentClause = String(raw.dropFirst(prefix.count))
                break
            }
        }

        // Check "add <Rest> to my calendar" or "add <Rest> to calendar"
        if contentClause == nil {
            if lower.hasPrefix("add ") {
                if let range = lower.range(of: " to my calendar", options: .backwards) {
                    let inside = String(raw[raw.index(raw.startIndex, offsetBy: 4)..<range.lowerBound])
                    contentClause = inside
                    matchedPrefix = "add to calendar"
                } else if let range = lower.range(of: " to calendar", options: .backwards) {
                    let inside = String(raw[raw.index(raw.startIndex, offsetBy: 4)..<range.lowerBound])
                    contentClause = inside
                    matchedPrefix = "add to calendar"
                }
            }
        }

        guard let clause = contentClause?.trimmingCharacters(in: .whitespacesAndNewlines), !clause.isEmpty else {
            return nil
        }

        let defaultTitle: String?
        if let prefix = matchedPrefix {
            if prefix.contains("meeting") {
                defaultTitle = "Meeting"
            } else if prefix.contains("event") {
                defaultTitle = "Event"
            } else {
                defaultTitle = nil
            }
        } else {
            defaultTitle = nil
        }

        if let details = dateTimeParser.extractEventDetails(from: clause, defaultTitle: defaultTitle) {
            return CalendarEventRequest(
                title: details.title,
                date: details.date,
                startTime: details.startTime,
                duration: details.duration
            )
        }

        return nil
    }

    // MARK: - Delete Calendar Event

    private func parseDeleteEventCommand(raw: String, lower: String) -> CalendarEventDeleteRequest? {
        // "cancel my 3 PM meeting"
        // "cancel my meeting at 3 PM"
        // "delete my 3 PM meeting"
        // "delete my meeting at 3 PM"
        // "cancel the 3 PM meeting"
        // "delete the meeting at 3 PM"

        let cancelPrefixes = [
            "cancel my ",
            "cancel the ",
            "delete my ",
            "delete the "
        ]

        for prefix in cancelPrefixes {
            if lower.hasPrefix(prefix) {
                let clause = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if clause.isEmpty { continue }

                // Extract title and time from the clause using dateTimeParser
                if let details = dateTimeParser.extractEventDetails(from: clause, defaultTitle: nil) {
                    return CalendarEventDeleteRequest(
                        title: details.title,
                        date: details.date,
                        startTime: details.startTime
                    )
                }

                // Fallback: just use the clause as title
                return CalendarEventDeleteRequest(title: clause, date: nil, startTime: nil)
            }
        }

        return nil
    }
}
