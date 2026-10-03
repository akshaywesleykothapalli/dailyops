import Foundation

/// Parses Contacts voice commands into structured CommandPlans.
@MainActor
struct ContactsCommandParser: CommandParsing {
    private let contactResolver: WhatsAppContactResolving

    init(contactResolver: WhatsAppContactResolving) {
        self.contactResolver = contactResolver
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

        // 1. Find/Search Contacts
        if let query = parseFindContactsCommand(lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .contactsFind,
                arguments: .contactsQuery(query)
            ))
        }

        // 2. Show Contact
        if let query = parseShowContactCommand(lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .contactsShow,
                arguments: .contactsShow(query)
            ))
        }

        return nil
    }

    // MARK: - Find Contacts Parsing

    private func parseFindContactsCommand(lower: String) -> ContactQuery? {
        let findPrefixes = [
            "find contact ",
            "find my contact ",
            "find contact in my contacts ",
            "search contacts for ",
            "search my contacts for ",
            "look up contact in my contacts ",
            "look up "
        ]

        for prefix in findPrefixes {
            if lower.hasPrefix(prefix) {
                let query = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return ContactQuery(query: query)
                }
            }
        }
        return nil
    }

    // MARK: - Show Contact Parsing

    private func parseShowContactCommand(lower: String) -> ContactShowRequest? {
        let showPrefixes = [
            "show contact ",
            "show my contact ",
            "show me contact ",
            "show me "
        ]

        for prefix in showPrefixes {
            if lower.hasPrefix(prefix) {
                let query = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return ContactShowRequest(query: query)
                }
            }
        }
        return nil
    }
}