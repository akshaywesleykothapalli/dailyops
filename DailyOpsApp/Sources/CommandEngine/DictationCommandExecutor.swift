import Foundation

/// Commands that act on the dictation session itself: the pasteboard, the
/// writing mode and the speech model.
@MainActor
struct DictationCommandExecutor: CommandExecuting {
    private let host: CommandHosting

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .clipboardCopyLast,
        .clipboardClear,
        .dictationModeFormal,
        .dictationModeStandard,
        .speechModelReload,
    ]

    init(host: CommandHosting) {
        self.host = host
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .clipboardCopyLast:
            host.copyLastDictation()
            return "Copied Last Dictation"
        case .clipboardClear:
            host.clearClipboard()
            return "Cleared Clipboard"
        case .dictationModeFormal, .dictationModeStandard:
            let mode = try writingModeArgument(from: intent)
            host.setWritingMode(mode)
            return "Switched to \(mode.label) Mode"
        case .speechModelReload:
            host.reloadSpeechModel()
            return "Reloading Speech Model"
        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}
