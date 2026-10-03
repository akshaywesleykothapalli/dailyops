import Foundation
import Contacts
import os

/// Resolves a spoken person name or query into an email-compatible contact.
@MainActor
protocol EmailContactResolving: Sendable {
    func resolve(nameOrQuery: String) -> EmailContactResolutionResult
}

/// A resolved contact suitable for email communication.
struct EmailContact: Equatable, Codable, Sendable {
    let name: String
    let emailAddress: String
    let identifier: String?

    init(name: String, emailAddress: String, identifier: String? = nil) {
        self.name = name
        self.emailAddress = emailAddress
        self.identifier = identifier
    }
}

/// The result of attempting to resolve a recipient name or query for email.
enum EmailContactResolutionResult: Equatable, Codable, Sendable {
    case unresolved
    case resolved(EmailContact)
    case ambiguous([EmailContact])
    case notFound(query: String)
    case unavailable(reason: String)
    case noEmailAddress(name: String)
}

/// A recipient for an email command, capturing both the original spoken query
/// and the result of contact resolution.
struct EmailRecipient: Equatable, Codable, Sendable {
    let rawQuery: String
    let resolution: EmailContactResolutionResult

    init(rawQuery: String, resolution: EmailContactResolutionResult = .unresolved) {
        self.rawQuery = rawQuery
        self.resolution = resolution
    }

    var displayName: String {
        switch resolution {
        case .resolved(let contact):
            return "\(contact.name) <\(contact.emailAddress)>"
        case .ambiguous, .notFound, .unavailable, .noEmailAddress, .unresolved:
            return rawQuery
        }
    }

    var contactName: String {
        switch resolution {
        case .resolved(let contact):
            return contact.name
        case .ambiguous, .notFound, .unavailable, .noEmailAddress, .unresolved:
            return rawQuery
        }
    }

    var resolvedContact: EmailContact? {
        if case .resolved(let contact) = resolution {
            return contact
        }
        return nil
    }
}

/// Concrete Email Contact resolver using Apple's Contacts framework.
@MainActor
final class SystemEmailContactResolver: EmailContactResolving {
    private let contactStore: CNContactStore

    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }

    func resolve(nameOrQuery: String) -> EmailContactResolutionResult {
        let trimmed = nameOrQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .notFound(query: nameOrQuery)
        }

        // 1. Direct email address check
        if isLikelyEmailAddress(trimmed) {
            return .resolved(EmailContact(name: trimmed, emailAddress: trimmed))
        }

        // 2. Check Contacts framework authorization
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .denied, .restricted:
            return .unavailable(reason: "Contacts access is denied. Allow DailyOps in System Settings > Privacy & Security > Contacts.")
        case .notDetermined:
            let granted = OSAllocatedUnfairLock(initialState: false)
            let semaphore = DispatchSemaphore(value: 0)
            contactStore.requestAccess(for: .contacts) { isGranted, _ in
                granted.withLock { $0 = isGranted }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2.0)
            guard granted.withLock({ $0 }) else {
                return .unavailable(reason: "Contacts access was not granted.")
            }
        case .authorized:
            break
        @unknown default:
            break
        }

        // 3. Query Contacts matching the given name
        let predicate = CNContact.predicateForContacts(matchingName: trimmed)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        let matchedContacts: [CNContact]
        do {
            matchedContacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        } catch {
            return .unavailable(reason: "Failed to query Contacts: \(error.localizedDescription)")
        }

        // 4. Filter contacts that possess at least one valid email address
        struct Candidate {
            let contact: EmailContact
            let given: String
            let family: String
            let nickname: String
            let fullName: String
            let organization: String
        }

        let candidates: [Candidate] = matchedContacts.compactMap { contact in
            guard let email = Self.selectPreferredEmailAddress(from: contact.emailAddresses) else {
                return nil
            }

            let given = contact.givenName.trimmingCharacters(in: .whitespaces)
            let family = contact.familyName.trimmingCharacters(in: .whitespaces)
            let nickname = contact.nickname.trimmingCharacters(in: .whitespaces)
            let organization = contact.organizationName.trimmingCharacters(in: .whitespaces)

            let fullName: String
            if !given.isEmpty && !family.isEmpty {
                fullName = "\(given) \(family)"
            } else if !given.isEmpty {
                fullName = given
            } else if !family.isEmpty {
                fullName = family
            } else if !organization.isEmpty {
                fullName = organization
            } else if !nickname.isEmpty {
                fullName = nickname
            } else {
                fullName = trimmed
            }

            let emailContact = EmailContact(name: fullName, emailAddress: email, identifier: contact.identifier)
            return Candidate(
                contact: emailContact,
                given: given,
                family: family,
                nickname: nickname,
                fullName: fullName,
                organization: organization
            )
        }

        guard !candidates.isEmpty else {
            return .notFound(query: trimmed)
        }

        let q = trimmed.lowercased()

        // Tier 1: Exact full-name, exact nickname, or exact organization match
        let tier1 = candidates.filter {
            $0.fullName.lowercased() == q ||
            $0.nickname.lowercased() == q ||
            $0.organization.lowercased() == q
        }
        if !tier1.isEmpty {
            return tier1.count == 1 ? .resolved(tier1[0].contact) : .ambiguous(tier1.map(\.contact))
        }

        // Tier 2: Exact given name or exact family name match
        let tier2 = candidates.filter {
            $0.given.lowercased() == q ||
            $0.family.lowercased() == q
        }
        if !tier2.isEmpty {
            return tier2.count == 1 ? .resolved(tier2[0].contact) : .ambiguous(tier2.map(\.contact))
        }

        // Tier 3: Word-component match in full name (e.g. query matches one of the whitespace-delimited tokens)
        let tier3 = candidates.filter {
            let tokens = $0.fullName.lowercased().split(separator: " ").map(String.init)
            return tokens.contains(q)
        }
        if !tier3.isEmpty {
            return tier3.count == 1 ? .resolved(tier3[0].contact) : .ambiguous(tier3.map(\.contact))
        }

        // Avoid dangerous fuzzy matching that could silently select the wrong person
        return .notFound(query: trimmed)
    }

    private func isLikelyEmailAddress(_ text: String) -> Bool {
        // Simple email validation regex
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: text)
    }

    /// Selects the best email address for email from a contact's email list, prioritizing work/personal labels.
    static func selectPreferredEmailAddress(from emailAddresses: [CNLabeledValue<NSString>]) -> String? {
        guard !emailAddresses.isEmpty else { return nil }

        // 1. Explicit CNLabelHome or CNLabelWork (these are the public labels for email)
        let preferredLabels = [CNLabelHome, CNLabelWork, CNLabelEmailiCloud]
        for label in preferredLabels {
            if let email = emailAddresses.first(where: { $0.label == label }) {
                let emailStr = email.value as String
                if isValidEmail(emailStr) { return emailStr }
            }
        }

        // 2. Label containing "work" or "personal" or "home"
        if let labeled = emailAddresses.first(where: {
            guard let label = $0.label?.lowercased() else { return false }
            return label.contains("work") || label.contains("personal") || label.contains("home")
        }) {
            let emailStr = labeled.value as String
            if isValidEmail(emailStr) { return emailStr }
        }

        // 3. Fall back to first valid email
        for email in emailAddresses {
            let emailStr = email.value as String
            if isValidEmail(emailStr) { return emailStr }
        }

        return nil
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
}

/// Fake Email Contact resolver for unit testing.
@MainActor
final class FakeEmailContactResolver: EmailContactResolving {
    var responses: [String: EmailContactResolutionResult]
    private(set) var queriedNames: [String] = []

    init(responses: [String: EmailContactResolutionResult] = [:]) {
        self.responses = responses
    }

    func resolve(nameOrQuery: String) -> EmailContactResolutionResult {
        queriedNames.append(nameOrQuery)
        let lower = nameOrQuery.lowercased()
        if let direct = responses[nameOrQuery] { return direct }
        if let lowerMatch = responses.first(where: { $0.key.lowercased() == lower })?.value {
            return lowerMatch
        }
        return .notFound(query: nameOrQuery)
    }

    func reset() {
        queriedNames.removeAll()
    }
}