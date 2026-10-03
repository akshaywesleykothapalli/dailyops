import Foundation

/// Abstract interface for system power/session operations.
@MainActor
protocol SystemPowerControlling: Sendable {
    func sleep() throws
    func lock() throws
    func logout() throws
    func restart() throws
    func shutdown() throws
}

/// Concrete System Power controller using native macOS APIs.
/// NOTE: The previously assumed NSWorkspace performSleep/performLogout/performRestart/performPowerOff
/// methods do not exist in the current SDK. All five power operations are explicitly unsupported
/// through the currently permitted public macOS APIs.
@MainActor
final class SystemPowerControl: SystemPowerControlling {
    func sleep() throws {
        throw CommandExecutionError.operationFailed(
            "Sleep is not available through the currently permitted public macOS APIs."
        )
    }

    func lock() throws {
        throw CommandExecutionError.operationFailed(
            "Screen locking is not available through the currently permitted public macOS APIs."
        )
    }

    func logout() throws {
        throw CommandExecutionError.operationFailed(
            "Log out is not available through the currently permitted public macOS APIs."
        )
    }

    func restart() throws {
        throw CommandExecutionError.operationFailed(
            "Restart is not available through the currently permitted public macOS APIs."
        )
    }

    func shutdown() throws {
        throw CommandExecutionError.operationFailed(
            "Shut down is not available through the currently permitted public macOS APIs."
        )
    }
}

/// Fake System Power controller for unit testing.
@MainActor
final class FakeSystemPowerControl: SystemPowerControlling {
    var shouldFail: Bool = false
    private(set) var sleepCalls: Int = 0
    private(set) var lockCalls: Int = 0
    private(set) var logoutCalls: Int = 0
    private(set) var restartCalls: Int = 0
    private(set) var shutdownCalls: Int = 0

    func sleep() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to sleep.")
        }
        sleepCalls += 1
    }

    func lock() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to lock screen.")
        }
        lockCalls += 1
    }

    func logout() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to log out.")
        }
        logoutCalls += 1
    }

    func restart() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to restart.")
        }
        restartCalls += 1
    }

    func shutdown() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to shut down.")
        }
        shutdownCalls += 1
    }
}

/// Executes System Power commands.
@MainActor
struct SystemPowerCommandExecutor: CommandExecuting {
    private let control: SystemPowerControlling

    let supportedIdentifiers: Set<CommandIdentifier> = [
        .systemSleep,
        .systemLock,
        .systemLogout,
        .systemRestart,
        .systemShutdown
    ]

    init(control: SystemPowerControlling) {
        self.control = control
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        switch intent.identifier {
        case .systemSleep:
            try control.sleep()
            return "Mac is going to sleep."

        case .systemLock:
            try control.lock()
            return "Screen locked."

        case .systemLogout:
            try control.logout()
            return "Logging out."

        case .systemRestart:
            try control.restart()
            return "Restarting Mac."

        case .systemShutdown:
            try control.shutdown()
            return "Shutting down Mac."

        default:
            throw CommandExecutionError.unsupported(intent.identifier)
        }
    }
}