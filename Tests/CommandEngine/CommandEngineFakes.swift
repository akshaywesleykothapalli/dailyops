import Foundation
@testable import DailyOps

/// Resolves only the names it was seeded with. Nothing here touches
/// `/Applications` or `NSWorkspace`, so parser tests cannot launch or quit a
/// real application.
@MainActor
final class FakeApplicationResolver: ApplicationResolving {
    var installed: [String: ApplicationReference]
    var running: [String: ApplicationReference]
    private(set) var installedQueries: [String] = []
    private(set) var runningQueries: [String] = []

    init(installed: [String] = [], running: [String] = []) {
        self.installed = Dictionary(
            uniqueKeysWithValues: installed.map {
                ($0, ApplicationReference(displayName: $0, bundleURL: URL(fileURLWithPath: "/Applications/\($0).app")))
            }
        )
        self.running = Dictionary(
            uniqueKeysWithValues: running.map {
                ($0, ApplicationReference(displayName: $0, bundleURL: nil))
            }
        )
    }

    func installedApplication(named query: String) -> ApplicationReference? {
        installedQueries.append(query)
        if let direct = installed[query] { return direct }
        let lower = query.lowercased()
        return installed.first { $0.key.lowercased() == lower }?.value
    }

    func runningApplication(named query: String) -> ApplicationReference? {
        runningQueries.append(query)
        if let direct = running[query] { return direct }
        let lower = query.lowercased()
        return running.first { $0.key.lowercased() == lower }?.value
    }
}

/// Records what it was asked to do and can be told to fail, so the router's
/// success and failure paths are both reachable without side effects.
@MainActor
final class FakeExecutor: CommandExecuting {
    let supportedIdentifiers: Set<CommandIdentifier>
    var errorToThrow: CommandExecutionError?
    var feedback: String
    private(set) var executed: [CommandIntent] = []

    init(
        supportedIdentifiers: Set<CommandIdentifier>,
        feedback: String = "Done",
        errorToThrow: CommandExecutionError? = nil
    ) {
        self.supportedIdentifiers = supportedIdentifiers
        self.feedback = feedback
        self.errorToThrow = errorToThrow
    }

    func execute(_ intent: CommandIntent, context: CommandContext) throws -> String {
        executed.append(intent)
        if let errorToThrow { throw errorToThrow }
        return feedback
    }
}

/// Returns a fixed plan regardless of input. Used to drive the router without
/// depending on the deterministic parser's phrase table.
@MainActor
struct StubParser: CommandParsing {
    let plan: CommandPlan?

    func parse(_ transcript: String, context: CommandContext) -> CommandPlan? {
        plan
    }
}

/// Records host calls instead of touching windows, the pasteboard or the model.
@MainActor
final class FakeCommandHost: CommandHosting {
    private(set) var calls: [String] = []
    private(set) var writingModes: [WritingMode] = []

    func showSettings() { calls.append("showSettings") }
    func showHistory() { calls.append("showHistory") }
    func copyLastDictation() { calls.append("copyLastDictation") }
    func clearClipboard() { calls.append("clearClipboard") }
    func reloadSpeechModel() { calls.append("reloadSpeechModel") }

    func setWritingMode(_ mode: WritingMode) {
        calls.append("setWritingMode")
        writingModes.append(mode)
    }
}

/// Records launch/quit/hide requests. No process is ever signalled.
@MainActor
final class FakeApplicationControl: ApplicationControlling {
    var errorToThrow: CommandExecutionError?
    private(set) var launched: [ApplicationReference] = []
    private(set) var activated: [ApplicationReference] = []
    private(set) var quit: [ApplicationReference] = []
    private(set) var hidden: [ApplicationReference] = []

    func launch(_ reference: ApplicationReference) throws {
        if let errorToThrow { throw errorToThrow }
        launched.append(reference)
    }

    func activate(_ reference: ApplicationReference) throws {
        if let errorToThrow { throw errorToThrow }
        activated.append(reference)
    }

    func quit(_ reference: ApplicationReference) throws {
        if let errorToThrow { throw errorToThrow }
        quit.append(reference)
    }

    func hide(_ reference: ApplicationReference) throws {
        if let errorToThrow { throw errorToThrow }
        hidden.append(reference)
    }
}

/// Records opened URLs without interacting with NSWorkspace or launching a real browser.
@MainActor
final class FakeBrowserControl: BrowserControlling {
    private(set) var openedURLs: [URL] = []
    private(set) var didOpenDefaultBrowser = false
    private(set) var didOpenPrivateWindow = false
    var shouldFail = false
    var defaultBrowserFeedback: String = "Opened Safari"
    var privateWindowFeedback: String = "Opened private window in Safari"
    var privateWindowError: CommandExecutionError?

    func open(_ url: URL) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Browser launch failed.")
        }
        openedURLs.append(url)
    }

    func openDefaultBrowser() throws -> String {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Browser launch failed.")
        }
        didOpenDefaultBrowser = true
        return defaultBrowserFeedback
    }

    func openPrivateWindow() throws -> String {
        if let error = privateWindowError {
            throw error
        }
        if shouldFail {
            throw CommandExecutionError.operationFailed("Browser launch failed.")
        }
        didOpenPrivateWindow = true
        return privateWindowFeedback
    }
}

/// Records opened WhatsApp URLs without launching WhatsApp or NSWorkspace.
@MainActor
final class FakeWhatsAppControl: WhatsAppControlling {
    private(set) var openedURLs: [URL] = []
    var shouldFail = false

    func open(_ url: URL) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("WhatsApp launch failed.")
        }
        openedURLs.append(url)
    }
}

/// Deterministic contact resolver for testing WhatsApp commands without querying CNContactStore.
@MainActor
final class FakeWhatsAppContactResolver: WhatsAppContactResolving {
    var responses: [String: ContactResolutionResult]
    private(set) var queriedNames: [String] = []

    init(responses: [String: ContactResolutionResult] = [:]) {
        self.responses = responses
    }

    func resolve(nameOrQuery: String) -> ContactResolutionResult {
        queriedNames.append(nameOrQuery)
        let lower = nameOrQuery.lowercased()
        if let direct = responses[nameOrQuery] { return direct }
        if let lowerMatch = responses.first(where: { $0.key.lowercased() == lower })?.value {
            return lowerMatch
        }
        return .notFound(query: nameOrQuery)
    }

    func reset() {
        queriedNames.removeAll()
    }
}

/// Records Mail compose operations without launching Mail or NSWorkspace.
@MainActor
final class FakeMailControl: MailControlling {
    var openedMail: Bool = false
    var composedEmails: [MailComposeRequest] = []
    var shouldFail = false

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

/// Records Clipboard inspection operations without accessing the real pasteboard.
@MainActor
final class FakeClipboardControl: ClipboardControlling {
    var contentToReturn: ClipboardContent?
    var shouldFail: Bool = false

    func inspectClipboard() throws -> ClipboardContent {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Clipboard inspection failed.")
        }
        return contentToReturn ?? ClipboardContent(hasText: false, text: nil, typeDescription: "empty")
    }
}

/// Records system information operations without accessing real system APIs.
@MainActor
final class FakeSystemInformationControl: SystemInformationControlling {
    var batteryInfoToReturn: BatteryInfo?
    var macOSVersionToReturn: MacOSVersionInfo?
    var timeToReturn: TimeInfo?
    var dateToReturn: DateInfo?
    var shouldFail: Bool = false

    func getBatteryInfo() throws -> BatteryInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Battery information unavailable.")
        }
        return batteryInfoToReturn ?? BatteryInfo(percentage: nil, isCharging: false, isFullyCharged: false, timeRemaining: nil, isACPowered: false)
    }

    func getMacOSVersion() throws -> MacOSVersionInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("macOS version unavailable.")
        }
        return macOSVersionToReturn ?? MacOSVersionInfo(versionString: "macOS 26.0", buildVersion: "26A000")
    }

    func getCurrentTime() throws -> TimeInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Time unavailable.")
        }
        return timeToReturn ?? TimeInfo(formattedTime: "12:00 PM")
    }

    func getCurrentDate() throws -> DateInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Date unavailable.")
        }
        return dateToReturn ?? DateInfo(formattedDate: "Monday, January 1, 2024")
    }
}

/// Records system audio operations without accessing real Core Audio APIs.
@MainActor
final class FakeSystemAudioControl: SystemAudioControlling {
    var volumeToReturn: Float = 0.5
    var mutedToReturn: Bool = false
    var shouldFail: Bool = false

    private(set) var setVolumeCalls: [Float] = []
    private(set) var volumeUpCalls: Int = 0
    private(set) var volumeDownCalls: Int = 0
    private(set) var muteCalls: Int = 0
    private(set) var unmuteCalls: Int = 0

    func getVolume() throws -> VolumeInfo {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Volume unavailable.")
        }
        return VolumeInfo(volume: volumeToReturn, isMuted: mutedToReturn)
    }

    func setVolume(_ volume: Float) throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to set volume.")
        }
        setVolumeCalls.append(volume)
    }

    func volumeUp() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to increase volume.")
        }
        volumeUpCalls += 1
    }

    func volumeDown() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to decrease volume.")
        }
        volumeDownCalls += 1
    }

    func mute() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to mute volume.")
        }
        muteCalls += 1
    }

    func unmute() throws {
        if shouldFail {
            throw CommandExecutionError.operationFailed("Failed to unmute volume.")
        }
        unmuteCalls += 1
    }
}

/// Records system power/session operations without accessing real system APIs.
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

extension CommandContext {

    /// A context with command mode on and no frontmost application, which is
    /// what most tests want.
    static func test(isCommandModeEnabled: Bool = true) -> CommandContext {
        CommandContext(
            frontmostApplicationName: "",
            timestamp: Date(timeIntervalSince1970: 0),
            isCommandModeEnabled: isCommandModeEnabled
        )
    }

    /// A context with a specific frontmost application for testing context-aware commands.
    static func test(frontmostApplicationName: String, isCommandModeEnabled: Bool = true) -> CommandContext {
        CommandContext(
            frontmostApplicationName: frontmostApplicationName,
            timestamp: Date(timeIntervalSince1970: 0),
            isCommandModeEnabled: isCommandModeEnabled
        )
    }

    /// A context with a resolved file for testing "open it" style commands.
    static func test(resolvedFileURL: URL, isCommandModeEnabled: Bool = true) -> CommandContext {
        CommandContext(
            frontmostApplicationName: "",
            timestamp: Date(timeIntervalSince1970: 0),
            isCommandModeEnabled: isCommandModeEnabled,
            resolvedFileURL: resolvedFileURL,
            resolvedFileName: resolvedFileURL.lastPathComponent
        )
    }
}

/// Fake Email Contact resolver for unit testing.
@MainActor
final class FakeEmailContactResolver: EmailContactResolving {
    var responses: [String: EmailContactResolutionResult]
    private(set) var queriedNames: [String] = []

    init(responses: [String: EmailContactResolutionResult] = [:]) {
        self.responses = responses
    }

    func resolve(nameOrQuery: String) -> EmailContactResolutionResult {
        queriedNames.append(nameOrQuery)
        let lower = nameOrQuery.lowercased()
        if let direct = responses[nameOrQuery] { return direct }
        if let lowerMatch = responses.first(where: { $0.key.lowercased() == lower })?.value {
            return lowerMatch
        }
        return .notFound(query: nameOrQuery)
    }

    func reset() {
        queriedNames.removeAll()
    }
}
