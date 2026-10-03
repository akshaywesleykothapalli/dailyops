import Foundation

/// Launches, quits and hides applications. The actual system calls live behind
/// `ApplicationControlling`, so this type only decides which operation an
/// identifier maps to and what the user is told afterwards.
@MainActor
struct ApplicationCommandExecutor: CommandExecuting {
    private let control: ApplicationControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [.appOpen, .appQuit, .appHide, .appSwitch]

    init(control: ApplicationControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        let reference = try applicationArgument(from: intent)
        let name = reference.displayName.capitalized

        switch intent.identifier {
        case .appOpen:
            try control.launch(reference)
            return "Opened \(name)"
        case .appSwitch:
            try control.activate(reference)
            return "Switched to \(name)"
        case .appQuit:
            try control.quit(reference)
            return "Quit \(name)"
        case .appHide:
            try control.hide(reference)
            return "Hidden \(name)"
        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
