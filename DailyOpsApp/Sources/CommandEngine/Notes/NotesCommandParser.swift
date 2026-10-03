import Foundation

/// Parses Notes voice commands into structured CommandPlans.
@MainActor
struct NotesCommandParser: CommandParsing {
    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }

        // 1. Open Notes
        if isOpenNotesCommand(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .notesOpen))
        }

        // 2. Create Note
        if let request = parseCreateNoteCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .notesCreate,
                arguments: .note(request)
            ))
        }

        // 3. Find Notes by topic
        if let request = parseFindNotesCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .notesFind,
                arguments: .noteFind(request)
            ))
        }

        // 4. Open specific note by topic
        if let request = parseOpenNoteCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .notesOpenNote,
                arguments: .noteOpen(request)
            ))
        }

        return nil
    }

    private func isOpenNotesCommand(_ lower: String) -> Bool {
        let openPrefixes = [
            "open notes", "launch notes", "start notes", "go to notes", "open my notes", "show notes"
        ]
        return openPrefixes.contains { lower.hasPrefix($0) }
    }

    private func parseCreateNoteCommand(raw: String, lower: String) -> NoteRequest? {
        // "add this to my notes" / "add to my notes"
        if lower == "add this to my notes" || lower == "add to my notes" || lower == "add to notes" {
            return NoteRequest(title: "New Note", body: nil)
        }

        // Patterns with "saying" separating title and body:
        // "create a note called Meeting Notes saying John will review the project tomorrow"
        // "make a note called Meeting Notes saying John will review..."
        let createPrefixesWithCalled = [
            "create a note called ",
            "create a note named ",
            "create note called ",
            "create note named ",
            "make a note called ",
            "make a note named ",
            "make note called ",
            "make note named "
        ]

        for prefix in createPrefixesWithCalled {
            if lower.hasPrefix(prefix) {
                let restRaw = String(raw.dropFirst(prefix.count))
                let restLower = String(lower.dropFirst(prefix.count))

                if let sayingRange = restLower.range(of: " saying ") {
                    let title = String(restRaw[..<sayingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let body = String(restRaw[sayingRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty {
                        return NoteRequest(title: title, body: body.isEmpty ? nil : body)
                    }
                } else {
                    let title = restRaw.trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty {
                        return NoteRequest(title: title, body: nil)
                    }
                }
            }
        }

        // "create a note saying <Body>" / "make a note saying <Body>"
        let sayingPrefixes = [
            "create a note saying ",
            "create note saying ",
            "make a note saying ",
            "make note saying "
        ]

        for prefix in sayingPrefixes {
            if lower.hasPrefix(prefix) {
                let body = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty {
                    let titleWords = body.components(separatedBy: .whitespaces).prefix(5).joined(separator: " ")
                    return NoteRequest(title: titleWords, body: body)
                }
            }
        }

        // Generic "create a note <Title>" / "make a note <Title>"
        let genericPrefixes = [
            "create a note ",
            "create note ",
            "make a note ",
            "make note "
        ]

        for prefix in genericPrefixes {
            if lower.hasPrefix(prefix) {
                let title = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return NoteRequest(title: title, body: nil)
                }
            }
        }

        return nil
    }

    private func parseFindNotesCommand(raw: String, lower: String) -> NoteFindRequest? {
        let findPrefixes = [
            "find notes about ",
            "search notes for ",
            "search notes ",
            "find my notes about ",
            "search my notes for ",
            "search my notes ",
            "look for notes about ",
            "find note about ",
            "search note for "
        ]

        for prefix in findPrefixes {
            if lower.hasPrefix(prefix) {
                let query = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return NoteFindRequest(query: query)
                }
            }
        }
        return nil
    }

    private func parseOpenNoteCommand(raw: String, lower: String) -> NoteOpenRequest? {
        let openPrefixes = [
            "open the note about ",
            "open note about ",
            "open my note about ",
            "show the note about ",
            "show note about ",
            "show my note about "
        ]

        for prefix in openPrefixes {
            if lower.hasPrefix(prefix) {
                let query = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return NoteOpenRequest(query: query)
                }
            }
        }
        return nil
    }
}
