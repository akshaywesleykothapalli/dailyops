import Foundation

/// Executes validated WhatsApp commands via native deep link URLs.
@MainActor
struct WhatsAppCommandExecutor: CommandExecuting {
    private let control: WhatsAppControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [.whatsAppOpenChat, .whatsAppSendMessage]

    init(control: WhatsAppControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .whatsAppOpenChat:
            let target = try whatsAppChatArgument(from: intent)
            guard case .resolved(let contact) = target.recipient.resolution else {
                throw CommandExecutionError.operationFailed("Recipient for WhatsApp chat was not resolved.")
            }
            guard let url = WhatsAppURLBuilder.chatURL(for: contact.phoneNumber) else {
                throw CommandExecutionError.operationFailed("Could not construct WhatsApp chat URL.")
            }
            try control.open(url)
            return "Opened WhatsApp chat with \(contact.name)"

        case .whatsAppSendMessage:
            let target = try whatsAppMessageArgument(from: intent)
            guard case .resolved(let contact) = target.recipient.resolution else {
                throw CommandExecutionError.operationFailed("Recipient for WhatsApp message was not resolved.")
            }
            guard let url = WhatsAppURLBuilder.messageURL(for: contact.phoneNumber, message: target.message) else {
                throw CommandExecutionError.operationFailed("Could not construct WhatsApp message URL.")
            }
            try control.open(url)
            return "Prepared WhatsApp message for \(contact.name)"

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
