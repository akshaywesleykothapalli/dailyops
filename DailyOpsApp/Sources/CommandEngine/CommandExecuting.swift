import Foundation

/// Why an otherwise valid command failed at execution time.
enum CommandExecutionError: Error, Equatable {
    /// No executor claimed the identifier.
    case unsupported(CommandIdentifier)
    /// The executor was handed arguments it cannot use. Reaching this means
    /// validation and the registry disagree about a command's shape.
    case malformedArguments(CommandIdentifier)
    /// The underlying system operation did not succeed.
    case operationFailed(String)
}

/// Performs the side effect for a subset of commands. Executors are narrow on
/// purpose: application control, window navigation and pasteboard work have
/// nothing in common beyond being effects, and keeping them apart means a test
/// can substitute one without stubbing the others.
@MainActor
protocol CommandExecuting {
    /// Identifiers this executor handles. The router uses this to dispatch, so
    /// an executor can never be reached with a command it did not claim.
    var supportedIdentifiers: Set<CommandIdentifier> { get }

    /// Runs the intent and returns short user-facing feedback.
    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String
}

extension CommandExecuting {
    /// Unwraps an application argument or reports a shape mismatch, rather
    /// than force-unwrapping what validation is expected to have guaranteed.
    func applicationArgument(from intent: CommandIntent) throws -> ApplicationReference {
        guard case .application(let reference) = intent.arguments else {
            throw CommandExecutionError.malformedArguments(intent.identifier)
        }
        return reference
    }

    func writingModeArgument(from intent: CommandIntent) throws -> WritingMode {
        guard case .writingMode(let mode) = intent.arguments else {
            throw CommandExecutionError.malformedArguments(intent.identifier)
        }
        return mode
    }

    func urlArgument(from intent: CommandIntent) throws -> URL {
        guard case .url(let url) = intent.arguments else {
            throw CommandExecutionError.malformedArguments(intent.identifier)
        }
        return url
    }

    func searchArgument(from intent: CommandIntent) throws -> SearchRequest {
        guard case .search(let request) = intent.arguments else {
            throw CommandExecutionError.malformedArguments(intent.identifier)
        }
        return request
    }

    func whatsAppChatArgument(from intent: CommandIntent) throws -> WhatsAppChatTarget {
        guard case .whatsAppChat(let target) = intent.arguments else {
            throw CommandExecutionError.malformedArguments(intent.identifier)
        }
        return target
    }

    func whatsAppMessageArgument(from intent: CommandIntent) throws -> WhatsAppMessageTarget {
        guard case .whatsAppMessage(let target) = intent.arguments else {
            throw CommandExecutionError.malformedArguments(intent.identifier)
        }
        return target
    }
}
