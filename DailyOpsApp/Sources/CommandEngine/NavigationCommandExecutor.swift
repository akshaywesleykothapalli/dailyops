import Foundation

/// Opens the app's own windows. Separate from application control because
/// showing a pane is not the same kind of operation as launching a process, and
/// a test for one should not have to stub the other.
@MainActor
struct NavigationCommandExecutor: CommandExecuting {
    private let host: CommandHosting

    let supportedIdentifiers: Set<CommandIdentifier> = [.settingsOpen, .historyOpen]

    init(host: CommandHosting) {
        self.host = host
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .settingsOpen:
            host.showSettings()
            return "Opened Settings"
        case .historyOpen:
            host.showHistory()
            return "Opened History"
        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
