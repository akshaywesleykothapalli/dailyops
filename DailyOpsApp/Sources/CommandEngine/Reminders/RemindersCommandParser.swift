import Foundation

/// Parses Reminders voice commands into structured CommandPlans.
@MainActor
struct RemindersCommandParser: CommandParsing {
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

        // 1. Open Reminders
        if isOpenRemindersCommand(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .remindersOpen))
        }

        // 2. Read / List Reminders
        if let query = parseListRemindersCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .remindersList,
                arguments: .reminderQuery(query)
            ))
        }

        // 3. Create Reminder
        if let request = parseCreateReminderCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .remindersCreate,
                arguments: .reminder(request)
            ))
        }

        // 4. Complete Reminder
        if let request = parseCompleteReminderCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .remindersComplete,
                arguments: .reminderComplete(request)
            ))
        }

        // 5. Delete Reminder
        if let request = parseDeleteReminderCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .remindersDelete,
                arguments: .reminderDelete(request)
            ))
        }

        return nil
    }

    // MARK: - Open Reminders

    private func isOpenRemindersCommand(_ lower: String) -> Bool {
        let openPhrases = [
            "open reminders", "launch reminders", "start reminders", "go to reminders", "open my reminders"
        ]
        return openPhrases.contains(lower)
    }

    // MARK: - Read Reminders

    private func parseListRemindersCommand(raw: String, lower: String) -> ReminderQuery? {
        // "show my reminders", "what are my reminders", "show reminders for today", "show reminders"
        if lower == "show reminders for today"
            || lower == "show today's reminders"
            || lower == "show my reminders for today"
            || lower == "what are my reminders today"
            || lower == "what are my reminders for today"
            || lower == "what reminders do i have today"
            || lower == "what reminders do i have for today"
            || lower == "reminders today"
            || lower == "my reminders today"
            || lower == "list reminders today"
            || lower == "show my reminders today" {
            return ReminderQuery(dueDay: .today)
        }

        if lower == "show reminders for tomorrow"
            || lower == "show tomorrow's reminders"
            || lower == "show my reminders for tomorrow"
            || lower == "show reminders tomorrow"
            || lower == "show my reminders tomorrow"
            || lower == "what are my reminders tomorrow"
            || lower == "what are my reminders for tomorrow"
            || lower == "what reminders do i have tomorrow"
            || lower == "what reminders do i have for tomorrow"
            || lower == "reminders tomorrow"
            || lower == "my reminders tomorrow" {
            return ReminderQuery(dueDay: .tomorrow)
        }

        if lower == "show my reminders"
            || lower == "show reminders"
            || lower == "what are my reminders"
            || lower == "what reminders do i have"
            || lower == "list my reminders"
            || lower == "list reminders"
            || lower == "view reminders" {
            return ReminderQuery(dueDay: nil)
        }

        // Overdue reminders
        if lower == "show overdue reminders"
            || lower == "show my overdue reminders"
            || lower == "what are my overdue reminders"
            || lower == "what reminders are overdue"
            || lower == "what overdue reminders do i have"
            || lower == "list overdue reminders"
            || lower == "overdue reminders"
            || lower == "my overdue reminders" {
            return ReminderQuery(dueDay: .specificDate) // We'll handle this specially in executor
        }

        return nil
    }

    // MARK: - Create Reminder

    private func parseCreateReminderCommand(raw: String, lower: String) -> ReminderRequest? {
        // Form 1: "remind me tomorrow to <Title>" or "remind me today to <Title>"
        if lower.hasPrefix("remind me tomorrow to ") {
            let rest = String(raw.dropFirst("remind me tomorrow to ".count))
            let details = dateTimeParser.extractReminderDetails(from: rest)
            let trimmedTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            let tomorrow = dateTimeParser.resolveDate(from: "tomorrow")
            return ReminderRequest(
                title: trimmedTitle,
                dueDate: details.dueDate ?? tomorrow,
                dueTime: details.dueTime
            )
        }

        if lower.hasPrefix("remind me today to ") {
            let rest = String(raw.dropFirst("remind me today to ".count))
            let details = dateTimeParser.extractReminderDetails(from: rest)
            let trimmedTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            let today = dateTimeParser.resolveDate(from: "today")
            return ReminderRequest(
                title: trimmedTitle,
                dueDate: details.dueDate ?? today,
                dueTime: details.dueTime
            )
        }

        // Form 2: "remind me to <Title>"
        if lower.hasPrefix("remind me to ") {
            let rest = String(raw.dropFirst("remind me to ".count))
            let details = dateTimeParser.extractReminderDetails(from: rest)
            let trimmedTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            return ReminderRequest(
                title: trimmedTitle,
                dueDate: details.dueDate,
                dueTime: details.dueTime
            )
        }

        // Form 3: "remind me <Title>"
        // Bare stopwords that look like sentence fragments must not become reminder titles.
        let bareStopwords: Set<String> = ["to", "a", "an", "the", "about", "of"]
        if lower.hasPrefix("remind me ") && !lower.hasPrefix("remind me of") {
            let rest = String(raw.dropFirst("remind me ".count))
            let details = dateTimeParser.extractReminderDetails(from: rest)
            let trimmedTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, !bareStopwords.contains(trimmedTitle.lowercased()) else { return nil }
            return ReminderRequest(
                title: trimmedTitle,
                dueDate: details.dueDate,
                dueTime: details.dueTime
            )
        }

        // Form 4: "create a reminder called <Title>" / "create a reminder to <Title>" / "add a reminder to <Title>"
        let otherPrefixes = [
            "create a reminder to ",
            "create a reminder called ",
            "create a reminder named ",
            "create a reminder ",
            "create reminder to ",
            "create reminder called ",
            "create reminder ",
            "add a reminder to ",
            "add a reminder called ",
            "add a reminder ",
            "add reminder to ",
            "add reminder "
        ]

        for prefix in otherPrefixes {
            if lower.hasPrefix(prefix) {
                let rest = String(raw.dropFirst(prefix.count))
                let details = dateTimeParser.extractReminderDetails(from: rest)
                let trimmedTitle = details.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty else { return nil }
                return ReminderRequest(
                    title: trimmedTitle,
                    dueDate: details.dueDate,
                    dueTime: details.dueTime
                )
            }
        }

        return nil
    }

    // MARK: - Complete Reminder

    private func parseCompleteReminderCommand(raw: String, lower: String) -> ReminderCompleteRequest? {
        // "complete my groceries reminder"
        // "complete the groceries reminder"
        // "complete reminder groceries"
        // "complete groceries"
        // "mark groceries as done"
        // "mark groceries complete"
        // "mark reminder groceries as complete"
        // "mark reminder groceries complete"

        // First, try specific "mark reminder" patterns
        let markReminderPrefixes = [
            "mark reminder ",
            "check off reminder ",
            "check reminder "
        ]
        for prefix in markReminderPrefixes {
            if lower.hasPrefix(prefix) {
                var clause = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove trailing " as done", " as complete", " complete", " reminder"
                if clause.lowercased().hasSuffix(" as done") {
                    clause = String(clause.dropLast(" as done".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if clause.lowercased().hasSuffix(" as complete") {
                    clause = String(clause.dropLast(" as complete".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if clause.lowercased().hasSuffix(" complete") {
                    clause = String(clause.dropLast(" complete".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if clause.lowercased().hasSuffix(" reminder") {
                    clause = String(clause.dropLast(" reminder".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !clause.isEmpty {
                    return ReminderCompleteRequest(title: clause)
                }
            }
        }

        let completePrefixes = [
            "complete my ",
            "complete the ",
            "complete reminder ",
            "complete ",
            "mark ",
            "check off ",
            "check "
        ]

        for prefix in completePrefixes {
            if lower.hasPrefix(prefix) {
                var clause = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove trailing " reminder" or " as done" or " complete"
                if clause.lowercased().hasSuffix(" reminder") {
                    clause = String(clause.dropLast(" reminder".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if clause.lowercased().hasSuffix(" as done") {
                    clause = String(clause.dropLast(" as done".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if clause.lowercased().hasSuffix(" complete") {
                    clause = String(clause.dropLast(" complete".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !clause.isEmpty {
                    return ReminderCompleteRequest(title: clause)
                }
            }
        }

        return nil
    }

    // MARK: - Delete Reminder

    private func parseDeleteReminderCommand(raw: String, lower: String) -> ReminderDeleteRequest? {
        // "delete my groceries reminder"
        // "delete the groceries reminder"
        // "delete reminder groceries"
        // "delete groceries"
        // "remove my groceries reminder"
        // "remove the groceries reminder"
        // "remove reminder groceries"
        // "remove groceries from reminders"

        let deletePrefixes = [
            "delete my ",
            "delete the ",
            "delete reminder ",
            "delete ",
            "remove my ",
            "remove the ",
            "remove reminder ",
            "remove "
        ]

        for prefix in deletePrefixes {
            if lower.hasPrefix(prefix) {
                var clause = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove trailing " reminder" or " from reminders"
                if clause.lowercased().hasSuffix(" reminder") {
                    clause = String(clause.dropLast(" reminder".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if clause.lowercased().hasSuffix(" from reminders") {
                    clause = String(clause.dropLast(" from reminders".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !clause.isEmpty {
                    return ReminderDeleteRequest(title: clause)
                }
            }
        }

        return nil
    }
}
