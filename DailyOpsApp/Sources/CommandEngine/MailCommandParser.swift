import Foundation

/// Parses Mail voice commands into structured CommandPlans.
@MainActor
struct MailCommandParser: CommandParsing {
    private let contactResolver: WhatsAppContactResolving?
    private let emailResolver: EmailContactResolving?

    init(contactResolver: WhatsAppContactResolving? = nil, emailResolver: EmailContactResolving? = nil) {
        self.contactResolver = contactResolver
        self.emailResolver = emailResolver
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

        // 1. Open Mail
        if isOpenMailCommand(lower) {
            return CommandPlan(intent: CommandIntent(identifier: .mailOpen))
        }

        // 2. Compose Email
        if let request = parseComposeEmailCommand(raw: raw, lower: lower) {
            return CommandPlan(intent: CommandIntent(
                identifier: .mailCompose,
                arguments: .mailCompose(request)
            ))
        }

        return nil
    }

    // MARK: - Open Mail

    private func isOpenMailCommand(_ lower: String) -> Bool {
        let openPhrases = [
            "open mail", "launch mail", "start mail", "open my mail", "show mail"
        ]
        return openPhrases.contains(lower)
    }

    // MARK: - Compose Email

    private func parseComposeEmailCommand(raw: String, lower: String) -> MailComposeRequest? {
        // "compose an email" / "write an email" / "compose email" / "write email"
        // These should open a blank compose window
        if lower == "compose an email" || lower == "write an email" || lower == "compose email" || lower == "write email" {
            return MailComposeRequest(to: nil, subject: nil, body: nil)
        }

        // Helper to resolve a name to an email address
        func resolveRecipient(_ name: String) -> String? {
            // First check if it's already an email address
            if isLikelyEmailAddress(name) {
                return name
            }
            // Try to resolve through contacts
            if let resolver = emailResolver {
                let result = resolver.resolve(nameOrQuery: name)
                switch result {
                case .resolved(let contact):
                    return contact.emailAddress
                case .unresolved, .notFound, .noEmailAddress, .unavailable, .ambiguous:
                    // Return the original name; the mailto URL will use it as-is
                    // The mail client will handle it or show an error
                    return nil
                }
            }
            return nil
        }

        // "compose an email to <name> saying <body>"
        // "compose an email to <name> that <body>"
        // "compose an email to <name> with subject <subject>"
        // "write an email to <name> saying <body>"
        // "write an email to <name> that <body>"
        // "write an email to <name> with subject <subject>"
        // "email <name> saying <body>"
        // "email <name> that <body>"
        // "email <name> with subject <subject>"
        // "send an email to <name> saying <body>"
        // "send an email to <name> that <body>"
        // "send an email to <name> with subject <subject>"
        // "send email to <name> saying <body>"
        // "send email to <name> that <body>"
        // "send email to <name> with subject <subject>"
        let compoundPrefixes = [
            "compose an email to ",
            "write an email to ",
            "compose email to ",
            "write email to ",
            "email ",
            "send an email to ",
            "send email to "
        ]
        for prefix in compoundPrefixes {
            if lower.hasPrefix(prefix) {
                let remaining = String(raw.dropFirst(prefix.count))
                // Check for " with subject " first (most specific)
                if let range = remaining.lowercased().range(of: " with subject ") {
                    let name = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let subject = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        let email = resolveRecipient(name) ?? name
                        return MailComposeRequest(to: email, subject: subject.isEmpty ? nil : subject, body: nil)
                    }
                }
                // Check for " saying " / " that "
                for delimiter in [" saying ", " that "] {
                    if let range = remaining.lowercased().range(of: delimiter) {
                        let name = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let body = String(remaining[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            let email = resolveRecipient(name) ?? name
                            return MailComposeRequest(to: email, subject: nil, body: body.isEmpty ? nil : body)
                        }
                    }
                }
                // If no delimiter found, just treat the rest as name
                let name = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let email = resolveRecipient(name) ?? name
                    return MailComposeRequest(to: email, subject: nil, body: nil)
                }
            }
        }

        // "compose an email to <name>"
        if lower.hasPrefix("compose an email to ") {
            let name = String(raw.dropFirst("compose an email to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        // "compose email to <name>"
        if lower.hasPrefix("compose email to ") {
            let name = String(raw.dropFirst("compose email to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        // "write an email to <name>"
        if lower.hasPrefix("write an email to ") {
            let name = String(raw.dropFirst("write an email to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        // "write email to <name>"
        if lower.hasPrefix("write email to ") {
            let name = String(raw.dropFirst("write email to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        // "email <name>" - this could be ambiguous with WhatsApp "message" commands
        // Only treat as email if it's NOT a WhatsApp command
        // The WhatsApp parser handles "message <name>" and "text <name>" etc.
        // "email <name>" is specifically for email
        if lower.hasPrefix("email ") {
            let name = String(raw.dropFirst("email ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        // "send an email to <name>"
        if lower.hasPrefix("send an email to ") {
            let name = String(raw.dropFirst("send an email to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        // "send email to <name>"
        if lower.hasPrefix("send email to ") {
            let name = String(raw.dropFirst("send email to ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let email = resolveRecipient(name) ?? name
                return MailComposeRequest(to: email, subject: nil, body: nil)
            }
        }

        return nil
    }

    private func isLikelyEmailAddress(_ text: String) -> Bool {
        // Simple email validation regex
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: text)
    }
}