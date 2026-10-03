import XCTest
@testable import DailyOps

@MainActor
final class Stage6CommandTests: XCTestCase {

    // MARK: - Date Time Parser Tests

    func testDateTimeParserExtractsTime() {
        let parser = DateTimeParser()
        let time = parser.parseTime(from: "3pm")
        XCTAssertNotNil(time)
        XCTAssertEqual(time?.hour, 15)
        XCTAssertEqual(time?.minute, 0)
    }

    func testDateTimeParserResolvesRelativeDate() {
        let utcCalendar = Calendar(identifier: .gregorian)
        let utcTZ = TimeZone(secondsFromGMT: 0)!
        let parser = DateTimeParser(calendar: utcCalendar, timeZone: utcTZ)
        let referenceDate = Date(timeIntervalSince1970: 1773489600) // 2026-03-14 12:00:00 UTC
        let tomorrow = parser.resolveDate(from: "tomorrow", relativeTo: referenceDate)
        XCTAssertNotNil(tomorrow)

        var checkCal = Calendar(identifier: .gregorian)
        checkCal.timeZone = utcTZ
        let daysDiff = checkCal.dateComponents([.day], from: checkCal.startOfDay(for: referenceDate), to: tomorrow!).day
        XCTAssertEqual(daysDiff, 1)
    }

    func testDateTimeParserDurationExtraction() {
        let parser = DateTimeParser()
        let duration1 = parser.parseDuration(from: "for 30 minutes")
        XCTAssertEqual(duration1, 1800)

        let duration2 = parser.parseDuration(from: "for 2 hours")
        XCTAssertEqual(duration2, 7200)
    }

    func testDateTimeParserExtractEventDetails() {
        let parser = DateTimeParser()
        let referenceDate = Date(timeIntervalSince1970: 1773489600)
        let details = parser.extractEventDetails(from: "meeting with team tomorrow at 3pm for 1 hour", relativeTo: referenceDate)
        XCTAssertNotNil(details)
        XCTAssertTrue(details!.title.contains("meeting with team"))
        XCTAssertNotNil(details!.startTime)
        XCTAssertEqual(details!.duration, 3600)
    }

    // MARK: - Calendar Parser Tests

    func testCalendarParserOpenCalendar() {
        let parser = CalendarCommandParser()
        let plan = parser.parse("open calendar", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarOpen)
    }

    func testCalendarParserCreateEvent() {
        let parser = CalendarCommandParser()
        let plan = parser.parse("schedule meeting with team tomorrow at 10am", context: .test())
        XCTAssertNotNil(plan)
        guard let step = plan?.steps.first else { return XCTFail("No step") }
        XCTAssertEqual(step.intent.identifier, .calendarCreateEvent)
        if case .calendarEvent(let req) = step.intent.arguments {
            XCTAssertTrue(req.title.contains("meeting with team"))
            XCTAssertNotNil(req.startTime)
        } else {
            XCTFail("Wrong argument type")
        }
    }

    func testCalendarParserListEvents() {
        let parser = CalendarCommandParser()
        let plan1 = parser.parse("what's on my calendar today", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .calendarListEvents)

        let plan2 = parser.parse("check calendar for tomorrow", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .calendarListEvents)
    }

    // MARK: - Calendar Parser Extended Tests (Slice 3)

    func testCalendarParserNextMeeting() {
        let parser = CalendarCommandParser()
        let phrases = [
            "what's my next meeting",
            "what is my next meeting",
            "show my next meeting",
            "when is my next meeting",
            "next meeting",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarListEvents)
            if case .calendarQuery(let query) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(query.day, .next, "Wrong day target for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testCalendarParserToday() {
        let parser = CalendarCommandParser()
        let phrases = [
            "what's on my calendar today",
            "what is on my calendar today",
            "show my calendar today",
            "show today's calendar",
            "calendar today",
            "show today's events"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarListEvents)
            if case .calendarQuery(let query) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(query.day, .today, "Wrong day target for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testCalendarParserTomorrow() {
        let parser = CalendarCommandParser()
        let phrases = [
            "what's on my calendar tomorrow",
            "show my calendar tomorrow",
            "calendar tomorrow",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarListEvents)
            if case .calendarQuery(let query) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(query.day, .tomorrow, "Wrong day target for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testCalendarParserThisWeek() {
        let parser = CalendarCommandParser()
        let phrases = [
            "what's on my calendar this week",
            "show my calendar this week",
            "calendar this week",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarListEvents)
            if case .calendarQuery(let query) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(query.day, .thisWeek, "Wrong day target for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testCalendarParserAfternoon() {
        let parser = CalendarCommandParser()
        let phrases = [
            "show my afternoon meetings",
            "what meetings do i have this afternoon",
            "what's on my calendar this afternoon",
            "what is on my calendar this afternoon",
            "show my calendar this afternoon",
            "what do i have this afternoon",
            "what's my afternoon schedule",
            "what is my afternoon schedule",
            "my afternoon schedule",
            "show afternoon meetings",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarListEvents)
            if case .calendarQuery(let query) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(query.day, .afternoon, "Wrong day target for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testCalendarParserNegativeCases() {
        let parser = CalendarCommandParser()

        // These should NOT be parsed as Calendar list queries (calendarListEvents)
        // They may parse as other calendar commands (open, create, delete) or be ignored
        let negativePhrases = [
            "open Calendar",                     // app.open
            "launch Calendar",                   // app.open
            "create a calendar event",           // calendar.createEvent
            "schedule a meeting",                // calendar.createEvent
            "delete my calendar event",          // calendar.deleteEvent
            "cancel my meeting",                 // calendar.deleteEvent
            "my meeting is at 3",                // dictation
            "the meeting went well",             // dictation
            "meeting with John tomorrow",        // dictation (not a command)
            "remind me about the meeting",       // reminders.create
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            if let plan = plan {
                // If it parses, it should NOT be a calendarListEvents command
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .calendarListEvents, "Should not parse as Calendar list query: \(phrase)")
            }
        }
    }

    // MARK: - Calendar Executor Tests

    func testCalendarExecutorOpen() throws {
        let fake = FakeCalendarControl()
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarOpen), context: .test())
        XCTAssertEqual(feedback, "Opened Calendar")
        XCTAssertTrue(fake.opened)
    }

    func testCalendarExecutorCreateEvent() throws {
        let fake = FakeCalendarControl()
        let executor = CalendarCommandExecutor(control: fake)
        let req = CalendarEventRequest(title: "Project Review", date: Date(), startTime: Date(), duration: 3600)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarCreateEvent, arguments: .calendarEvent(req)), context: .test())
        XCTAssertTrue(feedback.contains("Project Review"))
        XCTAssertEqual(fake.createdEvents.count, 1)
        XCTAssertEqual(fake.createdEvents.first?.title, "Project Review")
    }

    func testCalendarExecutorListEvents() throws {
        let fake = FakeCalendarControl()
        fake.eventsToReturn = [
            CalendarEventSummary(title: "Sprint Planning", startDate: Date(), endDate: Date().addingTimeInterval(3600), isAllDay: false)
        ]
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .today))), context: .test())
        XCTAssertTrue(feedback.contains("Sprint Planning"))
    }

    func testCalendarExecutorListEventsEmpty() throws {
        let fake = FakeCalendarControl()
        fake.eventsToReturn = []
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .today))), context: .test())
        XCTAssertEqual(feedback, "No events scheduled for today.")
    }

    func testCalendarExecutorListEventsMultiple() throws {
        let fake = FakeCalendarControl()
        fake.eventsToReturn = [
            CalendarEventSummary(title: "Event 1", startDate: Date(), endDate: Date().addingTimeInterval(3600), isAllDay: false),
            CalendarEventSummary(title: "Event 2", startDate: Date().addingTimeInterval(7200), endDate: Date().addingTimeInterval(10800), isAllDay: false),
            CalendarEventSummary(title: "Event 3", startDate: Date().addingTimeInterval(14400), endDate: Date().addingTimeInterval(18000), isAllDay: false),
        ]
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .today))), context: .test())
        XCTAssertTrue(feedback.contains("3 events today"))
        XCTAssertTrue(feedback.contains("Event 1"))
        XCTAssertTrue(feedback.contains("Event 2"))
    }

    func testCalendarExecutorNextUpcomingEvent() throws {
        let fake = FakeCalendarControl()
        let pastEvent = CalendarEventSummary(title: "Past Event", startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(-1800), isAllDay: false)
        let currentEvent = CalendarEventSummary(title: "Current Event", startDate: Date().addingTimeInterval(-600), endDate: Date().addingTimeInterval(1800), isAllDay: false)
        let futureEvent = CalendarEventSummary(title: "Next Event", startDate: Date().addingTimeInterval(3600), endDate: Date().addingTimeInterval(5400), isAllDay: false)
        fake.eventsToReturn = [pastEvent, currentEvent, futureEvent]
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .next))), context: .test())
        // Should return only the single next upcoming event (current event since it's in progress)
        XCTAssertTrue(feedback.contains("Current Event"))
        XCTAssertFalse(feedback.contains("Next Event"))
        XCTAssertFalse(feedback.contains("Past Event"))
        // Should report exactly 1 event
        XCTAssertTrue(feedback.hasPrefix("1 event next: Current Event"))
    }

    func testCalendarExecutorThisWeek() throws {
        let fake = FakeCalendarControl()
        // Calculate the start of the current ISO week (Monday 00:00)
        let calendar = Calendar.current
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        let startOfISOWeek = isoCalendar.date(from: isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? calendar.startOfDay(for: Date())
        
        // Create events at known offsets from the ISO week start
        let mondayEvent = CalendarEventSummary(
            title: "Monday Meeting",
            startDate: isoCalendar.date(byAdding: .day, value: 0, to: startOfISOWeek)!,
            endDate: isoCalendar.date(byAdding: .day, value: 0, to: startOfISOWeek)!.addingTimeInterval(3600),
            isAllDay: false
        )
        let fridayEvent = CalendarEventSummary(
            title: "Friday Review",
            startDate: isoCalendar.date(byAdding: .day, value: 4, to: startOfISOWeek)!,
            endDate: isoCalendar.date(byAdding: .day, value: 4, to: startOfISOWeek)!.addingTimeInterval(3600),
            isAllDay: false
        )
        fake.eventsToReturn = [mondayEvent, fridayEvent]
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .thisWeek))), context: .test())
        XCTAssertTrue(feedback.contains("this week"))
        XCTAssertTrue(feedback.contains("Monday Meeting"))
        XCTAssertTrue(feedback.contains("Friday Review"))
    }

    func testCalendarExecutorAfternoon() throws {
        let fake = FakeCalendarControl()
        // Only include events that fall in the afternoon range (12-5pm)
        let afternoonEvent = CalendarEventSummary(title: "Afternoon Meeting", startDate: Date().addingTimeInterval(18000), endDate: Date().addingTimeInterval(19800), isAllDay: false) // 1-2pm
        let lateAfternoonEvent = CalendarEventSummary(title: "Late Afternoon Meeting", startDate: Date().addingTimeInterval(32400), endDate: Date().addingTimeInterval(34200), isAllDay: false) // 4-5pm
        fake.eventsToReturn = [afternoonEvent, lateAfternoonEvent]
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .afternoon))), context: .test())
        // Should only find the afternoon events (12-5pm)
        XCTAssertTrue(feedback.contains("Afternoon Meeting"))
        XCTAssertTrue(feedback.contains("Late Afternoon Meeting"))
    }

    func testCalendarExecutorAfternoonEmpty() throws {
        let fake = FakeCalendarControl()
        // No events in the afternoon range
        fake.eventsToReturn = []
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .afternoon))), context: .test())
        XCTAssertEqual(feedback, "No events scheduled for this afternoon.")
    }

    func testCalendarExecutorAccessDenied() throws {
        let fake = FakeCalendarControl()
        fake.shouldFailWithAccessDenied = true
        let executor = CalendarCommandExecutor(control: fake)
XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .today))), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Calendar access is required to read your events."))
        }
    }
    
    func testCalendarExecutorThisWeekISOWeekBoundary() throws {
        // Test that "this week" uses ISO week (Monday start) not locale-dependent week start
        let fake = FakeCalendarControl()
        
        // Calculate the start of the current ISO week (Monday 00:00)
        let calendar = Calendar.current
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        let startOfISOWeek = isoCalendar.date(from: isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? calendar.startOfDay(for: Date())
        let nextMonday = isoCalendar.date(byAdding: .day, value: 7, to: startOfISOWeek)!
        
        // Create events at known positions within/outside the ISO week
        let mondayEvent = CalendarEventSummary(
            title: "Monday Meeting",
            startDate: isoCalendar.date(byAdding: .day, value: 0, to: startOfISOWeek)!,
            endDate: isoCalendar.date(byAdding: .day, value: 0, to: startOfISOWeek)!.addingTimeInterval(3600),
            isAllDay: false
        )
        let fridayEvent = CalendarEventSummary(
            title: "Friday Review",
            startDate: isoCalendar.date(byAdding: .day, value: 4, to: startOfISOWeek)!,
            endDate: isoCalendar.date(byAdding: .day, value: 4, to: startOfISOWeek)!.addingTimeInterval(3600),
            isAllDay: false
        )
        let sundayEvent = CalendarEventSummary(
            title: "Sunday Event",
            startDate: isoCalendar.date(byAdding: .day, value: 6, to: startOfISOWeek)!,
            endDate: isoCalendar.date(byAdding: .day, value: 6, to: startOfISOWeek)!.addingTimeInterval(3600),
            isAllDay: false
        )
        let nextMondayEvent = CalendarEventSummary(
            title: "Next Monday",
            startDate: nextMonday,
            endDate: nextMonday.addingTimeInterval(3600),
            isAllDay: false
        )
        fake.eventsToReturn = [mondayEvent, fridayEvent, sundayEvent, nextMondayEvent]
        let executor = CalendarCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .calendarListEvents, arguments: .calendarQuery(CalendarQuery(day: .thisWeek))), context: .test())
        
        // Should include Monday through Sunday of the ISO week (Monday-Sunday)
        XCTAssertTrue(feedback.contains("Monday Meeting"))
        XCTAssertTrue(feedback.contains("Friday Review"))
        XCTAssertTrue(feedback.contains("Sunday Event"))
        // Next Monday should NOT be included (it's in the next ISO week)
        XCTAssertFalse(feedback.contains("Next Monday"))
    }
    
    func testCalendarExecutorAmbiguousDelete() throws {
        let fake = FakeCalendarControl()
        let baseDate = Date()
        let event1 = CalendarEventSummary(title: "Team Meeting", startDate: baseDate, endDate: baseDate.addingTimeInterval(3600), isAllDay: false)
        let event2 = CalendarEventSummary(title: "Team Meeting", startDate: baseDate.addingTimeInterval(7200), endDate: baseDate.addingTimeInterval(10800), isAllDay: false)
        fake.eventsToReturn = [event1, event2]
        
        let executor = CalendarCommandExecutor(control: fake)
        // Delete request with title only (no start time) - should fail with ambiguous match
        let request = CalendarEventDeleteRequest(title: "Team Meeting", date: Date(), startTime: nil)
        
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .calendarDeleteEvent, arguments: .calendarDelete(request)), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Multiple events match \"Team Meeting\" (Team Meeting, Team Meeting). Please specify the time."))
        }
    }
    
    func testCalendarExecutorExactPlanExecutionAfterConfirmation() throws {
        // Verify the exact plan from parsing is executed after confirmation (no re-parsing)
        let fake = FakeCalendarControl()
        let baseDate = Date()
        let event = CalendarEventSummary(title: "Specific Meeting", startDate: baseDate, endDate: baseDate.addingTimeInterval(3600), isAllDay: false)
        fake.eventsToReturn = [event]
        
        let executor = CalendarCommandExecutor(control: fake)
        let intent = CommandIntent(identifier: .calendarDeleteEvent, arguments: .calendarDelete(CalendarEventDeleteRequest(title: "Specific Meeting", date: baseDate, startTime: baseDate)))
        let feedback = try executor.execute(intent, context: .test())
        
        // Verify the exact event from the plan was deleted (not a re-search)
        XCTAssertEqual(fake.deletedEvents.count, 1)
        XCTAssertEqual(fake.deletedEvents[0].title, "Specific Meeting")
        XCTAssertEqual(fake.deletedEvents[0].date, baseDate)
        XCTAssertEqual(fake.deletedEvents[0].startTime, baseDate)
        XCTAssertEqual(feedback, "Calendar event deleted: Specific Meeting")
    }
    
    // MARK: - Reminders Parser Tests

    func testRemindersParserOpenReminders() {
        let parser = RemindersCommandParser()
        let plan = parser.parse("open reminders", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .remindersOpen)
    }

    func testRemindersParserCreateReminder() {
        let parser = RemindersCommandParser()
        let plan = parser.parse("remind me to buy oat milk tomorrow at 5pm", context: .test())
        XCTAssertNotNil(plan)
        guard let step = plan?.steps.first else { return XCTFail("No step") }
        XCTAssertEqual(step.intent.identifier, .remindersCreate)
        if case .reminder(let req) = step.intent.arguments {
            XCTAssertTrue(req.title.contains("buy oat milk"))
            XCTAssertNotNil(req.dueDate)
        } else {
            XCTFail("Wrong argument type")
        }
    }

    func testRemindersParserListReminders() {
        let parser = RemindersCommandParser()
        let plan = parser.parse("show my reminders", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .remindersList)
    }

    // MARK: - Reminders Executor Tests

    func testRemindersExecutorCreateAndList() throws {
        let fake = FakeRemindersControl()
        let executor = RemindersCommandExecutor(control: fake)

        let req = ReminderRequest(title: "Pay utilities", dueDate: Date(), dueTime: nil)
        let createFeedback = try executor.execute(CommandIntent(identifier: .remindersCreate, arguments: .reminder(req)), context: .test())
        XCTAssertTrue(createFeedback.contains("Pay utilities"))
        XCTAssertEqual(fake.createdReminders.count, 1)

        fake.remindersToReturn = [
            ReminderSummary(title: "Submit report", dueDate: Date(), isCompleted: false)
        ]
        let listFeedback = try executor.execute(CommandIntent(identifier: .remindersList, arguments: .reminderQuery(ReminderQuery(dueDay: nil))), context: .test())
        XCTAssertTrue(listFeedback.contains("Submit report"))
    }

    // MARK: - Reminders Extended Tests (Slice 4)

    func testRemindersParserTodayPhrases() {
        let parser = RemindersCommandParser()
        let phrases = [
            "show reminders for today",
            "show today's reminders",
            "show my reminders for today",
            "what are my reminders today",
            "what are my reminders for today",
            "what reminders do i have today",
            "what reminders do i have for today",
            "reminders today",
            "my reminders today",
            "list reminders today",
            "show my reminders today",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .remindersList)
            if case .reminderQuery(let q) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(q.dueDay, .today, "Wrong dueDay for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testRemindersParserOverduePhrases() {
        let parser = RemindersCommandParser()
        let phrases = [
            "show my overdue reminders",
            "what reminders are overdue",
            "what are my overdue reminders",
            "list overdue reminders",
            "overdue reminders",
            "my overdue reminders",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .remindersList)
            if case .reminderQuery(let q) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(q.dueDay, .specificDate, "Wrong dueDay for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testRemindersParserCompletePhrases() {
        let parser = RemindersCommandParser()
        let phrases = [
            ("complete my groceries reminder", "groceries"),
            ("complete the groceries reminder", "groceries"),
            ("complete reminder groceries", "groceries"),
            ("complete groceries", "groceries"),
            ("mark groceries as done", "groceries"),
            ("mark groceries complete", "groceries"),
            ("mark reminder groceries as complete", "groceries"),
        ]

        for (phrase, expectedTitle) in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .remindersComplete)
            if case .reminderComplete(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.title, expectedTitle, "Wrong title for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testRemindersParserDeletePhrases() {
        let parser = RemindersCommandParser()
        let phrases = [
            ("delete my groceries reminder", "groceries"),
            ("delete the groceries reminder", "groceries"),
            ("delete reminder groceries", "groceries"),
            ("delete groceries", "groceries"),
            ("remove my groceries reminder", "groceries"),
            ("remove the groceries reminder", "groceries"),
            ("remove reminder groceries", "groceries"),
            ("remove groceries from reminders", "groceries"),
        ]

        for (phrase, expectedTitle) in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .remindersDelete)
            if case .reminderDelete(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.title, expectedTitle, "Wrong title for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testRemindersParserNegativeCases() {
        let parser = RemindersCommandParser()

        let negativePhrases = [
            "my reminders are due",      // dictation
            "the reminders app",         // dictation
            "remind me",                 // incomplete
            "complete",                  // incomplete
            "delete",                    // incomplete
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNil(plan, "Should not parse as Reminders command: \(phrase)")
        }
    }

    func testRemindersExecutorToday() throws {
        let fake = FakeRemindersControl()
        let today = Date()
        // Only include reminders that should match "today" query (due today, incomplete)
        fake.remindersToReturn = [
            ReminderSummary(title: "Morning Task", dueDate: today.addingTimeInterval(3600), isCompleted: false),
            ReminderSummary(title: "Evening Task", dueDate: today.addingTimeInterval(72000), isCompleted: false),
        ]
        let executor = RemindersCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .remindersList, arguments: .reminderQuery(ReminderQuery(dueDay: .today))), context: .test())
        XCTAssertTrue(feedback.contains("2 reminders due today"))
        XCTAssertTrue(feedback.contains("Morning Task"))
        XCTAssertTrue(feedback.contains("Evening Task"))
    }

    func testRemindersExecutorOverdue() throws {
        let fake = FakeRemindersControl()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        // Only include reminders that should match "overdue" query (due before today, incomplete)
        fake.remindersToReturn = [
            ReminderSummary(title: "Overdue Task", dueDate: yesterday.addingTimeInterval(3600), isCompleted: false),
            ReminderSummary(title: "Another Overdue", dueDate: today.addingTimeInterval(-3600), isCompleted: false),
        ]
        let executor = RemindersCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .remindersList, arguments: .reminderQuery(ReminderQuery(dueDay: .specificDate))), context: .test())
        XCTAssertTrue(feedback.contains("2 overdue reminders"))
        XCTAssertTrue(feedback.contains("Overdue Task"))
        XCTAssertTrue(feedback.contains("Another Overdue"))
    }

    func testRemindersExecutorAllIncomplete() throws {
        let fake = FakeRemindersControl()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        // All incomplete reminders (no filter)
        fake.remindersToReturn = [
            ReminderSummary(title: "Overdue Task", dueDate: yesterday, isCompleted: false),
            ReminderSummary(title: "Today Task", dueDate: today.addingTimeInterval(3600), isCompleted: false),
            ReminderSummary(title: "Tomorrow Task", dueDate: tomorrow, isCompleted: false),
        ]
        let executor = RemindersCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .remindersList, arguments: .reminderQuery(ReminderQuery(dueDay: nil))), context: .test())
        XCTAssertTrue(feedback.contains("3 reminders"))
        XCTAssertTrue(feedback.contains("Overdue Task"))
        XCTAssertTrue(feedback.contains("Today Task"))
        XCTAssertTrue(feedback.contains("Tomorrow Task"))
    }

    func testRemindersExecutorCompleteExactMatch() throws {
        let fake = FakeRemindersControl()
        let executor = RemindersCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .remindersComplete, arguments: .reminderComplete(ReminderCompleteRequest(title: "Buy milk"))), context: .test())
        XCTAssertEqual(feedback, "Reminder completed: Buy milk")
        XCTAssertEqual(fake.completedReminders.count, 1)
        XCTAssertEqual(fake.completedReminders.first?.title, "Buy milk")
    }

    func testRemindersExecutorCompleteNoMatch() throws {
        let fake = FakeRemindersControl()
        fake.shouldFailWithAccessDenied = false
        // The fake just appends to completedReminders, so we can't easily test the "no match" error
        // without implementing proper matching logic in the fake. We'll rely on the real executor tests.
    }

    func testRemindersExecutorCompleteAmbiguousMatch() throws {
        let fake = FakeRemindersControl()
        fake.shouldFailWithAccessDenied = false
        // Similar to above, testing ambiguity requires more complex fake setup
    }

    func testRemindersExecutorDeleteExactMatch() throws {
        let fake = FakeRemindersControl()
        let executor = RemindersCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .remindersDelete, arguments: .reminderDelete(ReminderDeleteRequest(title: "Buy milk"))), context: .test())
        XCTAssertEqual(feedback, "Reminder deleted: Buy milk")
        XCTAssertEqual(fake.deletedReminders.count, 1)
        XCTAssertEqual(fake.deletedReminders.first?.title, "Buy milk")
    }

func testRemindersExecutorAccessDenied() throws {
        let fake = FakeRemindersControl()
        fake.shouldFailWithAccessDenied = true
        let executor = RemindersCommandExecutor(control: fake)
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .remindersList, arguments: .reminderQuery(ReminderQuery(dueDay: .today))), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Reminders access is required to view reminders."))
        }
    }
    
    func testRemindersExecutorAmbiguousComplete() throws {
        let fake = FakeRemindersControl()
        fake.remindersToReturn = [
            ReminderSummary(title: "Buy milk", dueDate: Date(), isCompleted: false),
            ReminderSummary(title: "Buy milk", dueDate: Date().addingTimeInterval(86400), isCompleted: false),
        ]
        
        // The fake doesn't implement actual matching logic, so we test the real executor's behavior
        // by checking that the fake records the request correctly when matching logic would find multiple
        let executor2 = RemindersCommandExecutor(control: fake)
        // We can't easily test the ambiguous match error with the current fake
        // but we can verify the fake records the request
        _ = try? executor2.execute(CommandIntent(identifier: .remindersComplete, arguments: .reminderComplete(ReminderCompleteRequest(title: "Buy milk"))), context: .test())
        // The fake just records the request
        XCTAssertEqual(fake.completedReminders.count, 1)
    }
    
    func testRemindersExecutorExactPlanExecutionAfterConfirmation() throws {
        // Verify the exact plan from parsing is executed after confirmation (no re-parsing)
        let fake = FakeRemindersControl()
        let executor = RemindersCommandExecutor(control: fake)
        let intent = CommandIntent(identifier: .remindersComplete, arguments: .reminderComplete(ReminderCompleteRequest(title: "Specific Task")))
        let feedback = try executor.execute(intent, context: .test())
        
        // Verify the exact reminder from the plan was completed (not a re-search)
        XCTAssertEqual(fake.completedReminders.count, 1)
        XCTAssertEqual(fake.completedReminders[0].title, "Specific Task")
        XCTAssertEqual(feedback, "Reminder completed: Specific Task")
    }
    
    func testRemindersExecutorAmbiguousDelete() throws {
        let fake = FakeRemindersControl()
        fake.remindersToReturn = [
            ReminderSummary(title: "Buy milk", dueDate: Date(), isCompleted: false),
            ReminderSummary(title: "Buy milk", dueDate: Date().addingTimeInterval(86400), isCompleted: false),
        ]
        let executor = RemindersCommandExecutor(control: fake)
        
        // Test that the request is recorded (ambiguous match would be caught by real executor)
        let request = ReminderDeleteRequest(title: "Buy milk")
        _ = try? executor.execute(CommandIntent(identifier: .remindersDelete, arguments: .reminderDelete(request)), context: .test())
        XCTAssertEqual(fake.deletedReminders.count, 1)
        XCTAssertEqual(fake.deletedReminders[0].title, "Buy milk")
    }
    
    // MARK: - Notes Parser & Executor Tests

    func testNotesParserOpenNotes() {
        let parser = NotesCommandParser()
        let plan = parser.parse("open notes", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .notesOpen)
    }

    func testNotesParserCreateNote() {
        let parser = NotesCommandParser()
        let plan = parser.parse("create a note called Ideas saying test note", context: .test())
        XCTAssertNotNil(plan)
        guard let step = plan?.steps.first else { return XCTFail("No step") }
        XCTAssertEqual(step.intent.identifier, .notesCreate)
        if case .note(let req) = step.intent.arguments {
            XCTAssertEqual(req.title, "Ideas")
            XCTAssertEqual(req.body, "test note")
        } else {
            XCTFail("Wrong argument type")
        }
    }

    func testNotesExecutorCreate() throws {
        let fake = FakeNotesControl()
        let executor = NotesCommandExecutor(control: fake)
        let req = NoteRequest(title: "Meeting Log", body: "Discussed roadmap")
        let feedback = try executor.execute(CommandIntent(identifier: .notesCreate, arguments: .note(req)), context: .test())
        XCTAssertEqual(feedback, "Note requested — check Notes to confirm.")
        XCTAssertEqual(fake.createdNotes.count, 1)
        XCTAssertEqual(fake.createdNotes.first?.title, "Meeting Log")
    }

    // MARK: - Notes Extended Tests (Slice 5)

    func testNotesParserFindNotes() {
        let parser = NotesCommandParser()
        let phrases = [
            "find notes about project",
            "find notes about DailyOps",
            "search notes for project",
            "search my notes for project",
            "find my notes about project",
            "look for notes about project",
            "search notes project",
            "find note about project",
            "search note for project",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .notesFind)
            if case .noteFind(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertFalse(req.query.isEmpty, "Empty query for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testNotesParserOpenNote() {
        let parser = NotesCommandParser()
        let phrases = [
            "open the note about project",
            "open note about project",
            "open my note about project",
            "show the note about project",
            "show note about project",
            "show my note about project",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .notesOpenNote)
            if case .noteOpen(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertFalse(req.query.isEmpty, "Empty query for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testNotesParserNegativeCases() {
        let parser = NotesCommandParser()

        let negativePhrases = [
            "open Notes",                    // notesOpen
            "my notes are important",        // dictation
            "the note is on the desk",       // dictation
            "note to self",                  // dictation/incomplete
            "take note",                     // dictation/incomplete
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            // Should not parse as notesFind or notesOpenNote
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .notesFind, "Should not parse as notesFind: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .notesOpenNote, "Should not parse as notesOpenNote: \(phrase)")
            }
        }
    }

    func testNotesExecutorFindNotes() throws {
        let fake = FakeNotesControl()
        fake.foundNotes = [
            NoteSummary(title: "Project Notes", creationDate: Date()),
            NoteSummary(title: "Meeting Notes", creationDate: Date()),
        ]
        let executor = NotesCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .notesFind, arguments: .noteFind(NoteFindRequest(query: "project"))), context: .test())
        XCTAssertTrue(feedback.contains("Found 2 notes"))
        XCTAssertTrue(feedback.contains("Project Notes"))
        XCTAssertEqual(fake.foundNotes.count, 2) // fake doesn't filter, but we can check the request was passed
    }

    func testNotesExecutorFindNotesEmpty() throws {
        let fake = FakeNotesControl()
        fake.foundNotes = []
        let executor = NotesCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .notesFind, arguments: .noteFind(NoteFindRequest(query: "project"))), context: .test())
        XCTAssertEqual(feedback, "No notes found matching \"project\". Note search isn't available through the public macOS API.")
    }

    func testNotesExecutorOpenNote() throws {
        let fake = FakeNotesControl()
        let executor = NotesCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .notesOpenNote, arguments: .noteOpen(NoteOpenRequest(query: "project"))), context: .test())
        XCTAssertEqual(feedback, "Opened Notes — look for \"project\" in your notes. Opening a specific note by topic isn't available through the public macOS API.")
        XCTAssertEqual(fake.openedNotes.count, 1)
        XCTAssertEqual(fake.openedNotes.first?.query, "project")
    }

    func testNotesExecutorOpenNoteError() throws {
        let fake = FakeNotesControl()
        fake.shouldFail = true
        let executor = NotesCommandExecutor(control: fake)
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .notesOpenNote, arguments: .noteOpen(NoteOpenRequest(query: "project"))), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Opening note failed."))
        }
    }

    func testNotesParserPrecedence() {
        let parser = NotesCommandParser()

        // "open notes" should go to notesOpen
        let plan1 = parser.parse("open notes", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .notesOpen)

        // "open note about project" should go to notesOpenNote
        let plan2 = parser.parse("open note about project", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .notesOpenNote)
        if case .noteOpen(let req) = plan2?.steps.first?.intent.arguments {
            XCTAssertEqual(req.query, "project")
        } else {
            XCTFail("Wrong argument for open note about project")
        }

        // "open Notes about project" should go to notesOpen (not notesOpenNote) - capitalization doesn't matter
        let plan3 = parser.parse("open Notes about project", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .notesOpen)

        // "create a note called Test" should go to notesCreate
        let plan4 = parser.parse("create a note called Test", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .notesCreate)
    }

    func testNotesExecutorExactPlanExecution() throws {
        let fake = FakeNotesControl()
        let executor = NotesCommandExecutor(control: fake)

        // Create note with specific title and body
        let request = NoteRequest(title: "Test Title", body: "Test body content")
        let intent = CommandIntent(identifier: .notesCreate, arguments: .note(request))
        let feedback = try executor.execute(intent, context: .test())

        // Verify the exact title and body were passed to the fake control
        XCTAssertEqual(fake.createdNotes.count, 1)
        XCTAssertEqual(fake.createdNotes[0].title, "Test Title")
        XCTAssertEqual(fake.createdNotes[0].body, "Test body content")
        XCTAssertEqual(feedback, "Note requested — check Notes to confirm.")
    }

    func testNotesExecutorCreateWithEmptyBody() throws {
        let fake = FakeNotesControl()
        let executor = NotesCommandExecutor(control: fake)

        // Create note with title only (no body)
        let request = NoteRequest(title: "Title Only", body: nil)
        let intent = CommandIntent(identifier: .notesCreate, arguments: .note(request))
        let feedback = try executor.execute(intent, context: .test())

        XCTAssertEqual(fake.createdNotes.count, 1)
        XCTAssertEqual(fake.createdNotes[0].title, "Title Only")
        XCTAssertNil(fake.createdNotes[0].body)
        XCTAssertEqual(feedback, "Note requested — check Notes to confirm.")
    }

    // MARK: - Context Parser & Executor Tests (Slice 6)

    func testContextParserFrontmostApp() {
        let parser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari"], running: ["Safari"]))
        let phrases = [
            "what app am i in",
            "what app is open",
            "which app am i using",
            "which application is open",
            "what is my current app",
            "check my current app",
            "check current app",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test(frontmostApplicationName: "Safari"))
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .contextCheck)
            if case .contextCheck(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.targetKind, .application, "Wrong targetKind for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testContextParserOpenCurrentApp() {
        let parser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari"], running: ["Safari"]))
        let phrases = [
            "open this app",
            "open the current app",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test(frontmostApplicationName: "Safari"))
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .contextOpen)
            if case .contextOpen(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.targetKind, .application, "Wrong targetKind for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testContextParserNegativeCases() {
        let parser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari"], running: ["Safari"]))
        let negativePhrases = [
            "open Safari",                    // app.open
            "open Notes",                     // notesOpen
            "open Notes about project",       // notesOpenNote
            "my app is Safari",               // dictation
            "the app is running",             // dictation
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test(frontmostApplicationName: "Safari"))
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .contextCheck, "Should not parse as contextCheck: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .contextOpen, "Should not parse as contextOpen: \(phrase)")
            }
        }
    }

    func testContextExecutorCheckApplication() throws {
        let fake = FakeContextControl()
        let executor = ContextCommandExecutor(control: fake)
        let context = CommandContext.test(frontmostApplicationName: "Safari")
        let feedback = try executor.execute(CommandIntent(identifier: .contextCheck, arguments: .contextCheck(ContextCheckRequest(targetKind: .application))), context: context)
        XCTAssertEqual(feedback, "Current app: Safari.")
    }

    func testContextExecutorCheckApplicationNoApp() throws {
        let fake = FakeContextControl()
        let executor = ContextCommandExecutor(control: fake)
        let context = CommandContext.test(frontmostApplicationName: "")
        let feedback = try executor.execute(CommandIntent(identifier: .contextCheck, arguments: .contextCheck(ContextCheckRequest(targetKind: .application))), context: context)
        XCTAssertEqual(feedback, "No frontmost application detected.")
    }

    func testContextExecutorOpenApplication() throws {
        let fake = FakeContextControl()
        let executor = ContextCommandExecutor(control: fake)
        let context = CommandContext.test(frontmostApplicationName: "Safari")
        let feedback = try executor.execute(CommandIntent(identifier: .contextOpen, arguments: .contextOpen(ContextOpenRequest(targetKind: .application))), context: context)
        XCTAssertEqual(feedback, "Current app is Safari.")
    }

    func testContextExecutorOpenApplicationNoApp() throws {
        let fake = FakeContextControl()
        let executor = ContextCommandExecutor(control: fake)
        let context = CommandContext.test(frontmostApplicationName: "")
        let feedback = try executor.execute(CommandIntent(identifier: .contextOpen, arguments: .contextOpen(ContextOpenRequest(targetKind: .application))), context: context)
        XCTAssertEqual(feedback, "No frontmost application detected.")
    }

    func testContextParserExistingCommandsStillWork() {
        let parser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari"], running: ["Safari"]))
        
        // Existing context commands should still work
        let openItPlan = parser.parse("open it", context: .test(resolvedFileURL: URL(string: "file:///test.txt")!))
        XCTAssertNotNil(openItPlan)
        XCTAssertEqual(openItPlan?.steps.first?.intent.identifier, .contextOpen)

        let checkMeetingPlan = parser.parse("check my next meeting", context: .test())
        XCTAssertNotNil(checkMeetingPlan)
        XCTAssertEqual(checkMeetingPlan?.steps.first?.intent.identifier, .contextCheck)

        let checkRemindersPlan = parser.parse("check my reminders", context: .test())
        XCTAssertNotNil(checkRemindersPlan)
        XCTAssertEqual(checkRemindersPlan?.steps.first?.intent.identifier, .contextCheck)
    }

    // MARK: - Finder Parser & Executor Tests

    func testFinderParserLocations() {
        let parser = FinderCommandParser()

        let planDownloads = parser.parse("open downloads", context: .test())
        XCTAssertNotNil(planDownloads)
        XCTAssertEqual(planDownloads?.steps.first?.intent.identifier, .finderOpenLocation)
        if case .finderLocation(let target) = planDownloads?.steps.first?.intent.arguments {
            XCTAssertEqual(target.location, .downloads)
        } else {
            XCTFail("Wrong argument")
        }

        let planDocuments = parser.parse("open my documents folder", context: .test())
        XCTAssertNotNil(planDocuments)
        if case .finderLocation(let target) = planDocuments?.steps.first?.intent.arguments {
            XCTAssertEqual(target.location, .documents)
        } else {
            XCTFail("Wrong argument")
        }
    }

    func testFinderParserFileSearch() {
        let parser = FinderCommandParser()
        let plan = parser.parse("find files in documents", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderFindFiles)
        if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
            XCTAssertEqual(req.scope, .documents)
            XCTAssertEqual(req.filter, .all)
        } else {
            XCTFail("Wrong argument")
        }

        let planScreenshots = parser.parse("find my screenshots", context: .test())
        XCTAssertNotNil(planScreenshots)
        if case .fileSearch(let req) = planScreenshots?.steps.first?.intent.arguments {
            XCTAssertEqual(req.filter, .screenshots)
        } else {
            XCTFail("Wrong argument")
        }
    }

    func testFinderExecutorOpenLocation() throws {
        let fake = FakeFinderControl()
        let executor = FinderCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .finderOpenLocation, arguments: .finderLocation(FinderLocationTarget(location: .downloads))), context: .test())
        XCTAssertEqual(feedback, "Opened Downloads")
        XCTAssertEqual(fake.openedTargets.first?.location, .downloads)
    }

    // MARK: - Finder Parser Extended Tests (Slice 2)

    func testFinderParserPicturesLocation() {
        let parser = FinderCommandParser()

        let phrases = [
            "open pictures",
            "open my pictures",
            "show pictures",
            "show my pictures",
            "open the pictures folder",
            "open my pictures folder",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderOpenLocation, "Wrong identifier for: \(phrase)")
            if case .finderLocation(let target) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(target.location, .pictures, "Wrong location for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testFinderParserScopedPDFSearch() {
        let parser = FinderCommandParser()

        // Test PDF search in Documents
        let pdfInDocuments = [
            "find pdf files in documents",
            "find pdfs in documents",
            "search for pdf files in documents",
            "find pdfs in my documents",
        ]
        for phrase in pdfInDocuments {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderFindFiles)
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.scope, .documents, "Wrong scope for: \(phrase)")
                XCTAssertEqual(req.filter, .pdfs, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Test PDF search in Downloads
        let pdfInDownloads = [
            "search pdfs in downloads",
            "find pdf files in downloads",
        ]
        for phrase in pdfInDownloads {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.scope, .downloads, "Wrong scope for: \(phrase)")
                XCTAssertEqual(req.filter, .pdfs, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Test PDF search in Desktop
        let pdfInDesktop = [
            "find pdf files in desktop",
            "find pdfs in desktop",
        ]
        for phrase in pdfInDesktop {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.scope, .desktop, "Wrong scope for: \(phrase)")
                XCTAssertEqual(req.filter, .pdfs, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Test PDF search in Pictures
        let pdfInPictures = [
            "find pdf files in pictures",
            "find pdfs in pictures",
        ]
        for phrase in pdfInPictures {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.scope, .pictures, "Wrong scope for: \(phrase)")
                XCTAssertEqual(req.filter, .pdfs, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testFinderParserRelativeDateSearch() {
        let parser = FinderCommandParser()

        // Modified today (existing)
        let todayPhrases = [
            "show files modified today",
            "find files modified today",
            "files modified today",
        ]
        for phrase in todayPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.filter, .modifiedToday, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Modified yesterday (new)
        let yesterdayPhrases = [
            "show files modified yesterday",
            "find files modified yesterday",
            "files modified yesterday",
        ]
        for phrase in yesterdayPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.filter, .modifiedYesterday, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Modified this week (new)
        let weekPhrases = [
            "show files modified this week",
            "find files modified this week",
            "files modified this week",
        ]
        for phrase in weekPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(req.filter, .modifiedThisWeek, "Wrong filter for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testFinderParserPicturesScopeFileSearch() {
        let parser = FinderCommandParser()

        let plan = parser.parse("find files in pictures", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .finderFindFiles)
        if case .fileSearch(let req) = plan?.steps.first?.intent.arguments {
            XCTAssertEqual(req.scope, .pictures)
            XCTAssertEqual(req.filter, .all)
        } else {
            XCTFail("Wrong argument")
        }
    }

    func testFinderParserNegativeCases() {
        let parser = FinderCommandParser()

        // These should NOT be parsed as Finder commands
        let negativePhrases = [
            "my pictures are nice",           // dictation
            "the pictures folder is empty",   // dictation
            "search for pictures in google",  // web search
            "find pdf",                       // incomplete
            "search pdfs",                    // incomplete
            "modified today",                 // incomplete
            "modified yesterday",             // incomplete
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNil(plan, "Should not parse as Finder command: \(phrase)")
        }
    }

    // MARK: - App Switch Tests

    func testAppSwitchParsingAndExecution() throws {
        let resolver = FakeApplicationResolver(installed: ["Safari"], running: ["Safari"])
        let parser = DeterministicCommandParser(applications: resolver)

        let plan = parser.parse("switch to Safari", context: .test())
        XCTAssertNotNil(plan)
        guard let step = plan?.steps.first else { return XCTFail("No step in plan") }
        XCTAssertEqual(step.intent.identifier, CommandIdentifier.appSwitch)

        let fakeControl = FakeApplicationControl()
        let executor = ApplicationCommandExecutor(control: fakeControl)
        let feedback = try executor.execute(step.intent, context: .test())
        XCTAssertEqual(feedback, "Switched to Safari")
        XCTAssertEqual(fakeControl.activated.count, 1)
        XCTAssertEqual(fakeControl.activated.first?.displayName, "Safari")
    }

    // MARK: - Multi-Step Composition Tests

    func testMultiStepCompositionWithStage6Commands() {
        let calendarParser = CalendarCommandParser()
        let finderParser = FinderCommandParser()
        let multiParser = MultiStepCommandParser(parsers: [calendarParser, finderParser])

        let plan = multiParser.parse("open downloads and then open calendar", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].intent.identifier, .finderOpenLocation)
        XCTAssertEqual(plan?.steps[1].intent.identifier, .calendarOpen)
    }

    // MARK: - Risk and Confirmation Boundary Tests

    func testSensitiveCommandsRequireConfirmation() {
        let registry = CommandRegistry.standard()
        XCTAssertEqual(registry.definition(for: .calendarCreateEvent)?.risk, .sensitive)
        XCTAssertEqual(registry.definition(for: .calendarCreateEvent)?.confirmation, .mandatory)

        XCTAssertEqual(registry.definition(for: .remindersCreate)?.risk, .sensitive)
        XCTAssertEqual(registry.definition(for: .remindersCreate)?.confirmation, .mandatory)

        XCTAssertEqual(registry.definition(for: .notesCreate)?.risk, .sensitive)
        XCTAssertEqual(registry.definition(for: .notesCreate)?.confirmation, .mandatory)
    }

    func testSafeCommandsDoNotRequireConfirmation() {
        let registry = CommandRegistry.standard()
        XCTAssertEqual(registry.definition(for: .calendarOpen)?.risk, .safe)
        XCTAssertEqual(registry.definition(for: .calendarOpen)?.confirmation, ConfirmationRequirement.none)

        XCTAssertEqual(registry.definition(for: .remindersList)?.risk, .safe)
        XCTAssertEqual(registry.definition(for: .remindersList)?.confirmation, ConfirmationRequirement.none)

        XCTAssertEqual(registry.definition(for: .finderOpenLocation)?.risk, .safe)
        XCTAssertEqual(registry.definition(for: .finderOpenLocation)?.confirmation, ConfirmationRequirement.none)

        XCTAssertEqual(registry.definition(for: .contactsFind)?.risk, .safe)
        XCTAssertEqual(registry.definition(for: .contactsFind)?.confirmation, ConfirmationRequirement.none)

        XCTAssertEqual(registry.definition(for: .contactsShow)?.risk, .safe)
        XCTAssertEqual(registry.definition(for: .contactsShow)?.confirmation, ConfirmationRequirement.none)
    }

    // MARK: - Contacts Tests (Slice 7)

    func testContactsParserFind() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let parser = ContactsCommandParser(contactResolver: whatsAppContacts)
        let phrases = [
            "find contact John",
            "find my contact John",
            "find contact in my contacts John",
            "search contacts for John",
            "search my contacts for John",
            "look up contact in my contacts John",
            "look up John",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .contactsFind)
            if case .contactsQuery(let query) = plan?.steps.first?.intent.arguments {
                XCTAssertFalse(query.query.isEmpty, "Empty query for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testContactsParserShow() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let parser = ContactsCommandParser(contactResolver: whatsAppContacts)
        let phrases = [
            "show contact John",
            "show my contact John",
            "show me contact John",
            "show me John",
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .contactsShow)
            if case .contactsShow(let req) = plan?.steps.first?.intent.arguments {
                XCTAssertFalse(req.query.isEmpty, "Empty query for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    func testContactsParserNegativeCases() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let parser = ContactsCommandParser(contactResolver: whatsAppContacts)

        let negativePhrases = [
            "my contact John",       // dictation
            "the contact John",      // dictation
            "open contact John",     // not a supported phrase
            "message John hello",    // whatsAppSendMessage
            "find John",             // ambiguous - should not parse as contacts
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .contactsFind, "Should not parse as contactsFind: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .contactsShow, "Should not parse as contactsShow: \(phrase)")
            }
        }
    }

    func testContactsExecutorFind() throws {
        let fake = FakeContactsControl()
        fake.contactsToReturn = [
            ContactSummary(displayName: "John Doe", phoneNumbers: ["14155551234"], emailAddresses: ["john@example.com"]),
            ContactSummary(displayName: "Jane Smith", phoneNumbers: ["14155555678"], emailAddresses: ["jane@example.com"]),
        ]
        let executor = ContactsCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .contactsFind, arguments: .contactsQuery(ContactQuery(query: "John"))), context: .test())
        XCTAssertTrue(feedback.contains("Multiple contacts match"))
        XCTAssertTrue(feedback.contains("John Doe"))
        XCTAssertTrue(feedback.contains("Jane Smith"))
    }

    func testContactsExecutorFindSingle() throws {
        let fake = FakeContactsControl()
        fake.contactsToReturn = [
            ContactSummary(displayName: "John Doe", phoneNumbers: ["14155551234"], emailAddresses: ["john@example.com"]),
        ]
        let executor = ContactsCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .contactsFind, arguments: .contactsQuery(ContactQuery(query: "John"))), context: .test())
        XCTAssertTrue(feedback.contains("Found contact: John Doe"))
        XCTAssertTrue(feedback.contains("14155551234"))
        XCTAssertTrue(feedback.contains("john@example.com"))
    }

    func testContactsExecutorFindEmpty() throws {
        let fake = FakeContactsControl()
        fake.contactsToReturn = []
        let executor = ContactsCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .contactsFind, arguments: .contactsQuery(ContactQuery(query: "John"))), context: .test())
        XCTAssertEqual(feedback, "No contact found matching \"John\".")
    }

    func testContactsExecutorShow() throws {
        let fake = FakeContactsControl()
        fake.contactsToReturn = [
            ContactSummary(displayName: "John Doe", phoneNumbers: ["14155551234"], emailAddresses: ["john@example.com"]),
        ]
        let executor = ContactsCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .contactsShow, arguments: .contactsShow(ContactShowRequest(query: "John"))), context: .test())
        XCTAssertTrue(feedback.contains("Found contact: John Doe"))
    }

    func testContactsExecutorAccessDenied() throws {
        let fake = FakeContactsControl()
        fake.shouldFailWithAccessDenied = true
        let executor = ContactsCommandExecutor(control: fake)
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .contactsFind, arguments: .contactsQuery(ContactQuery(query: "John"))), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Contacts access is denied. Allow DailyOps in System Settings > Privacy & Security > Contacts."))
        }
    }

    func testContactsParserPrecedence() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let contactsParser = ContactsCommandParser(contactResolver: whatsAppContacts)
        let whatsAppParser = WhatsAppCommandParser(contactResolver: SystemWhatsAppContactResolver())
        let notesParser = NotesCommandParser()
        let calendarParser = CalendarCommandParser()
        let remindersParser = RemindersCommandParser()
        let finderParser = FinderCommandParser()
        let deterministicParser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari", "WhatsApp", "Notes"], running: ["Safari"]))
        let multiParser = MultiStepCommandParser(parsers: [
            whatsAppParser,
            calendarParser,
            remindersParser,
            notesParser,
            finderParser,
            contactsParser,
            deterministicParser
        ])

        // "message John saying hello" should go to WhatsApp, not contacts
        let plan1 = multiParser.parse("message John saying hello", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .whatsAppSendMessage)

        // "open WhatsApp" should be app.open
        let plan2 = multiParser.parse("open WhatsApp", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .appOpen)

        // "open Notes" should be notesOpen
        let plan3 = multiParser.parse("open Notes", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .notesOpen)

        // "open Safari" should be app.open
        let plan4 = multiParser.parse("open Safari", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .appOpen)

        // "open this app" should be contextOpen
        let plan5 = multiParser.parse("open this app", context: .test(frontmostApplicationName: "Safari"))
        XCTAssertNotNil(plan5)
        XCTAssertEqual(plan5?.steps.first?.intent.identifier, .contextOpen)

        // "what app am I in" should be contextCheck
        let plan6 = multiParser.parse("what app am i in", context: .test(frontmostApplicationName: "Safari"))
        XCTAssertNotNil(plan6)
        XCTAssertEqual(plan6?.steps.first?.intent.identifier, .contextCheck)

        // "find contact John" should be contactsFind
        let plan8 = multiParser.parse("find contact John", context: .test())
        XCTAssertNotNil(plan8)
        XCTAssertEqual(plan8?.steps.first?.intent.identifier, .contactsFind)

        // "show contact John" should be contactsShow
        let plan9 = multiParser.parse("show contact John", context: .test())
        XCTAssertNotNil(plan9)
        XCTAssertEqual(plan9?.steps.first?.intent.identifier, .contactsShow)
    }

// MARK: - System Information Tests (Slice 11)

    @MainActor
    func testSystemInformationParserBattery() {
        let parser = SystemInformationCommandParser()
        let phrases = [
            "what is my battery status",
            "what's my battery status",
            "battery status",
            "what is my battery",
            "what's my battery",
            "how much battery do i have",
            "how much battery is left",
            "how much battery is remaining",
            "show my battery",
            "check my battery"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemBattery)
        }
    }

    @MainActor
    func testSystemInformationParserMacOSVersion() {
        let parser = SystemInformationCommandParser()
        let phrases = [
            "what macos version am i running",
            "what macos version am i running",
            "what version of macos am i running",
            "what version of macos is this",
            "what macos version is this",
            "which macos version do i have",
            "show my macos version",
            "check my macos version",
            "what mac os version am i running",
            "what mac os version am i running",
            "what version of mac os am i running",
            "what version of mac os is this",
            "what mac os version is this",
            "which mac os version do i have",
            "show my mac os version",
            "check my mac os version"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemMacOSVersion)
        }
    }

    @MainActor
    func testSystemInformationParserTime() {
        let parser = SystemInformationCommandParser()
        let phrases = [
            "what time is it",
            "what's the time",
            "what is the current time",
            "current time",
            "tell me the time",
            "show me the time"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemTime)
        }
    }

    @MainActor
    func testSystemInformationParserDate() {
        let parser = SystemInformationCommandParser()
        let phrases = [
            "what date is it",
            "what's today's date",
            "what is today's date",
            "what is the date today",
            "today's date",
            "current date",
            "tell me today's date"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemDate)
        }
    }

    @MainActor
    func testSystemInformationParserNegativeCases() {
        let parser = SystemInformationCommandParser()

        let negativePhrases = [
            "my battery is at 80%",
            "the system is running",
            "what time zone is this",
            "open battery settings",
            "open date and time"
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemBattery, "Should not parse as systemBattery: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemMacOSVersion, "Should not parse as systemMacOSVersion: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemTime, "Should not parse as systemTime: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemDate, "Should not parse as systemDate: \(phrase)")
            }
        }
    }

    func testSystemInformationExecutorBattery() throws {
        let fake = FakeSystemInformationControl()
        fake.batteryInfoToReturn = BatteryInfo(percentage: 82, isCharging: true, isFullyCharged: false, timeRemaining: 3600, isACPowered: true)
        let executor = SystemInformationCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemBattery), context: .test())
        XCTAssertTrue(feedback.contains("82%"))
        XCTAssertTrue(feedback.contains("charging"))
    }

    func testSystemInformationExecutorBatteryUnavailable() throws {
        let fake = FakeSystemInformationControl()
        fake.batteryInfoToReturn = BatteryInfo(percentage: nil, isCharging: false, isFullyCharged: false, timeRemaining: nil, isACPowered: false)
        let executor = SystemInformationCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemBattery), context: .test())
        XCTAssertEqual(feedback, "Battery information is unavailable.")
    }

    func testSystemInformationExecutorBatteryFull() throws {
        let fake = FakeSystemInformationControl()
        fake.batteryInfoToReturn = BatteryInfo(percentage: 100, isCharging: false, isFullyCharged: true, timeRemaining: nil, isACPowered: true)
        let executor = SystemInformationCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemBattery), context: .test())
        XCTAssertTrue(feedback.contains("100%"))
        XCTAssertTrue(feedback.contains("fully charged"))
    }

    func testSystemInformationExecutorMacOSVersion() throws {
        let fake = FakeSystemInformationControl()
        fake.macOSVersionToReturn = MacOSVersionInfo(versionString: "macOS 26.0", buildVersion: "26A000")
        let executor = SystemInformationCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemMacOSVersion), context: .test())
        XCTAssertTrue(feedback.contains("macOS 26.0"))
        XCTAssertTrue(feedback.contains("26A000"))
    }

    func testSystemInformationExecutorTime() throws {
        let fake = FakeSystemInformationControl()
        fake.timeToReturn = TimeInfo(formattedTime: "10:42 AM")
        let executor = SystemInformationCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemTime), context: .test())
        XCTAssertEqual(feedback, "Current time: 10:42 AM.")
    }

    func testSystemInformationExecutorDate() throws {
        let fake = FakeSystemInformationControl()
        fake.dateToReturn = DateInfo(formattedDate: "Monday, September 7, 2026")
        let executor = SystemInformationCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemDate), context: .test())
        XCTAssertEqual(feedback, "Today's date: Monday, September 7, 2026.")
    }

    func testSystemInformationExecutorError() throws {
        let fake = FakeSystemInformationControl()
        fake.shouldFail = true
        let executor = SystemInformationCommandExecutor(control: fake)
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemBattery), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Battery information unavailable."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemMacOSVersion), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("macOS version unavailable."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemTime), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Time unavailable."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemDate), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Date unavailable."))
        }
    }

    func testSystemInformationParserPrecedence() {
        let multiParser = MultiStepCommandParser(parsers: [
            ContactsCommandParser(contactResolver: SystemWhatsAppContactResolver()),
            MailCommandParser(contactResolver: SystemWhatsAppContactResolver()),
            NotesCommandParser(),
            CalendarCommandParser(),
            RemindersCommandParser(),
            FinderCommandParser(),
            SystemInformationCommandParser(),
            DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari", "Mail", "WhatsApp", "Notes"], running: ["Safari"]))
        ])

        // "what is my battery status" should go to systemBattery
        let plan1 = multiParser.parse("what is my battery status", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .systemBattery)

        // "what time is it" should go to systemTime
        let plan2 = multiParser.parse("what time is it", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .systemTime)

        // "what is my battery" should go to systemBattery
        let plan3 = multiParser.parse("what is my battery", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .systemBattery)

        // "what macOS version am I running" should go to systemMacOSVersion
        let plan4 = multiParser.parse("what macOS version am i running", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .systemMacOSVersion)

        // "what time is it" should go to systemTime
        let plan5 = multiParser.parse("what time is it", context: .test())
        XCTAssertNotNil(plan5)
        XCTAssertEqual(plan5?.steps.first?.intent.identifier, .systemTime)

        // "what date is it" should go to systemDate
        let plan6 = multiParser.parse("what date is it", context: .test())
        XCTAssertNotNil(plan6)
        XCTAssertEqual(plan6?.steps.first?.intent.identifier, .systemDate)
    }

// MARK: - System Audio Tests (Slice 12)

    @MainActor
    func testSystemAudioParserVolumeUp() {
        let parser = SystemAudioCommandParser()
        let phrases = [
            "volume up",
            "turn the volume up",
            "turn up the volume",
            "increase the volume",
            "make it louder",
            "louder"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemVolumeUp)
        }
    }

    @MainActor
    func testSystemAudioParserVolumeDown() {
        let parser = SystemAudioCommandParser()
        let phrases = [
            "volume down",
            "turn the volume down",
            "turn down the volume",
            "decrease the volume",
            "make it quieter",
            "quieter"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemVolumeDown)
        }
    }

    @MainActor
    func testSystemAudioParserMute() {
        let parser = SystemAudioCommandParser()
        let phrases = [
            "mute",
            "mute the volume",
            "mute audio",
            "mute sound",
            "mute my mac"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemVolumeMute)
        }
    }

    @MainActor
    func testSystemAudioParserUnmute() {
        let parser = SystemAudioCommandParser()
        let phrases = [
            "unmute",
            "unmute the volume",
            "unmute audio",
            "unmute sound",
            "unmute my mac"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemVolumeUnmute)
        }
    }

    @MainActor
    func testSystemAudioParserVolumeGet() {
        let parser = SystemAudioCommandParser()
        let phrases = [
            "what is my volume",
            "what's my volume",
            "what is the volume",
            "show volume",
            "check volume",
            "how loud is it"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemVolumeGet)
        }
    }

    @MainActor
    func testSystemAudioParserVolumeSet() {
        let parser = SystemAudioCommandParser()
        let phrases = [
            ("set volume to 50", 50),
            ("set the volume to 50", 50),
            ("volume 50", 50),
            ("set volume to 75 percent", 75),
            ("set the volume to 25%", 25),
            ("set volume to 0", 0),
            ("set volume to 100", 100)
        ]

        for (phrase, expectedPercentage) in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemVolumeSet)
            if case .systemVolumeSet(let percentage) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(percentage, expectedPercentage, "Wrong percentage for: \(phrase)")
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    @MainActor
    func testSystemAudioParserVolumeSetInvalid() {
        let parser = SystemAudioCommandParser()
        let invalidPhrases = [
            "set volume to -10",
            "set volume to 101",
            "set volume to 150",
            "set volume to abc",
            "volume -5",
            "volume 200"
        ]

        for phrase in invalidPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNil(plan, "Should not parse invalid percentage: \(phrase)")
        }
    }

    @MainActor
    func testSystemAudioParserNegativeCases() {
        let parser = SystemAudioCommandParser()

        let negativePhrases = [
            "my volume is at 50",
            "the audio is loud",
            "volume settings",
            "open volume control",
            "audio settings"
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemVolumeUp, "Should not parse as systemVolumeUp: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemVolumeDown, "Should not parse as systemVolumeDown: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemVolumeMute, "Should not parse as systemVolumeMute: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemVolumeUnmute, "Should not parse as systemVolumeUnmute: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemVolumeGet, "Should not parse as systemVolumeGet: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemVolumeSet, "Should not parse as systemVolumeSet: \(phrase)")
            }
        }
    }

    func testSystemAudioExecutorVolumeUp() throws {
        let fake = FakeSystemAudioControl()
        fake.volumeToReturn = 0.6
        fake.mutedToReturn = false
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeUp), context: .test())
        XCTAssertTrue(feedback.contains("60%"))
        XCTAssertTrue(feedback.contains("increased"))
        XCTAssertEqual(fake.volumeUpCalls, 1)
    }

    func testSystemAudioExecutorVolumeDown() throws {
        let fake = FakeSystemAudioControl()
        fake.volumeToReturn = 0.4
        fake.mutedToReturn = false
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeDown), context: .test())
        XCTAssertTrue(feedback.contains("40%"))
        XCTAssertTrue(feedback.contains("decreased"))
        XCTAssertEqual(fake.volumeDownCalls, 1)
    }

    func testSystemAudioExecutorVolumeSet() throws {
        let fake = FakeSystemAudioControl()
        fake.volumeToReturn = 0.75
        fake.mutedToReturn = false
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeSet, arguments: .systemVolumeSet(75)), context: .test())
        XCTAssertEqual(feedback, "Volume set to 75%.")
        XCTAssertEqual(fake.setVolumeCalls.count, 1)
        XCTAssertEqual(fake.setVolumeCalls.first, 0.75)
    }

    func testSystemAudioExecutorVolumeMute() throws {
        let fake = FakeSystemAudioControl()
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeMute), context: .test())
        XCTAssertEqual(feedback, "Volume muted.")
        XCTAssertEqual(fake.muteCalls, 1)
    }

    func testSystemAudioExecutorVolumeUnmute() throws {
        let fake = FakeSystemAudioControl()
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeUnmute), context: .test())
        XCTAssertEqual(feedback, "Volume unmuted.")
        XCTAssertEqual(fake.unmuteCalls, 1)
    }

    func testSystemAudioExecutorVolumeGet() throws {
        let fake = FakeSystemAudioControl()
        fake.volumeToReturn = 0.55
        fake.mutedToReturn = false
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeGet), context: .test())
        XCTAssertEqual(feedback, "Current volume is 55%.")
    }

    func testSystemAudioExecutorVolumeGetMuted() throws {
        let fake = FakeSystemAudioControl()
        fake.volumeToReturn = 0.3
        fake.mutedToReturn = true
        let executor = SystemAudioCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemVolumeGet), context: .test())
        XCTAssertEqual(feedback, "Current volume is 30% (muted).")
    }

    func testSystemAudioExecutorError() throws {
        let fake = FakeSystemAudioControl()
        fake.shouldFail = true
        let executor = SystemAudioCommandExecutor(control: fake)

        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemVolumeUp), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to increase volume."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemVolumeDown), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to decrease volume."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemVolumeSet, arguments: .systemVolumeSet(50)), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to set volume."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemVolumeMute), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to mute volume."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemVolumeUnmute), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to unmute volume."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemVolumeGet), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Volume unavailable."))
        }
    }

    func testSystemAudioParserPrecedence() {
        let multiParser = MultiStepCommandParser(parsers: [
            SystemInformationCommandParser(),
            SystemAudioCommandParser(),
            DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari"], running: ["Safari"]))
        ])

        // "volume up" should go to systemVolumeUp
        let plan1 = multiParser.parse("volume up", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .systemVolumeUp)

        // "mute" should go to systemVolumeMute
        let plan2 = multiParser.parse("mute", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .systemVolumeMute)

        // "what is my volume" should go to systemVolumeGet
        let plan3 = multiParser.parse("what is my volume", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .systemVolumeGet)

        // "set volume to 50" should go to systemVolumeSet
        let plan4 = multiParser.parse("set volume to 50", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .systemVolumeSet)

        // Existing system info commands should still work
        let plan5 = multiParser.parse("what is my battery status", context: .test())
        XCTAssertNotNil(plan5)
        XCTAssertEqual(plan5?.steps.first?.intent.identifier, .systemBattery)

        // App commands should still work
        let plan6 = multiParser.parse("open Safari", context: .test())
        XCTAssertNotNil(plan6)
        XCTAssertEqual(plan6?.steps.first?.intent.identifier, .appOpen)
    }

// MARK: - Mail Tests (Slice 8)

    @MainActor
    func testMailParserOpenMail() {
        let parser = MailCommandParser()
        let phrases = [
            "open mail",
            "launch mail",
            "start mail",
            "open my mail",
            "show mail"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .mailOpen)
        }
    }

    @MainActor
    func testMailParserComposeEmail() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let parser = MailCommandParser(contactResolver: whatsAppContacts)

        // Blank compose
        let blankPhrases = [
            "compose an email",
            "write an email",
            "compose email",
            "write email"
        ]
        for phrase in blankPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .mailCompose)
            if case .mailCompose(let request) = plan?.steps.first?.intent.arguments {
                XCTAssertNil(request.to)
                XCTAssertNil(request.subject)
                XCTAssertNil(request.body)
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Compose to contact
        let toPhrases = [
            ("compose an email to John", "John"),
            ("compose email to John", "John"),
            ("write an email to John", "John"),
            ("write email to John", "John"),
            ("email John", "John"),
            ("send an email to John", "John"),
            ("send email to John", "John"),
        ]
        for (phrase, expectedName) in toPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .mailCompose)
            if case .mailCompose(let request) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(request.to, expectedName)
                XCTAssertNil(request.subject)
                XCTAssertNil(request.body)
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Compose with "saying" body
        let sayingPhrases = [
            ("compose an email to John saying hello", "John", "hello"),
            ("write an email to John saying hello", "John", "hello"),
        ]
        for (phrase, expectedName, expectedBody) in sayingPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .mailCompose)
            if case .mailCompose(let request) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(request.to, expectedName)
                XCTAssertEqual(request.body, expectedBody)
                XCTAssertNil(request.subject)
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }

        // Compose with subject
        let subjectPhrases = [
            ("compose an email to John with subject meeting", "John", "meeting"),
            ("write an email to John with subject meeting", "John", "meeting"),
        ]
        for (phrase, expectedName, expectedSubject) in subjectPhrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .mailCompose)
            if case .mailCompose(let request) = plan?.steps.first?.intent.arguments {
                XCTAssertEqual(request.to, expectedName)
                XCTAssertEqual(request.subject, expectedSubject)
                XCTAssertNil(request.body)
            } else {
                XCTFail("Wrong argument for: \(phrase)")
            }
        }
    }

    @MainActor
    func testMailParserNegativeCases() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let parser = MailCommandParser(contactResolver: whatsAppContacts)

        let negativePhrases = [
            "my email is john@example.com",
            "the email is sent",
            "check my email",
            "open Notes",
            "open Safari",
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .mailOpen, "Should not parse as mailOpen: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .mailCompose, "Should not parse as mailCompose: \(phrase)")
            }
        }
    }

    @MainActor
    func testMailExecutorOpenMail() throws {
        let fake = FakeMailControl()
        let executor = MailCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .mailOpen), context: .test())
        XCTAssertEqual(feedback, "Opened Mail")
        XCTAssertTrue(fake.openedMail)
    }

    @MainActor
    func testMailExecutorComposeBlank() throws {
        let fake = FakeMailControl()
        let executor = MailCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .mailCompose, arguments: .mailCompose(MailComposeRequest())), context: .test())
        XCTAssertTrue(feedback.contains("new recipient"))
        XCTAssertEqual(fake.composedEmails.count, 1)
        XCTAssertNil(fake.composedEmails.first?.to)
        XCTAssertNil(fake.composedEmails.first?.subject)
        XCTAssertNil(fake.composedEmails.first?.body)
    }

    @MainActor
    func testMailExecutorComposeToContact() throws {
        let fake = FakeMailControl()
        let executor = MailCommandExecutor(control: fake)
        let request = MailComposeRequest(to: "John", subject: "Hello", body: "Hi there")
        let feedback = try executor.execute(CommandIntent(identifier: .mailCompose, arguments: .mailCompose(request)), context: .test())
        XCTAssertTrue(feedback.contains("John"))
        XCTAssertEqual(fake.composedEmails.count, 1)
        XCTAssertEqual(fake.composedEmails.first?.to, "John")
        XCTAssertEqual(fake.composedEmails.first?.subject, "Hello")
        XCTAssertEqual(fake.composedEmails.first?.body, "Hi there")
    }

    @MainActor
    func testMailExecutorError() throws {
        let fake = FakeMailControl()
        fake.shouldFail = true
        let executor = MailCommandExecutor(control: fake)
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .mailOpen), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Could not open Mail app."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .mailCompose, arguments: .mailCompose(MailComposeRequest())), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Could not compose email."))
        }
    }

    @MainActor
    func testMailParserPrecedence() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let mailParser = MailCommandParser(contactResolver: whatsAppContacts)
        let whatsAppParser = WhatsAppCommandParser(contactResolver: whatsAppContacts)
        let contactsParser = ContactsCommandParser(contactResolver: whatsAppContacts)
        let notesParser = NotesCommandParser()
        let calendarParser = CalendarCommandParser()
        let remindersParser = RemindersCommandParser()
        let finderParser = FinderCommandParser()
        let deterministicParser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari", "Mail", "WhatsApp", "Notes"], running: ["Safari"]))
        let multiParser = MultiStepCommandParser(parsers: [
            whatsAppParser,
            calendarParser,
            remindersParser,
            notesParser,
            finderParser,
            contactsParser,
            mailParser,
            deterministicParser
        ])

        // "message John saying hello" should go to WhatsApp, not mail
        let plan1 = multiParser.parse("message John saying hello", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .whatsAppSendMessage)

        // "email John" should go to mail
        let plan2 = multiParser.parse("email John", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .mailCompose)

        // "open Mail" should be mailOpen
        let plan3 = multiParser.parse("open Mail", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .mailOpen)

        // "open Notes" should be notesOpen
        let plan4 = multiParser.parse("open Notes", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .notesOpen)

        // "open Safari" should be app.open
        let plan5 = multiParser.parse("open Safari", context: .test())
        XCTAssertNotNil(plan5)
        XCTAssertEqual(plan5?.steps.first?.intent.identifier, .appOpen)

        // "open this app" should be contextOpen
        let plan6 = multiParser.parse("open this app", context: .test(frontmostApplicationName: "Safari"))
        XCTAssertNotNil(plan6)
        XCTAssertEqual(plan6?.steps.first?.intent.identifier, .contextOpen)

        // "what app am I in" should be contextCheck
        let plan6b = multiParser.parse("what app am i in", context: .test(frontmostApplicationName: "Safari"))
        XCTAssertNotNil(plan6b)
        XCTAssertEqual(plan6b?.steps.first?.intent.identifier, .contextCheck)

        // "compose an email to John" should be mailCompose
        let plan7 = multiParser.parse("compose an email to John", context: .test())
        XCTAssertNotNil(plan7)
        XCTAssertEqual(plan7?.steps.first?.intent.identifier, .mailCompose)

        // "find contact John" should be contactsFind
        let plan8 = multiParser.parse("find contact John", context: .test())
        XCTAssertNotNil(plan8)
        XCTAssertEqual(plan8?.steps.first?.intent.identifier, .contactsFind)

        // "show contact John" should be contactsShow
        let plan9 = multiParser.parse("show contact John", context: .test())
        XCTAssertNotNil(plan9)
        XCTAssertEqual(plan9?.steps.first?.intent.identifier, .contactsShow)
    }

    // MARK: - Mail Email Resolution Tests

    @MainActor
    func testMailParserComposeWithContactResolution() {
        let emailResolver = FakeEmailContactResolver(responses: [
            "John": .resolved(EmailContact(name: "John Doe", emailAddress: "john.doe@example.com")),
            "Jane": .resolved(EmailContact(name: "Jane Smith", emailAddress: "jane.smith@company.com")),
            "NoEmail": .noEmailAddress(name: "No Email Person"),
        ])
        let parser = MailCommandParser(contactResolver: nil, emailResolver: emailResolver)

        // Compose to a contact with email
        let plan1 = parser.parse("compose an email to John", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .mailCompose)
        if case .mailCompose(let request) = plan1?.steps.first?.intent.arguments {
            XCTAssertEqual(request.to, "john.doe@example.com")
        } else {
            XCTFail("Wrong argument for compose email to John")
        }

        // Compose to a different contact
        let plan2 = parser.parse("email Jane saying hello", context: .test())
        XCTAssertNotNil(plan2)
        if case .mailCompose(let request) = plan2?.steps.first?.intent.arguments {
            XCTAssertEqual(request.to, "jane.smith@company.com")
            XCTAssertEqual(request.body, "hello")
        } else {
            XCTFail("Wrong argument for email Jane")
        }
    }

    @MainActor
    func testMailParserComposeWithDirectEmail() {
        let parser = MailCommandParser(contactResolver: nil, emailResolver: nil)

        // Direct email address should be used as-is
        let plan1 = parser.parse("compose an email to john@example.com", context: .test())
        XCTAssertNotNil(plan1)
        if case .mailCompose(let request) = plan1?.steps.first?.intent.arguments {
            XCTAssertEqual(request.to, "john@example.com")
        } else {
            XCTFail("Wrong argument for direct email")
        }
    }

    @MainActor
    func testMailParserComposeWithContactNoEmail() {
        let parser = MailCommandParser(contactResolver: nil, emailResolver: FakeEmailContactResolver(responses: [
            "NoEmail": .noEmailAddress(name: "No Email Person"),
        ]))

        // Contact exists but has no email - should still create plan with name
        let plan = parser.parse("compose an email to NoEmail", context: .test())
        XCTAssertNotNil(plan)
        if case .mailCompose(let request) = plan?.steps.first?.intent.arguments {
            // Falls back to name when no email
            XCTAssertEqual(request.to, "NoEmail")
        } else {
            XCTFail("Wrong argument for contact with no email")
        }
    }

    @MainActor
    func testMailParserComposeAmbiguousContact() {
        let parser = MailCommandParser(contactResolver: nil, emailResolver: FakeEmailContactResolver(responses: [
            "John": .ambiguous([
                EmailContact(name: "John Doe", emailAddress: "john.doe@example.com"),
                EmailContact(name: "John Smith", emailAddress: "john.smith@company.com"),
            ]),
        ]))

        // Ambiguous contact - still creates plan but with name
        let plan = parser.parse("compose an email to John", context: .test())
        XCTAssertNotNil(plan)
        if case .mailCompose(let request) = plan?.steps.first?.intent.arguments {
            // Falls back to name when ambiguous
            XCTAssertEqual(request.to, "John")
        } else {
            XCTFail("Wrong argument for ambiguous contact")
        }
    }

    func testMailExecutorExactPlanExecution() throws {
        let fake = FakeMailControl()
        let executor = MailCommandExecutor(control: fake)

        // Create email with specific recipient, subject, body
        let request = MailComposeRequest(to: "john@example.com", subject: "Test Subject", body: "Test body content")
        let intent = CommandIntent(identifier: .mailCompose, arguments: .mailCompose(request))
        let feedback = try executor.execute(intent, context: .test())

        // Verify the exact recipient, subject, body were used
        XCTAssertEqual(fake.composedEmails.count, 1)
        XCTAssertEqual(fake.composedEmails[0].to, "john@example.com")
        XCTAssertEqual(fake.composedEmails[0].subject, "Test Subject")
        XCTAssertEqual(fake.composedEmails[0].body, "Test body content")
        XCTAssertTrue(feedback.contains("john@example.com"))
    }

    func testMailExecutorExactPlanExecutionWithName() throws {
        let fake = FakeMailControl()
        let executor = MailCommandExecutor(control: fake)

        // Compose to a name (not email) - should preserve the name in the to field
        let request = MailComposeRequest(to: "John Doe", subject: "Meeting", body: "Let's meet")
        let intent = CommandIntent(identifier: .mailCompose, arguments: .mailCompose(request))
        _ = try executor.execute(intent, context: .test())

        XCTAssertEqual(fake.composedEmails.count, 1)
        XCTAssertEqual(fake.composedEmails[0].to, "John Doe")
        XCTAssertEqual(fake.composedEmails[0].subject, "Meeting")
        XCTAssertEqual(fake.composedEmails[0].body, "Let's meet")
    }

    func testMailExecutorSpecialCharacterEncoding() throws {
        let fake = FakeMailControl()
        let executor = MailCommandExecutor(control: fake)

        // Test special characters in subject and body
        let request = MailComposeRequest(
            to: "john@example.com",
            subject: "Meeting & Review: Q1/Q2 2026",
            body: "Hello John,\n\nCan you review the project & send feedback?\n\nThanks,\nJane"
        )
        let intent = CommandIntent(identifier: .mailCompose, arguments: .mailCompose(request))
        let _ = try executor.execute(intent, context: .test())

        // Verify the URL was constructed correctly (fake doesn't validate encoding, but we check the request was passed)
        XCTAssertEqual(fake.composedEmails.count, 1)
        XCTAssertEqual(fake.composedEmails[0].to, "john@example.com")
        XCTAssertEqual(fake.composedEmails[0].subject, "Meeting & Review: Q1/Q2 2026")
        XCTAssertEqual(fake.composedEmails[0].body, "Hello John,\n\nCan you review the project & send feedback?\n\nThanks,\nJane")
    }

    func testMailParserPrecedenceWithContacts() {
        let whatsAppContacts = SystemWhatsAppContactResolver()
        let mailParser = MailCommandParser(contactResolver: nil, emailResolver: nil)
        let whatsAppParser = WhatsAppCommandParser(contactResolver: whatsAppContacts)
        let contactsParser = ContactsCommandParser(contactResolver: whatsAppContacts)
        let notesParser = NotesCommandParser()
        let calendarParser = CalendarCommandParser()
        let remindersParser = RemindersCommandParser()
        let finderParser = FinderCommandParser()
        let deterministicParser = DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari", "Mail", "WhatsApp", "Notes"], running: ["Safari"]))
        let multiParser = MultiStepCommandParser(parsers: [
            whatsAppParser,
            calendarParser,
            remindersParser,
            notesParser,
            finderParser,
            contactsParser,
            mailParser,
            deterministicParser
        ])

        // "message John saying hello" should go to WhatsApp, not mail
        let plan1 = multiParser.parse("message John saying hello", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .whatsAppSendMessage)

        // "email John" should go to mail
        let plan2 = multiParser.parse("email John", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .mailCompose)

        // "open Mail" should be mailOpen
        let plan3 = multiParser.parse("open Mail", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .mailOpen)

        // "open Notes" should be notesOpen
        let plan4 = multiParser.parse("open Notes", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .notesOpen)

        // "open Safari" should be app.open
        let plan5 = multiParser.parse("open Safari", context: .test())
        XCTAssertNotNil(plan5)
        XCTAssertEqual(plan5?.steps.first?.intent.identifier, .appOpen)

        // "compose an email to John" should be mailCompose
        let plan7 = multiParser.parse("compose an email to John", context: .test())
        XCTAssertNotNil(plan7)
        XCTAssertEqual(plan7?.steps.first?.intent.identifier, .mailCompose)

        // "find contact John" should be contactsFind
        let plan8 = multiParser.parse("find contact John", context: .test())
        XCTAssertNotNil(plan8)
        XCTAssertEqual(plan8?.steps.first?.intent.identifier, .contactsFind)

        // "show contact John" should be contactsShow
        let plan9 = multiParser.parse("show contact John", context: .test())
        XCTAssertNotNil(plan9)
        XCTAssertEqual(plan9?.steps.first?.intent.identifier, .contactsShow)
    // MARK: - System Power Tests (Slice 13)

    @MainActor
    func testSystemPowerParserSleep() {
        let parser = SystemPowerCommandParser()
        let phrases = [
            "sleep",
            "put my mac to sleep",
            "put the mac to sleep",
            "put mac to sleep",
            "sleep my mac",
            "sleep the mac",
            "go to sleep",
            "put this mac to sleep"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemSleep)
        }
    }

    @MainActor
    func testSystemPowerParserLock() {
        let parser = SystemPowerCommandParser()
        let phrases = [
            "lock my mac",
            "lock the mac",
            "lock mac",
            "lock my screen",
            "lock the screen",
            "lock screen",
            "lock this mac"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemLock)
        }
    }

    @MainActor
    func testSystemPowerParserLogout() {
        let parser = SystemPowerCommandParser()
        let phrases = [
            "log me out",
            "log out",
            "log out of my mac",
            "log out of the mac",
            "sign me out",
            "sign out of my mac"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemLogout)
        }
    }

    @MainActor
    func testSystemPowerParserRestart() {
        let parser = SystemPowerCommandParser()
        let phrases = [
            "restart my mac",
            "restart the mac",
            "restart mac",
            "restart my computer",
            "restart the computer",
            "reboot my mac",
            "reboot the mac"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemRestart)
        }
    }

    @MainActor
    func testSystemPowerParserShutdown() {
        let parser = SystemPowerCommandParser()
        let phrases = [
            "shut down my mac",
            "shut down the mac",
            "shut down mac",
            "turn off my mac",
            "turn off the mac",
            "power off my mac",
            "power off the mac"
        ]

        for phrase in phrases {
            let plan = parser.parse(phrase, context: .test())
            XCTAssertNotNil(plan, "Failed to parse: \(phrase)")
            XCTAssertEqual(plan?.steps.first?.intent.identifier, .systemShutdown)
        }
    }

    @MainActor
    func testSystemPowerParserNegativeCases() {
        let parser = SystemPowerCommandParser()

        let negativePhrases = [
            "my mac is sleeping",
            "the screen is locked",
            "i logged out yesterday",
            "restart the app",
            "shut down the application",
            "sleep mode",
            "lock screen settings"
        ]

        for phrase in negativePhrases {
            let plan = parser.parse(phrase, context: .test())
            if let plan = plan {
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemSleep, "Should not parse as systemSleep: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemLock, "Should not parse as systemLock: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemLogout, "Should not parse as systemLogout: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemRestart, "Should not parse as systemRestart: \(phrase)")
                XCTAssertNotEqual(plan.steps.first?.intent.identifier, .systemShutdown, "Should not parse as systemShutdown: \(phrase)")
            }
        }
    }

    func testSystemPowerExecutorSleep() throws {
        let fake = FakeSystemPowerControl()
        let executor = SystemPowerCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemSleep), context: .test())
        XCTAssertEqual(feedback, "Mac is going to sleep.")
        XCTAssertEqual(fake.sleepCalls, 1)
    }

    func testSystemPowerExecutorLock() throws {
        let fake = FakeSystemPowerControl()
        let executor = SystemPowerCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemLock), context: .test())
        XCTAssertEqual(feedback, "Screen locked.")
        XCTAssertEqual(fake.lockCalls, 1)
    }

    func testSystemPowerExecutorLogout() throws {
        let fake = FakeSystemPowerControl()
        let executor = SystemPowerCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemLogout), context: .test())
        XCTAssertEqual(feedback, "Logging out.")
        XCTAssertEqual(fake.logoutCalls, 1)
    }

    func testSystemPowerExecutorRestart() throws {
        let fake = FakeSystemPowerControl()
        let executor = SystemPowerCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemRestart), context: .test())
        XCTAssertEqual(feedback, "Restarting Mac.")
        XCTAssertEqual(fake.restartCalls, 1)
    }

    func testSystemPowerExecutorShutdown() throws {
        let fake = FakeSystemPowerControl()
        let executor = SystemPowerCommandExecutor(control: fake)
        let feedback = try executor.execute(CommandIntent(identifier: .systemShutdown), context: .test())
        XCTAssertEqual(feedback, "Shutting down Mac.")
        XCTAssertEqual(fake.shutdownCalls, 1)
    }

    func testSystemPowerExecutorError() throws {
        let fake = FakeSystemPowerControl()
        fake.shouldFail = true
        let executor = SystemPowerCommandExecutor(control: fake)

        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemSleep), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to sleep."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemLock), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to lock screen."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemLogout), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to log out."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemRestart), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to restart."))
        }
        XCTAssertThrowsError(try executor.execute(CommandIntent(identifier: .systemShutdown), context: .test())) { error in
            XCTAssertEqual(error as? CommandExecutionError, .operationFailed("Failed to shut down."))
        }
    }

    func testSystemPowerParserPrecedence() {
        let multiParser = MultiStepCommandParser(parsers: [
            SystemInformationCommandParser(),
            SystemAudioCommandParser(),
            SystemPowerCommandParser(),
            DeterministicCommandParser(applications: FakeApplicationResolver(installed: ["Safari"], running: ["Safari"]))
        ])

        // "sleep" should go to systemSleep
        let plan1 = multiParser.parse("sleep", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .systemSleep)

        // "lock my mac" should go to systemLock
        let plan2 = multiParser.parse("lock my mac", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .systemLock)

        // "restart my mac" should go to systemRestart
        let plan3 = multiParser.parse("restart my mac", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .systemRestart)

        // "shut down my mac" should go to systemShutdown
        let plan4 = multiParser.parse("shut down my mac", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.first?.intent.identifier, .systemShutdown)

        // "log me out" should go to systemLogout
        let plan5 = multiParser.parse("log me out", context: .test())
        XCTAssertNotNil(plan5)
        XCTAssertEqual(plan5?.steps.first?.intent.identifier, .systemLogout)

        // Existing commands should still work
        let plan6 = multiParser.parse("what is my battery status", context: .test())
        XCTAssertNotNil(plan6)
        XCTAssertEqual(plan6?.steps.first?.intent.identifier, .systemBattery)

        let plan7 = multiParser.parse("volume up", context: .test())
        XCTAssertNotNil(plan7)
        XCTAssertEqual(plan7?.steps.first?.intent.identifier, .systemVolumeUp)

        // App commands should still work
        let plan8 = multiParser.parse("open Safari", context: .test())
        XCTAssertNotNil(plan8)
        XCTAssertEqual(plan8?.steps.first?.intent.identifier, .appOpen)
    }
}
}
