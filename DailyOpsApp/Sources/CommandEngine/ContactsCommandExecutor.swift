import Contacts
import Foundation
import os

/// Summary of a contact for display to the user.
struct ContactSummary: Equatable, Sendable {
    let displayName: String
    let phoneNumbers: [String]
    let emailAddresses: [String]
}

/// Abstract interface for Contacts operations.
@MainActor
protocol ContactsControlling: Sendable {
    func findContacts(_ query: ContactQuery) throws -> [ContactSummary]
    func showContact(_ query: ContactShowRequest) throws -> [ContactSummary]
}

/// Concrete Contacts controller using CNContactStore.
@MainActor
final class SystemContactsControl: ContactsControlling {
    private let contactStore = CNContactStore()
    private let whatsAppResolver: WhatsAppContactResolving

    init(whatsAppResolver: WhatsAppContactResolving = SystemWhatsAppContactResolver()) {
        self.whatsAppResolver = whatsAppResolver
    }

    func findContacts(_ query: ContactQuery) throws -> [ContactSummary] {
        try ensureContactsAccess()

        let predicate = CNContact.predicateForContacts(matchingName: query.query)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let matchedContacts: [CNContact]
        do {
            matchedContacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        } catch {
            throw CommandExecutionError.operationFailed("Failed to query Contacts: \(error.localizedDescription)")
        }

        let summaries = matchedContacts.compactMap { contact -> ContactSummary? in
            let displayName = formatDisplayName(from: contact)
            let phoneNumbers = contact.phoneNumbers.map { WhatsAppURLBuilder.normalizePhoneNumber($0.value.stringValue) }.filter { !$0.isEmpty }
            let emailAddresses = contact.emailAddresses.map { $0.value as String }

            return ContactSummary(displayName: displayName, phoneNumbers: phoneNumbers, emailAddresses: emailAddresses)
        }

        return summaries
    }

    func showContact(_ query: ContactShowRequest) throws -> [ContactSummary] {
        // Reuse the find contacts logic - show is essentially the same as find for now
        return try findContacts(ContactQuery(query: query.query))
    }

    private func formatDisplayName(from contact: CNContact) -> String {
        let given = contact.givenName.trimmingCharacters(in: .whitespaces)
        let middle = contact.middleName.trimmingCharacters(in: .whitespaces)
        let family = contact.familyName.trimmingCharacters(in: .whitespaces)

        var components: [String] = []
        if !given.isEmpty { components.append(given) }
        if !middle.isEmpty { components.append(middle) }
        if !family.isEmpty { components.append(family) }
        if components.isEmpty {
            return contact.organizationName.isEmpty ? "Unknown" : contact.organizationName
        }
        return components.joined(separator: " ")
    }

    private func ensureContactsAccess() throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw CommandExecutionError.operationFailed("Contacts access is denied. Allow DailyOps in System Settings > Privacy & Security > Contacts.")
        case .notDetermined:
            let accessGranted = OSAllocatedUnfairLock(initialState: false)
            let semaphore = DispatchSemaphore(value: 0)
            contactStore.requestAccess(for: .contacts) { isGranted, _ in
                accessGranted.withLock { $0 = isGranted }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2.0)
            guard accessGranted.withLock({ $0 }) else {
                throw CommandExecutionError.operationFailed("Contacts access was not granted.")
            }
        @unknown default:
            throw CommandExecutionError.operationFailed("Contacts access is unavailable.")
        }
    }
}

/// Fake Contacts controller for unit testing.
@MainActor
final class FakeContactsControl: ContactsControlling {
    var contactsToReturn: [ContactSummary] = []
    var shouldFailWithAccessDenied: Bool = false

    func findContacts(_ query: ContactQuery) throws -> [ContactSummary] {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Contacts access is denied. Allow DailyOps in System Settings > Privacy & Security > Contacts.")
        }
        return contactsToReturn
    }

    func showContact(_ query: ContactShowRequest) throws -> [ContactSummary] {
        if shouldFailWithAccessDenied {
            throw CommandExecutionError.operationFailed("Contacts access is denied. Allow DailyOps in System Settings > Privacy & Security > Contacts.")
        }
        return contactsToReturn
    }
}

/// Executes Contacts commands.
@MainActor
struct ContactsCommandExecutor: CommandExecuting {
    private let control: ContactsControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .contactsFind,
        .contactsShow
    ]

    init(control: ContactsControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .contactsFind:
            guard case .contactsQuery(let query) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let contacts = try control.findContacts(query)
            return formatContactsResult(query: query.query, contacts: contacts)

        case .contactsShow:
            guard case .contactsShow(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            let contacts = try control.showContact(request)
            return formatContactsResult(query: request.query, contacts: contacts)

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }

    private func formatContactsResult(query: String, contacts: [ContactSummary]) -> String {
        if contacts.isEmpty {
            return "No contact found matching \"\(query)\"."
        }

        if contacts.count == 1 {
            let contact = contacts[0]
            var details = contact.displayName
            if !contact.phoneNumbers.isEmpty {
                details += " — \(contact.phoneNumbers.joined(separator: ", "))"
            }
            if !contact.emailAddresses.isEmpty {
                details += " — \(contact.emailAddresses.joined(separator: ", "))"
            }
            return "Found contact: \(details)."
        }

        // Multiple matches - return ambiguity
        let names = contacts.prefix(5).map { $0.displayName }.joined(separator: ", ")
        return "Multiple contacts match \"\(query)\" (\(names)). Please be more specific."
    }
}