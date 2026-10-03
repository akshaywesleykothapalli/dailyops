import AppKit
import Foundation

/// Summary of a mail compose operation result.
struct MailComposeResult: Equatable, Sendable {
    let success: Bool
    let message: String
}

/// Abstract interface for Mail operations.
@MainActor
protocol MailControlling: Sendable {
    func openMail() throws -> String
    func composeEmail(_ request: MailComposeRequest) throws -> String
}

/// Concrete Mail controller using NSWorkspace and mailto URL scheme.
@MainActor
final class SystemMailControl: MailControlling {
    func openMail() throws -> String {
        // Open the default mail client
        if let mailURL = URL(string: "mailto:") {
            let success = NSWorkspace.shared.open(mailURL)
            if success {
                return "Opened Mail"
            } else {
                throw CommandExecutionError.operationFailed("Could not open Mail app.")
            }
        } else {
            throw CommandExecutionError.operationFailed("Could not construct mailto URL.")
        }
    }

    func composeEmail(_ request: MailComposeRequest) throws -> String {
        var components = URLComponents()
        components.scheme = "mailto"
        
        // Properly encode the email address for the mailto path
        if let to = request.to, !to.isEmpty {
            // Check if it's a valid email address; if so, use it directly in the path
            // Otherwise, it might be a name that the mail client will resolve
            if isLikelyEmailAddress(to) {
                components.path = to
            } else {
                // For names, mailto: expects the path to be empty and the "to" in query
                // But mailto: doesn't support name resolution in the path
                // We'll put it in the "to" query parameter instead
                components.path = ""
            }
        } else {
            components.path = ""
        }

        var queryItems: [URLQueryItem] = []

        // Add "to" as a query parameter if it's not a valid email (name resolution by mail client)
        // Or if we want to be safe, always include it in query
        if let to = request.to, !to.isEmpty {
            queryItems.append(URLQueryItem(name: "to", value: to))
        }

        if let subject = request.subject, !subject.isEmpty {
            queryItems.append(URLQueryItem(name: "subject", value: subject))
        }

        if let body = request.body, !body.isEmpty {
            queryItems.append(URLQueryItem(name: "body", value: body))
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw CommandExecutionError.operationFailed("Could not construct mailto URL.")
        }

        let success = NSWorkspace.shared.open(url)
        if success {
            let to = request.to ?? "new recipient"
            return "Opened a new email draft to \(to) in your default mail app."
        } else {
            throw CommandExecutionError.operationFailed("Could not open mail compose window.")
        }
    }

    private func isLikelyEmailAddress(_ text: String) -> Bool {
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: text)
    }
}

/// Fake Mail controller for unit testing.
@MainActor
final class FakeMailControl: MailControlling {
    var openedMail: Bool = false
    var composedEmails: [MailComposeRequest] = []
    var shouldFail: Bool = false

    func openMail() throws -> String {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Could not open Mail app.")
        }
        openedMail = true
        return "Opened Mail"
    }

    func composeEmail(_ request: MailComposeRequest) throws -> String {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Could not compose email.")
        }
        composedEmails.append(request)
        let to = request.to ?? "new recipient"
        return "Opened a new email draft to \(to) in your default mail app."
    }
}

/// Executes Mail commands.
@MainActor
struct MailCommandExecutor: CommandExecuting {
    private let control: MailControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .mailOpen,
        .mailCompose
    ]

    init(control: MailControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .mailOpen:
            return try control.openMail()

        case .mailCompose:
            guard case .mailCompose(let request) = intent.arguments else {
                throw CommandExecutionError.unsupported(intent.identifier)
            }
            return try control.composeEmail(request)

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}