import Foundation
import Contacts
import os

/// Resolves a spoken person name or query into a WhatsApp-compatible contact.
@MainActor
protocol WhatsAppContactResolving: Sendable {
    func resolve(nameOrQuery: String) -> ContactResolutionResult
}

/// Resolves contacts using direct phone number detection and Apple's Contacts framework.
@MainActor
final class SystemWhatsAppContactResolver: WhatsAppContactResolving {
    private let contactStore: CNContactStore

    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }

    func resolve(nameOrQuery: String) -> ContactResolutionResult {
        let trimmed = nameOrQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .notFound(query: nameOrQuery)
        }

        // 1. Direct phone number check (e.g. "+14155552671", "9876543210")
        if isLikelyPhoneNumber(trimmed) {
            let digits = WhatsAppURLBuilder.normalizePhoneNumber(trimmed)
            if digits.count >= 7 {
                return .resolved(WhatsAppContact(name: trimmed, phoneNumber: digits))
            }
        }

        // 2. Check Contacts framework authorization
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .denied, .restricted:
            return .unavailable(reason: "Contacts access is denied. Allow DailyOps in System Settings > Privacy & Security > Contacts.")
        case .notDetermined:
            // Requesting access or checking if request was already initiated
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
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        let matchedContacts: [CNContact]
        do {
            matchedContacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        } catch {
            return .unavailable(reason: "Failed to query Contacts: \(error.localizedDescription)")
        }

        // 4. Filter contacts that possess at least one valid phone number
        struct Candidate {
            let contact: WhatsAppContact
            let given: String
            let family: String
            let nickname: String
            let fullName: String
            let organization: String
        }

        let candidates: [Candidate] = matchedContacts.compactMap { contact in
            guard let digits = Self.selectPreferredPhoneNumber(from: contact.phoneNumbers) else {
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

            let whatsAppContact = WhatsAppContact(name: fullName, phoneNumber: digits, identifier: contact.identifier)
            return Candidate(
                contact: whatsAppContact,
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

    private func isLikelyPhoneNumber(_ text: String) -> Bool {
        if text.hasPrefix("+") { return true }
        let digits = text.filter { $0.isNumber }
        let letters = text.filter { $0.isLetter }
        return letters.isEmpty && digits.count >= 7
    }

    /// Selects the best phone number for WhatsApp from a contact's phone list, prioritizing mobile numbers.
    static func selectPreferredPhoneNumber(from phoneNumbers: [CNLabeledValue<CNPhoneNumber>]) -> String? {
        guard !phoneNumbers.isEmpty else { return nil }

        // 1. Explicit CNLabelPhoneNumberMobile
        if let mobile = phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberMobile }) {
            let digits = WhatsAppURLBuilder.normalizePhoneNumber(mobile.value.stringValue)
            if !digits.isEmpty { return digits }
        }

        // 2. Explicit CNLabelPhoneNumberiPhone
        if let iphone = phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberiPhone }) {
            let digits = WhatsAppURLBuilder.normalizePhoneNumber(iphone.value.stringValue)
            if !digits.isEmpty { return digits }
        }

        // 3. Label containing "mobile" or "cell"
        if let labeledMobile = phoneNumbers.first(where: {
            guard let label = $0.label?.lowercased() else { return false }
            return label.contains("mobile") || label.contains("cell")
        }) {
            let digits = WhatsAppURLBuilder.normalizePhoneNumber(labeledMobile.value.stringValue)
            if !digits.isEmpty { return digits }
        }

        // 4. Fall back to first number with valid digits
        for phone in phoneNumbers {
            let digits = WhatsAppURLBuilder.normalizePhoneNumber(phone.value.stringValue)
            if !digits.isEmpty { return digits }
        }

        return nil
    }
}
