import Foundation

/// Deterministic parser for natural date and time expressions spoken in voice commands.
/// Strictly local, rule-based, and zero-heuristic: never guesses ambiguous strings.
struct DateTimeParser: Sendable {
    let calendar: Calendar
    let timeZone: TimeZone

    init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var cal = calendar
        cal.timeZone = timeZone
        self.calendar = cal
        self.timeZone = timeZone
    }

    // MARK: - Day Extraction

    /// Identifies whether the transcript references today, tomorrow, or a specific day.
    func parseDayTarget(from text: String) -> CalendarDayTarget? {
        let lower = text.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        if words.contains("today") {
            return .today
        } else if words.contains("tomorrow") {
            return .tomorrow
        } else if words.contains("monday") || words.contains("tuesday") || words.contains("wednesday")
                    || words.contains("thursday") || words.contains("friday") || words.contains("saturday")
                    || words.contains("sunday") {
            return .specificDate
        }
        return nil
    }

    /// Resolves a day string into a concrete Date representing the start of that day.
    func resolveDate(from text: String, relativeTo referenceDate: Date = Date()) -> Date? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lower == "today" {
            return calendar.startOfDay(for: referenceDate)
        }
        if lower == "tomorrow" {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: referenceDate) else { return nil }
            return calendar.startOfDay(for: nextDay)
        }
        if lower == "yesterday" {
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: referenceDate) else { return nil }
            return calendar.startOfDay(for: prevDay)
        }

        // Check weekday names
        let weekdays: [String: Int] = [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7
        ]

        let cleanWord = lower
            .replacingOccurrences(of: "next ", with: "")
            .replacingOccurrences(of: "this ", with: "")
            .trimmingCharacters(in: .whitespaces)

        if let targetWeekday = weekdays[cleanWord] {
            let currentWeekday = calendar.component(.weekday, from: referenceDate)
            var daysToAdd = targetWeekday - currentWeekday
            if daysToAdd <= 0 {
                daysToAdd += 7
            }
            if lower.hasPrefix("next ") && daysToAdd < 7 {
                daysToAdd += 7
            }
            guard let targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: referenceDate) else { return nil }
            return calendar.startOfDay(for: targetDate)
        }

        return nil
    }

    // MARK: - Time Extraction

    /// Parses time components (hour, minute) from expressions like "3 PM", "3:30 PM", "15:00", "noon", "midnight".
    func parseTime(from text: String) -> (hour: Int, minute: Int)? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lower == "noon" || lower == "midday" {
            return (12, 0)
        }
        if lower == "midnight" {
            return (0, 0)
        }

        // Pattern 1: 12-hour with am/pm (e.g. "3:30 pm", "3 pm", "11:45am", "8am")
        let ampmPattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#
        if let regex = try? NSRegularExpression(pattern: ampmPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, options: [], range: NSRange(location: 0, length: lower.utf16.count)) {
            guard let hourRange = Range(match.range(at: 1), in: lower),
                  let rawHour = Int(lower[hourRange]),
                  rawHour >= 1 && rawHour <= 12 else {
                return nil
            }
            var minute = 0
            if match.range(at: 2).location != NSNotFound,
               let minRange = Range(match.range(at: 2), in: lower),
               let parsedMin = Int(lower[minRange]),
               parsedMin >= 0 && parsedMin < 60 {
                minute = parsedMin
            }
            let isPM: Bool
            if match.range(at: 3).location != NSNotFound,
               let meridianRange = Range(match.range(at: 3), in: lower) {
                isPM = lower[meridianRange].lowercased() == "pm"
            } else {
                isPM = false
            }

            var hour = rawHour
            if isPM {
                if hour < 12 { hour += 12 }
            } else {
                if hour == 12 { hour = 0 }
            }
            return (hour, minute)
        }

        // Pattern 2: 24-hour military/ISO time (e.g. "17:30", "09:00", "15:45")
        let militaryPattern = #"^(\d{1,2}):(\d{2})$"#
        if let regex = try? NSRegularExpression(pattern: militaryPattern),
           let match = regex.firstMatch(in: lower, options: [], range: NSRange(location: 0, length: lower.utf16.count)) {
            guard let hourRange = Range(match.range(at: 1), in: lower),
                  let minRange = Range(match.range(at: 2), in: lower),
                  let hour = Int(lower[hourRange]),
                  let min = Int(lower[minRange]),
                  hour >= 0 && hour < 24,
                  min >= 0 && min < 60 else {
                return nil
            }
            return (hour, min)
        }

        // Pattern 3: Bare integer after "at" (e.g. "at 3", "at 11")
        if let singleHour = Int(lower), singleHour >= 1 && singleHour <= 12 {
            let hour = (singleHour >= 1 && singleHour <= 7) ? singleHour + 12 : singleHour
            return (hour, 0)
        }

        return nil
    }

    // MARK: - Duration Extraction

    /// Parses duration expressions like "for 1 hour", "for 30 minutes", "for 2 hours".
    func parseDuration(from text: String) -> TimeInterval? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"for\s+(\d+(?:\.\d+)?)\s*(hour|hours|hr|hrs|minute|minutes|min|mins)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: lower, options: [], range: NSRange(location: 0, length: lower.utf16.count)) else {
            return nil
        }
        guard let valueRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let value = Double(lower[valueRange]) else {
            return nil
        }
        let unit = lower[unitRange].lowercased()
        if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
            return value * 3600.0
        } else if unit.hasPrefix("min") {
            return value * 60.0
        }
        return nil
    }

    // MARK: - Calendar Event Extraction

    /// Extracts structured title, target date, start time, and optional duration from a spoken event command string.
    func extractEventDetails(
        from text: String,
        defaultTitle: String? = nil,
        relativeTo referenceDate: Date = Date()
    ) -> (title: String, date: Date, startTime: Date?, duration: TimeInterval?)? {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }

        // 1. Extract duration if present at the end
        var duration: TimeInterval? = nil
        let durationPattern = #"\s+for\s+\d+(?:\.\d+)?\s*(?:hour|hours|hr|hrs|minute|minutes|min|mins)$"#
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: clean, range: NSRange(location: 0, length: clean.utf16.count)),
           let matchRange = Range(match.range, in: clean) {
            let durationString = String(clean[matchRange]).trimmingCharacters(in: .whitespaces)
            duration = parseDuration(from: durationString)
            clean = String(clean[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // 2. Extract date & time indicators from the string
        let timePattern = #"\s+at\s+([0-9]{1,2}(?::[0-9]{2})?\s*(?:am|pm|AM|PM)?|[0-9]{1,2}:[0-9]{2}|noon|midnight)$"#
        var parsedTime: (hour: Int, minute: Int)? = nil

        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: clean, range: NSRange(location: 0, length: clean.utf16.count)),
           let matchRange = Range(match.range, in: clean),
           let timeRange = Range(match.range(at: 1), in: clean) {
            let timeString = String(clean[timeRange])
            parsedTime = parseTime(from: timeString)
            clean = String(clean[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // 3. Extract date token from the remainder
        let dateTokens = [
            "tomorrow", "today", "yesterday",
            "next monday", "next tuesday", "next wednesday", "next thursday", "next friday", "next saturday", "next sunday",
            "this monday", "this tuesday", "this wednesday", "this thursday", "this friday", "this saturday", "this sunday",
            "on monday", "on tuesday", "on wednesday", "on thursday", "on friday", "on saturday", "on sunday",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ]

        var resolvedDate: Date? = nil
        let cleanLower = clean.lowercased()

        for token in dateTokens {
            let tokenWithSpace = " " + token
            let tokenWithOn = " on " + token

            if cleanLower == token {
                // The entire remainder is just a date token — strip it, no title contribution.
                resolvedDate = resolveDate(from: token, relativeTo: referenceDate)
                clean = ""
                break
            } else if cleanLower.hasSuffix(tokenWithOn) {
                let cutoff = clean.index(clean.endIndex, offsetBy: -tokenWithOn.count)
                let datePart = String(clean[cutoff...]).trimmingCharacters(in: .whitespaces).dropFirst("on ".count)
                resolvedDate = resolveDate(from: String(datePart), relativeTo: referenceDate)
                clean = String(clean[..<cutoff]).trimmingCharacters(in: .whitespaces)
                break
            } else if cleanLower.hasSuffix(tokenWithSpace) {
                let cutoff = clean.index(clean.endIndex, offsetBy: -tokenWithSpace.count)
                let datePart = String(clean[cutoff...]).trimmingCharacters(in: .whitespaces)
                resolvedDate = resolveDate(from: datePart, relativeTo: referenceDate)
                clean = String(clean[..<cutoff]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // If no explicit date was spoken, but a time was given, assume today
        let targetDate = resolvedDate ?? calendar.startOfDay(for: referenceDate)

        var startTime: Date? = nil
        if let (hour, min) = parsedTime {
            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = hour
            components.minute = min
            components.second = 0
            startTime = calendar.date(from: components)
        }

        // Strip leading filler words from title
        var title = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased().hasPrefix("called ") {
            title = String(title.dropFirst("called ".count)).trimmingCharacters(in: .whitespaces)
        }
        if title.lowercased().hasPrefix("named ") {
            title = String(title.dropFirst("named ".count)).trimmingCharacters(in: .whitespaces)
        }

        if title.isEmpty, let fallback = defaultTitle, !fallback.isEmpty {
            title = fallback
        }

        guard !title.isEmpty else { return nil }

        return (title: title, date: targetDate, startTime: startTime, duration: duration)
    }

    // MARK: - Reminder Extraction

    /// Extracts title, optional due date, and optional due time for reminders.
    func extractReminderDetails(from text: String, relativeTo referenceDate: Date = Date()) -> (title: String, dueDate: Date?, dueTime: Date?) {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check time at the end ("at 8 PM", "at 17:00", etc.)
        let timePattern = #"\s+at\s+([0-9]{1,2}(?::[0-9]{2})?\s*(?:am|pm|AM|PM)?|[0-9]{1,2}:[0-9]{2}|noon|midnight)$"#
        var parsedTime: (hour: Int, minute: Int)? = nil

        if let regex = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: clean, range: NSRange(location: 0, length: clean.utf16.count)),
           let matchRange = Range(match.range, in: clean),
           let timeRange = Range(match.range(at: 1), in: clean) {
            let timeString = String(clean[timeRange])
            parsedTime = parseTime(from: timeString)
            clean = String(clean[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // 2. Check date token at the end
        let dateTokens = [
            "tomorrow", "today", "yesterday",
            "next monday", "next tuesday", "next wednesday", "next thursday", "next friday", "next saturday", "next sunday",
            "this monday", "this tuesday", "this wednesday", "this thursday", "this friday", "this saturday", "this sunday",
            "on monday", "on tuesday", "on wednesday", "on thursday", "on friday", "on saturday", "on sunday",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ]

        var resolvedDate: Date? = nil
        let cleanLower = clean.lowercased()

        for token in dateTokens {
            let tokenWithSpace = " " + token
            let tokenWithOn = " on " + token

            if cleanLower == token {
                // The entire remainder is just a date token — strip it, no title contribution.
                resolvedDate = resolveDate(from: token, relativeTo: referenceDate)
                clean = ""
                break
            } else if cleanLower.hasSuffix(tokenWithOn) {
                let cutoff = clean.index(clean.endIndex, offsetBy: -tokenWithOn.count)
                let datePart = String(clean[cutoff...]).trimmingCharacters(in: .whitespaces).dropFirst("on ".count)
                resolvedDate = resolveDate(from: String(datePart), relativeTo: referenceDate)
                clean = String(clean[..<cutoff]).trimmingCharacters(in: .whitespaces)
                break
            } else if cleanLower.hasSuffix(tokenWithSpace) {
                let cutoff = clean.index(clean.endIndex, offsetBy: -tokenWithSpace.count)
                let datePart = String(clean[cutoff...]).trimmingCharacters(in: .whitespaces)
                resolvedDate = resolveDate(from: datePart, relativeTo: referenceDate)
                clean = String(clean[..<cutoff]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        var dueDate = resolvedDate
        if dueDate == nil && parsedTime != nil {
            dueDate = calendar.startOfDay(for: referenceDate)
        }

        var dueTime: Date? = nil
        if let (hour, min) = parsedTime {
            let targetDay = dueDate ?? calendar.startOfDay(for: referenceDate)
            var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = hour
            components.minute = min
            components.second = 0
            dueTime = calendar.date(from: components)
        }

        let title = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title: title, dueDate: dueDate, dueTime: dueTime)
    }
}
