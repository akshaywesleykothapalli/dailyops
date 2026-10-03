import Foundation

/// Parses WhatsApp-specific voice commands for chat opening and messaging.
@MainActor
struct WhatsAppCommandParser: CommandParsing {
    private let contactResolver: WhatsAppContactResolving

    init(contactResolver: WhatsAppContactResolving) {
        self.contactResolver = contactResolver
    }

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        guard context.isCommandModeEnabled else { return nil }
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !raw.isEmpty else { return nil }

        // "Open WhatsApp" must be handled by generic app.open, not here
        var lower = raw.lowercased()
        if lower.hasSuffix(" please") {
            lower = String(lower.dropLast(" please".count)).trimmingCharacters(in: .whitespaces)
        }
        if lower == "open whatsapp" || lower == "launch whatsapp" || lower == "start whatsapp" {
            return nil
        }

        // 1. Message preparation commands
        if let messagePlan = parseMessageCommand(raw: raw, lower: lower) {
            return messagePlan
        }

        // 2. Chat opening commands
        if let chatPlan = parseChatCommand(raw: raw, lower: lower) {
            return chatPlan
        }

        return nil
    }

    // MARK: - Message Command Parsing

    private func parseMessageCommand(raw: String, lower: String) -> CommandPlan? {
        // Supported delimiters connecting the recipient clause to the message body
        let delimiters = [" saying ", " that "]

        // Find all delimiter occurrences and try them in left-to-right order
        var candidates: [(delimiter: String, range: Range<String.Index>)] = []
        for delimiter in delimiters {
            var searchRange = lower.startIndex..<lower.endIndex
            while let range = lower.range(of: delimiter, range: searchRange) {
                candidates.append((delimiter, range))
                if range.upperBound < lower.endIndex {
                    searchRange = range.upperBound..<lower.endIndex
                } else {
                    break
                }
            }
        }

        // Sort by earliest appearance in the transcript
        candidates.sort { $0.range.lowerBound < $1.range.lowerBound }

        for candidate in candidates {
            let beforeSayingRaw = String(raw[..<candidate.range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let beforeSayingLower = String(lower[..<candidate.range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let message = String(raw[candidate.range.upperBound...]).trimmingCharacters(in: .whitespaces)

            guard !message.isEmpty else { continue }
            guard let recipientName = extractMessageRecipient(raw: beforeSayingRaw, lower: beforeSayingLower) else {
                continue
            }

            let resolution = contactResolver.resolve(nameOrQuery: recipientName)
            let recipient = WhatsAppRecipient(rawQuery: recipientName, resolution: resolution)
            let target = WhatsAppMessageTarget(recipient: recipient, message: message)

            return CommandPlan(intent: CommandIntent(
                identifier: .whatsAppSendMessage,
                arguments: .whatsAppMessage(target)
            ))
        }

        return nil
    }

    private func extractMessageRecipient(raw: String, lower: String) -> String? {
        // 1. "send a whatsapp message to <name>"
        if lower.hasPrefix("send a whatsapp message to ") {
            let name = String(raw.dropFirst("send a whatsapp message to ".count))
            return cleanName(name)
        }
        // 2. "send whatsapp message to <name>"
        if lower.hasPrefix("send whatsapp message to ") {
            let name = String(raw.dropFirst("send whatsapp message to ".count))
            return cleanName(name)
        }
        // 3. "send a message to <name> on whatsapp"
        if lower.hasPrefix("send a message to ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "send a message to ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 4. "send a message on whatsapp to <name>"
        if lower.hasPrefix("send a message on whatsapp to ") {
            let name = String(raw.dropFirst("send a message on whatsapp to ".count))
            return cleanName(name)
        }
        // 5. "send message to <name> on whatsapp"
        if lower.hasPrefix("send message to ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "send message to ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 6. "send a message to <name>"
        if lower.hasPrefix("send a message to ") {
            let name = String(raw.dropFirst("send a message to ".count))
            return cleanName(name)
        }
        // 7. "send message to <name>"
        if lower.hasPrefix("send message to ") {
            let name = String(raw.dropFirst("send message to ".count))
            return cleanName(name)
        }
        // 8. "send <name> a whatsapp message"
        if lower.hasPrefix("send ") && lower.hasSuffix(" a whatsapp message") {
            let prefixCount = "send ".count
            let suffixCount = " a whatsapp message".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 9. "send <name> a message on whatsapp"
        if lower.hasPrefix("send ") && lower.hasSuffix(" a message on whatsapp") {
            let prefixCount = "send ".count
            let suffixCount = " a message on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 10. "send <name> a message"
        if lower.hasPrefix("send ") && lower.hasSuffix(" a message") {
            let prefixCount = "send ".count
            let suffixCount = " a message".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 11. "text <name> on whatsapp"
        if lower.hasPrefix("text ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "text ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 12. "text <name> a whatsapp message"
        if lower.hasPrefix("text ") && lower.hasSuffix(" a whatsapp message") {
            let prefixCount = "text ".count
            let suffixCount = " a whatsapp message".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 13. "text <name> a message on whatsapp"
        if lower.hasPrefix("text ") && lower.hasSuffix(" a message on whatsapp") {
            let prefixCount = "text ".count
            let suffixCount = " a message on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 14. "text <name>"
        if lower.hasPrefix("text ") {
            let name = String(raw.dropFirst("text ".count))
            return cleanName(name)
        }
        // 15. "message <name> on whatsapp"
        if lower.hasPrefix("message ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "message ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // 16. "message <name>"
        if lower.hasPrefix("message ") {
            let name = String(raw.dropFirst("message ".count))
            return cleanName(name)
        }
        // 17. "whatsapp <name>"
        if lower.hasPrefix("whatsapp ") {
            let name = String(raw.dropFirst("whatsapp ".count))
            return cleanName(name)
        }

        return nil
    }

    // MARK: - Chat Opening Parsing

    private func parseChatCommand(raw: String, lower: String) -> CommandPlan? {
        guard let recipientName = extractChatRecipient(raw: raw, lower: lower) else {
            return nil
        }

        let resolution = contactResolver.resolve(nameOrQuery: recipientName)
        let recipient = WhatsAppRecipient(rawQuery: recipientName, resolution: resolution)
        let target = WhatsAppChatTarget(recipient: recipient)

        return CommandPlan(intent: CommandIntent(
            identifier: .whatsAppOpenChat,
            arguments: .whatsAppChat(target)
        ))
    }

    private func extractChatRecipient(raw: String, lower: String) -> String? {
        // "open <name>'s whatsapp chat"
        if lower.hasPrefix("open ") && lower.hasSuffix("'s whatsapp chat") {
            let prefixCount = "open ".count
            let suffixCount = "'s whatsapp chat".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // "open <name>'s chat on whatsapp"
        if lower.hasPrefix("open ") && lower.hasSuffix("'s chat on whatsapp") {
            let prefixCount = "open ".count
            let suffixCount = "'s chat on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // "open <name>'s chat" (e.g. "open John's chat")
        if lower.hasPrefix("open ") && lower.hasSuffix("'s chat") {
            let prefixCount = "open ".count
            let suffixCount = "'s chat".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // "open my whatsapp chat with <name>"
        if lower.hasPrefix("open my whatsapp chat with ") {
            let name = String(raw.dropFirst("open my whatsapp chat with ".count))
            return cleanName(name)
        }
        // "open my chat with <name> on whatsapp"
        if lower.hasPrefix("open my chat with ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "open my chat with ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // "open my chat with <name>"
        if lower.hasPrefix("open my chat with ") {
            let name = String(raw.dropFirst("open my chat with ".count))
            return cleanName(name)
        }
        // "open whatsapp chat with <name>"
        if lower.hasPrefix("open whatsapp chat with ") {
            let name = String(raw.dropFirst("open whatsapp chat with ".count))
            return cleanName(name)
        }
        // "open whatsapp chat for <name>"
        if lower.hasPrefix("open whatsapp chat for ") {
            let name = String(raw.dropFirst("open whatsapp chat for ".count))
            return cleanName(name)
        }
        // "open chat with <name> on whatsapp"
        if lower.hasPrefix("open chat with ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "open chat with ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // "open chat with <name>"
        if lower.hasPrefix("open chat with ") {
            var name = String(raw.dropFirst("open chat with ".count))
            if lower.hasSuffix(" on whatsapp") {
                name = String(name.dropLast(" on whatsapp".count))
            }
            return cleanName(name)
        }
        // "open chat for <name> on whatsapp"
        if lower.hasPrefix("open chat for ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "open chat for ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            return cleanName(name)
        }
        // "open chat for <name>"
        if lower.hasPrefix("open chat for ") {
            let name = String(raw.dropFirst("open chat for ".count))
            return cleanName(name)
        }
        // "open <name> on whatsapp" (e.g. "open John on WhatsApp")
        if lower.hasPrefix("open ") && lower.hasSuffix(" on whatsapp") {
            let prefixCount = "open ".count
            let suffixCount = " on whatsapp".count
            guard raw.count > prefixCount + suffixCount else { return nil }
            let name = String(raw.dropFirst(prefixCount).dropLast(suffixCount))
            let cleaned = cleanName(name)
            if cleaned != nil && cleaned?.lowercased() != "whatsapp" && cleaned?.lowercased() != "chat" {
                return cleaned
            }
        }

        return nil
    }

    private func cleanName(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.'\""))
        guard !cleaned.isEmpty else { return nil }

        // A recipient name cannot contain sequence conjunctions, clause separators, or command prefixes
        let lower = cleaned.lowercased()
        if lower.contains(",") ||
           lower.contains(" and ") ||
           lower.contains(" then ") ||
           lower.contains(" after that ") ||
           lower.hasPrefix("open ") ||
           lower.hasPrefix("launch ") ||
           lower.hasPrefix("start ") ||
           lower.hasPrefix("whatsapp and ") {
            return nil
        }

        return cleaned
    }
}
