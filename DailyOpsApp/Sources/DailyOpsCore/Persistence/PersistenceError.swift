import Foundation

/// Errors that can occur during agent session persistence operations.
public enum PersistenceError: Error, Sendable, Equatable, LocalizedError {
    case fileNotFound(String)
    case unsupportedSchemaVersion(Int)
    case corruptedData(reason: String)
    case writeFailed(reason: String)
    case invalidSessionID(String)
    case directoryCreationFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Persistence file not found: \(path)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported persistence schema version: \(version)"
        case .corruptedData(let reason):
            return "Corrupted session data: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write session file: \(reason)"
        case .invalidSessionID(let id):
            return "Invalid session ID format: \(id)"
        case .directoryCreationFailed(let reason):
            return "Failed to create persistence directory: \(reason)"
        }
    }
}
