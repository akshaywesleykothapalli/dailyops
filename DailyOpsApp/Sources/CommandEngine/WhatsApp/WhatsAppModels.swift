import Foundation

/// A resolved contact suitable for WhatsApp communication.
struct WhatsAppContact: Equatable, Codable, Sendable {
    let name: String
    /// Normalized E.164 phone number digits (e.g. "14155552671" or "919876543210").
    let phoneNumber: String
    let identifier: String?

    init(name: String, phoneNumber: String, identifier: String? = nil) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.identifier = identifier
    }
}

/// The result of attempting to resolve a recipient name or query for WhatsApp.
enum ContactResolutionResult: Equatable, Codable, Sendable {
    /// Extracted recipient waiting for local resolution against macOS Contacts.
    case unresolved
    /// Exactly one unambiguous contact was found.
    case resolved(WhatsAppContact)
    /// Multiple contacts matched the query. Contains all matches so user can clarify.
    case ambiguous([WhatsAppContact])
    /// No matching contact was found for the given query.
    case notFound(query: String)
    /// Contact resolution could not be performed (e.g. permissions denied, no phone number on contact).
    case unavailable(reason: String)
}

/// A recipient for a WhatsApp command, capturing both the original spoken query
/// and the result of contact resolution.
struct WhatsAppRecipient: Equatable, Codable, Sendable {
    let rawQuery: String
    let resolution: ContactResolutionResult

    init(rawQuery: String, resolution: ContactResolutionResult = .unresolved) {
        self.rawQuery = rawQuery
        self.resolution = resolution
    }

    var displayName: String {
        switch resolution {
        case .resolved(let contact):
            return "\(contact.name) (+\(contact.phoneNumber))"
        case .ambiguous, .notFound, .unavailable, .unresolved:
            return rawQuery
        }
    }

    var contactName: String {
        switch resolution {
        case .resolved(let contact):
            return contact.name
        case .ambiguous, .notFound, .unavailable, .unresolved:
            return rawQuery
        }
    }

    var resolvedContact: WhatsAppContact? {
        if case .resolved(let contact) = resolution {
            return contact
        }
        return nil
    }
}

/// Target payload for opening a WhatsApp conversation.
struct WhatsAppChatTarget: Equatable, Codable, Sendable {
    let recipient: WhatsAppRecipient

    init(recipient: WhatsAppRecipient) {
        self.recipient = recipient
    }
}

/// Target payload for preparing/sending a WhatsApp message.
struct WhatsAppMessageTarget: Equatable, Codable, Sendable {
    let recipient: WhatsAppRecipient
    let message: String

    init(recipient: WhatsAppRecipient, message: String) {
        self.recipient = recipient
        self.message = message
    }
}

/// Constructs native WhatsApp deep link URLs (`whatsapp://send...`).
enum WhatsAppURLBuilder {
    /// Strips non-digit characters from a phone number, preserving international country code digits.
    static func normalizePhoneNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep only digits
        return trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    /// Constructs a URL to open a chat with a specific phone number.
    static func chatURL(for phoneNumber: String) -> URL? {
        let digits = normalizePhoneNumber(phoneNumber)
        guard !digits.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [
            URLQueryItem(name: "phone", value: digits)
        ]
        return components.url
    }

    /// Constructs a URL to open a chat with a specific phone number and pre-fill a message.
    static func messageURL(for phoneNumber: String, message: String) -> URL? {
        let digits = normalizePhoneNumber(phoneNumber)
        guard !digits.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [
            URLQueryItem(name: "phone", value: digits),
            URLQueryItem(name: "text", value: message)
        ]
        if let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") {
            components.percentEncodedQuery = encoded
        }
        return components.url
    }
}
