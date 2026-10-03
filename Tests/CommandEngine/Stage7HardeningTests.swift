import XCTest
@testable import DailyOps

@MainActor
final class Stage7HardeningTests: XCTestCase {

    // MARK: - 1. Finder & Browser Boundary Tests

    func testOpenMyBrowserNotHijackedByFinder() {
        let finderParser = FinderCommandParser()
        let planFromFinder = finderParser.parse("open my browser", context: .test())
        XCTAssertNil(planFromFinder, "FinderCommandParser must not hijack 'open my browser'")

        let resolver = FakeApplicationResolver(installed: ["Safari", "Google Chrome"])
        let deterministicParser = DeterministicCommandParser(applications: resolver)
        let planFromDeterministic = deterministicParser.parse("open my browser", context: .test())
        XCTAssertNotNil(planFromDeterministic)
        XCTAssertEqual(planFromDeterministic?.steps.first?.intent.identifier, .browserOpenDefault)
    }

    func testOpenDefaultBrowserAndPrivateAliases() {
        let resolver = FakeApplicationResolver(installed: ["Safari"])
        let parser = DeterministicCommandParser(applications: resolver)

        let planDefault = parser.parse("open default browser", context: .test())
        XCTAssertNotNil(planDefault)
        XCTAssertEqual(planDefault?.steps.first?.intent.identifier, .browserOpenDefault)

        let planPrivateTab = parser.parse("open private tab", context: .test())
        XCTAssertNotNil(planPrivateTab)
        XCTAssertEqual(planPrivateTab?.steps.first?.intent.identifier, .browserOpenPrivate)

        let planIncognito = parser.parse("open incognito", context: .test())
        XCTAssertNotNil(planIncognito)
        XCTAssertEqual(planIncognito?.steps.first?.intent.identifier, .browserOpenPrivate)

        let planIncognitoWindow = parser.parse("open incognito window", context: .test())
        XCTAssertNotNil(planIncognitoWindow)
        XCTAssertEqual(planIncognitoWindow?.steps.first?.intent.identifier, .browserOpenPrivate)
    }

    func testBrowserSearchAndURLQueries() {
        let resolver = FakeApplicationResolver(installed: [])
        let parser = DeterministicCommandParser(applications: resolver)

        let planSearch = parser.parse("search Google for React tutorials", context: .test())
        XCTAssertNotNil(planSearch)
        XCTAssertEqual(planSearch?.steps.first?.intent.identifier, .browserSearch)
        if case .search(let req) = planSearch?.steps.first?.intent.arguments {
            XCTAssertEqual(req.query, "React tutorials")
            XCTAssertEqual(req.provider, .google)
        } else {
            XCTFail("Wrong argument type")
        }

        let planURL = parser.parse("open github.com", context: .test())
        XCTAssertNotNil(planURL)
        XCTAssertEqual(planURL?.steps.first?.intent.identifier, .browserOpenURL)
        if case .url(let url) = planURL?.steps.first?.intent.arguments {
            XCTAssertEqual(url.host, "github.com")
        } else {
            XCTFail("Wrong argument type")
        }
    }

    func testFinderDoesNotInterceptNaturalDictation() {
        let finderParser = FinderCommandParser()
        XCTAssertNil(finderParser.parse("open the door please", context: .test()))
        XCTAssertNil(finderParser.parse("open my eyes", context: .test()))
        XCTAssertNil(finderParser.parse("open the window", context: .test()))

        // Explicit custom folder queries must work
        let planProjects = finderParser.parse("open my Projects folder", context: .test())
        XCTAssertNotNil(planProjects)
        if case .finderLocation(let target) = planProjects?.steps.first?.intent.arguments {
            XCTAssertEqual(target.location, .custom)
            XCTAssertEqual(target.customName, "Projects")
        } else {
            XCTFail("Expected custom location")
        }

        let planFolderCode = finderParser.parse("open folder Code", context: .test())
        XCTAssertNotNil(planFolderCode)
        if case .finderLocation(let target) = planFolderCode?.steps.first?.intent.arguments {
            XCTAssertEqual(target.location, .custom)
            XCTAssertEqual(target.customName, "Code")
        } else {
            XCTFail("Expected custom location")
        }
    }

    // MARK: - 2. Calendar Hardening Tests

    func testCalendarWeekdayResolution() {
        let parser = CalendarCommandParser()
        let plan = parser.parse("what's on my calendar Monday", context: .test())
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.first?.intent.identifier, .calendarListEvents)
        if case .calendarQuery(let query) = plan?.steps.first?.intent.arguments {
            XCTAssertEqual(query.day, .specificDate)
            XCTAssertNotNil(query.date)
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: query.date!)
            XCTAssertEqual(weekday, 2, "Monday corresponds to weekday 2")
        } else {
            XCTFail("Wrong argument type")
        }
    }

    func testCalendarShowMyEventsQueries() {
        let parser = CalendarCommandParser()

        let plan1 = parser.parse("show my events", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .calendarListEvents)
        if case .calendarQuery(let q) = plan1?.steps.first?.intent.arguments {
            XCTAssertEqual(q.day, .today)
        }

        let plan2 = parser.parse("show events tomorrow", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .calendarListEvents)
        if case .calendarQuery(let q) = plan2?.steps.first?.intent.arguments {
            XCTAssertEqual(q.day, .tomorrow)
        }
    }

    func testCalendarEventCreationWithNaturalPrefixesAndImplicitTitles() {
        let parser = CalendarCommandParser()

        // 1. "create an event called Project Review Friday at 5 PM"
        let plan1 = parser.parse("create an event called Project Review Friday at 5 PM", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.first?.intent.identifier, .calendarCreateEvent)
        if case .calendarEvent(let event) = plan1?.steps.first?.intent.arguments {
            XCTAssertEqual(event.title, "Project Review")
            XCTAssertNotNil(event.startTime)
            let hour = Calendar.current.component(.hour, from: event.startTime!)
            XCTAssertEqual(hour, 17)
        } else {
            XCTFail("Expected calendarEvent argument")
        }

        // 2. "schedule a meeting tomorrow at 3 PM" -> title "Meeting"
        let plan2 = parser.parse("schedule a meeting tomorrow at 3 PM", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.first?.intent.identifier, .calendarCreateEvent)
        if case .calendarEvent(let event) = plan2?.steps.first?.intent.arguments {
            XCTAssertEqual(event.title, "Meeting")
            XCTAssertNotNil(event.startTime)
            let hour = Calendar.current.component(.hour, from: event.startTime!)
            XCTAssertEqual(hour, 15)
        } else {
            XCTFail("Expected calendarEvent argument")
        }

        // 3. "create an event tomorrow at 3 PM" -> title "Event"
        let plan3 = parser.parse("create an event tomorrow at 3 PM", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.first?.intent.identifier, .calendarCreateEvent)
        if case .calendarEvent(let event) = plan3?.steps.first?.intent.arguments {
            XCTAssertEqual(event.title, "Event")
        } else {
            XCTFail("Expected calendarEvent argument")
        }

        // 4. "schedule team meeting tomorrow at 10 AM for 1 hour"
        let plan4 = parser.parse("schedule team meeting tomorrow at 10 AM for 1 hour", context: .test())
        XCTAssertNotNil(plan4)
        if case .calendarEvent(let event) = plan4?.steps.first?.intent.arguments {
            XCTAssertEqual(event.title, "team meeting")
            XCTAssertEqual(event.duration, 3600)
            let hour = Calendar.current.component(.hour, from: event.startTime!)
            XCTAssertEqual(hour, 10)
        } else {
            XCTFail("Expected calendarEvent argument")
        }
    }

    // MARK: - 3. Reminders Hardening Tests

    func testRemindersListQueries() {
        let parser = RemindersCommandParser()

        let planToday = parser.parse("what reminders do I have today", context: .test())
        XCTAssertNotNil(planToday)
        XCTAssertEqual(planToday?.steps.first?.intent.identifier, .remindersList)
        if case .reminderQuery(let q) = planToday?.steps.first?.intent.arguments {
            XCTAssertEqual(q.dueDay, .today)
        }

        let planTomorrow = parser.parse("what reminders do I have tomorrow", context: .test())
        XCTAssertNotNil(planTomorrow)
        XCTAssertEqual(planTomorrow?.steps.first?.intent.identifier, .remindersList)
        if case .reminderQuery(let q) = planTomorrow?.steps.first?.intent.arguments {
            XCTAssertEqual(q.dueDay, .tomorrow)
        }
    }

    func testRemindersEmptyTitleGuarding() {
        let parser = RemindersCommandParser()

        // Bare phrases without title must not parse into reminders
        XCTAssertNil(parser.parse("remind me tomorrow", context: .test()))
        XCTAssertNil(parser.parse("remind me", context: .test()))
        XCTAssertNil(parser.parse("remind me to", context: .test()))

        // Valid reminders
        let plan1 = parser.parse("remind me to submit my assignment", context: .test())
        XCTAssertNotNil(plan1)
        if case .reminder(let req) = plan1?.steps.first?.intent.arguments {
            XCTAssertEqual(req.title, "submit my assignment")
        }

        let plan2 = parser.parse("remind me tomorrow to submit my assignment", context: .test())
        XCTAssertNotNil(plan2)
        if case .reminder(let req) = plan2?.steps.first?.intent.arguments {
            XCTAssertEqual(req.title, "submit my assignment")
            XCTAssertNotNil(req.dueDate)
        }

        let plan3 = parser.parse("remind me to call John tomorrow at 8 PM", context: .test())
        XCTAssertNotNil(plan3)
        if case .reminder(let req) = plan3?.steps.first?.intent.arguments {
            XCTAssertEqual(req.title, "call John")
            XCTAssertNotNil(req.dueDate)
            XCTAssertNotNil(req.dueTime)
            let hour = Calendar.current.component(.hour, from: req.dueTime!)
            XCTAssertEqual(hour, 20)
        }
    }

    // MARK: - 4. Multi-Step Pipeline Hardening Tests

    func testMultiStepCalendarAndRemindersSequences() {
        let calendarParser = CalendarCommandParser()
        let remindersParser = RemindersCommandParser()
        let finderParser = FinderCommandParser()
        let multiParser = MultiStepCommandParser(parsers: [
            calendarParser,
            remindersParser,
            finderParser
        ])

        // "open Calendar and show my events"
        let plan1 = multiParser.parse("open Calendar and show my events", context: .test())
        XCTAssertNotNil(plan1)
        XCTAssertEqual(plan1?.steps.count, 2)
        XCTAssertEqual(plan1?.steps[0].intent.identifier, .calendarOpen)
        XCTAssertEqual(plan1?.steps[1].intent.identifier, .calendarListEvents)

        // "open Calendar and create an event tomorrow at 3 PM"
        let plan2 = multiParser.parse("open Calendar and create an event tomorrow at 3 PM", context: .test())
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps.count, 2)
        XCTAssertEqual(plan2?.steps[0].intent.identifier, .calendarOpen)
        XCTAssertEqual(plan2?.steps[1].intent.identifier, .calendarCreateEvent)

        // "open Reminders and show today's reminders"
        let plan3 = multiParser.parse("open Reminders and show today's reminders", context: .test())
        XCTAssertNotNil(plan3)
        XCTAssertEqual(plan3?.steps.count, 2)
        XCTAssertEqual(plan3?.steps[0].intent.identifier, .remindersOpen)
        XCTAssertEqual(plan3?.steps[1].intent.identifier, .remindersList)

        // "open Downloads and then open Finder"
        let plan4 = multiParser.parse("open Downloads and then open Finder", context: .test())
        XCTAssertNotNil(plan4)
        XCTAssertEqual(plan4?.steps.count, 2)
        XCTAssertEqual(plan4?.steps[0].intent.identifier, .finderOpenLocation)
        XCTAssertEqual(plan4?.steps[1].intent.identifier, .finderOpenLocation)
    }

    // MARK: - 5. Validation Hardening Tests

    func testValidatorRejectsEmptyTitles() {
        let validator = CommandValidator(registry: .standard())

        // Empty title in reminder
        let emptyReminderPlan = CommandPlan(intent: CommandIntent(
            identifier: .remindersCreate,
            arguments: .reminder(ReminderRequest(title: "   "))
        ))
        XCTAssertThrowsError(try validator.validate(emptyReminderPlan, context: .test())) { error in
            guard let valError = error as? CommandValidationError,
                  case .invalidArguments = valError else {
                return XCTFail("Expected invalidArguments error")
            }
        }

        // Empty title in calendar event
        let emptyCalendarPlan = CommandPlan(intent: CommandIntent(
            identifier: .calendarCreateEvent,
            arguments: .calendarEvent(CalendarEventRequest(title: "   ", date: Date()))
        ))
        XCTAssertThrowsError(try validator.validate(emptyCalendarPlan, context: .test())) { error in
            guard let valError = error as? CommandValidationError,
                  case .invalidArguments = valError else {
                return XCTFail("Expected invalidArguments error")
            }
        }

        // Empty title in note
        let emptyNotePlan = CommandPlan(intent: CommandIntent(
            identifier: .notesCreate,
            arguments: .note(NoteRequest(title: "   "))
        ))
        XCTAssertThrowsError(try validator.validate(emptyNotePlan, context: .test())) { error in
            guard let valError = error as? CommandValidationError,
                  case .invalidArguments = valError else {
                return XCTFail("Expected invalidArguments error")
            }
        }
    }

    // MARK: - 6. Confirmation Hardening Tests

    func testConfirmationDetailsEnrichment() {
        let manager = ConfirmationManager()
        let plan = CommandPlan(intent: CommandIntent(
            identifier: .calendarCreateEvent,
            arguments: .calendarEvent(CalendarEventRequest(title: "Team Sync", date: Date()))
        ))
        let def = CommandDefinition(identifier: .calendarCreateEvent, name: "Create Event", risk: .sensitive, confirmation: .mandatory)
        let request = manager.requestConfirmation(for: plan, definition: def, context: .test(), reason: "Needs approval")

        XCTAssertTrue(request.details.contains("Team Sync"))
        XCTAssertTrue(request.title.contains("Create Calendar Event"))
        XCTAssertEqual(request.confirmActionLabel, "Create Event")
    }

    func testConfirmationManagerRejectStaleAndAlreadyResolved() {
        let manager = ConfirmationManager()
        let plan = CommandPlan(intent: CommandIntent(identifier: .appQuit, arguments: .application(ApplicationReference(displayName: "Safari"))))
        let def = CommandDefinition(identifier: .appQuit, name: "Quit Application", risk: .destructive, confirmation: .mandatory)
        let request = manager.requestConfirmation(for: plan, definition: def, context: .test(), reason: "Quit Safari")

        // First resolution succeeds
        let res1 = manager.resolve(id: request.id, decision: .confirm)
        if case .confirmed = res1 {} else { XCTFail("Expected confirmed") }

        // Second resolution of same ID rejected
        let res2 = manager.resolve(id: request.id, decision: .confirm)
        if case .rejected(let reason) = res2 {
            XCTAssertEqual(reason, .alreadyResolved)
        } else {
            XCTFail("Expected alreadyResolved")
        }

        // Resolving an unknown ID rejected
        let res3 = manager.resolve(id: ConfirmationRequestID(), decision: .confirm)
        if case .rejected(let reason) = res3 {
            XCTAssertEqual(reason, .noPendingRequest)
        } else {
            XCTFail("Expected noPendingRequest")
        }
    }
}
