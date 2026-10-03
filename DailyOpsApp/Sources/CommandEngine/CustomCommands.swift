import AppKit
import Foundation

// MARK: - Custom Command Action Type

public enum CustomCommandActionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case openApplication = "open_app"
    case openURL = "open_url"
    case openFolder = "open_folder"
    case openFile = "open_file"
    case systemSettings = "system_settings"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openApplication: return "Open Application"
        case .openURL: return "Open URL"
        case .openFolder: return "Open Folder"
        case .openFile: return "Open File"
        case .systemSettings: return "System Settings"
        }
    }

    public var icon: String {
        switch self {
        case .openApplication: return "app.badge"
        case .openURL: return "safari"
        case .openFolder: return "folder"
        case .openFile: return "doc"
        case .systemSettings: return "gearshape"
        }
    }

    public var placeholder: String {
        switch self {
        case .openApplication: return "e.g. Safari, Xcode, or /Applications/Slack.app"
        case .openURL: return "e.g. https://github.com or google.com"
        case .openFolder: return "e.g. ~/Downloads or /Users/.../Documents"
        case .openFile: return "e.g. ~/Documents/Notes.txt"
        case .systemSettings: return "e.g. default, displays, sound, network"
        }
    }
}

// MARK: - Custom Command Model

public struct CustomCommand: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var triggerPhrase: String
    public var actionType: CustomCommandActionType
    public var target: String
    public var customDescription: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        triggerPhrase: String,
        actionType: CustomCommandActionType,
        target: String,
        customDescription: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.triggerPhrase = triggerPhrase
        self.actionType = actionType
        self.target = target
        self.customDescription = customDescription
        self.isEnabled = isEnabled
    }
}

// MARK: - Custom Command Store

@MainActor
public final class CustomCommandStore: ObservableObject {
    public static let shared = CustomCommandStore()

    private let userDefaultsKey = "dailyops_custom_commands"

    @Published public var commands: [CustomCommand] = []

    public init() {
        loadCommands()
    }

    public func loadCommands() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([CustomCommand].self, from: data) {
            self.commands = decoded
        } else {
            // Default sample custom commands
            self.commands = [
                CustomCommand(
                    triggerPhrase: "open github",
                    actionType: .openURL,
                    target: "https://github.com",
                    customDescription: "Opens GitHub in your default browser"
                ),
                CustomCommand(
                    triggerPhrase: "open downloads",
                    actionType: .openFolder,
                    target: "~/Downloads",
                    customDescription: "Opens Downloads folder in Finder"
                )
            ]
            saveCommands()
        }
    }

    public func saveCommands() {
        if let encoded = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    public func add(_ command: CustomCommand) {
        commands.append(command)
        saveCommands()
    }

    public func update(_ command: CustomCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
            saveCommands()
        }
    }

    public func delete(id: UUID) {
        commands.removeAll { $0.id == id }
        saveCommands()
    }

    public func toggle(id: UUID) {
        if let index = commands.firstIndex(where: { $0.id == id }) {
            commands[index].isEnabled.toggle()
            saveCommands()
        }
    }

    public func findMatching(transcript: String) -> CustomCommand? {
        let normQuery = CommandModeService.normalized(transcript)
        guard !normQuery.isEmpty else { return nil }

        return commands.first { cmd in
            guard cmd.isEnabled else { return false }
            let normTrigger = CommandModeService.normalized(cmd.triggerPhrase)
            return normQuery == normTrigger
        }
    }
}

// MARK: - Custom Command Execution Result

public enum CustomCommandExecutionResult: Equatable, Sendable {
    case success(String)
    case failure(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .success(let msg), .failure(let msg): return msg
        }
    }
}

// MARK: - Custom Command Executor

@MainActor
public final class CustomCommandExecutor {
    public static let shared = CustomCommandExecutor()

    public func execute(_ command: CustomCommand) -> CustomCommandExecutionResult {
        let trimmedTarget = command.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else {
            return .failure("Target cannot be empty.")
        }

        switch command.actionType {
        case .openApplication:
            return executeOpenApplication(target: trimmedTarget)

        case .openURL:
            return executeOpenURL(target: trimmedTarget)

        case .openFolder:
            return executeOpenFolder(target: trimmedTarget)

        case .openFile:
            return executeOpenFile(target: trimmedTarget)

        case .systemSettings:
            return executeSystemSettings(target: trimmedTarget)
        }
    }

    private func executeOpenApplication(target: String) -> CustomCommandExecutionResult {
        if target.hasPrefix("/") {
            let expanded = (target as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure("Application not found at path: \(target)")
            }
            if NSWorkspace.shared.open(url) {
                return .success("Opened \(url.deletingPathExtension().lastPathComponent)")
            } else {
                return .failure("Failed to launch application at \(target)")
            }
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target), NSWorkspace.shared.open(appURL) {
            return .success("Opened \(target)")
        }

        // Search common application locations
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        let targetLower = target.lowercased()
        for dir in searchDirs {
            let appURL = dir.appendingPathComponent("\(target).app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                if NSWorkspace.shared.open(appURL) {
                    return .success("Opened \(target)")
                }
            }

            // Case-insensitive file search in directory
            if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for item in contents where item.pathExtension.lowercased() == "app" {
                    let baseName = item.deletingPathExtension().lastPathComponent
                    if baseName.lowercased() == targetLower || baseName.lowercased().hasPrefix(targetLower) {
                        if NSWorkspace.shared.open(item) {
                            return .success("Opened \(baseName)")
                        }
                    }
                }
            }
        }

        return .failure("Could not find or open application '\(target)'.")
    }

    private func executeOpenURL(target: String) -> CustomCommandExecutionResult {
        var urlString = target
        if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            return .failure("Invalid URL: '\(target)'")
        }

        if NSWorkspace.shared.open(url) {
            return .success("Opened \(url.absoluteString)")
        } else {
            return .failure("Failed to open URL '\(urlString)'")
        }
    }

    private func executeOpenFolder(target: String) -> CustomCommandExecutionResult {
        let expanded = (target as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return .failure("Folder does not exist: '\(target)'")
        }

        let url = URL(fileURLWithPath: expanded)
        if NSWorkspace.shared.open(url) {
            return .success("Opened folder \(url.lastPathComponent)")
        } else {
            return .failure("Failed to open folder '\(target)'")
        }
    }

    private func executeOpenFile(target: String) -> CustomCommandExecutionResult {
        let expanded = (target as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else {
            return .failure("File does not exist: '\(target)'")
        }

        let url = URL(fileURLWithPath: expanded)
        if NSWorkspace.shared.open(url) {
            return .success("Opened file \(url.lastPathComponent)")
        } else {
            return .failure("Failed to open file '\(target)'")
        }
    }

    private func executeSystemSettings(target: String) -> CustomCommandExecutionResult {
        let lower = target.lowercased()
        var url: URL?

        if lower == "default" || lower == "settings" || lower.isEmpty {
            url = URL(string: "x-apple.systempreferences:")
        } else if lower.hasPrefix("x-apple.systempreferences:") {
            url = URL(string: target)
        } else {
            let paneMap: [String: String] = [
                "display": "com.apple.Displays-Settings.extension",
                "displays": "com.apple.Displays-Settings.extension",
                "sound": "com.apple.Sound-Settings.extension",
                "audio": "com.apple.Sound-Settings.extension",
                "network": "com.apple.Network-Settings.extension",
                "wifi": "com.apple.wifi-settings-extension",
                "bluetooth": "com.apple.BluetoothSettings",
                "keyboard": "com.apple.Keyboard-Settings.extension",
                "trackpad": "com.apple.Trackpad-Settings.extension",
                "mouse": "com.apple.Mouse-Settings.extension",
                "battery": "com.apple.Battery-Settings.extension",
                "wallpaper": "com.apple.Wallpaper-Settings.extension",
                "notifications": "com.apple.Notifications-Settings.extension",
                "privacy": "com.apple.settings.PrivacySecurity.extension"
            ]

            if let ext = paneMap[lower] {
                url = URL(string: "x-apple.systempreferences:\(ext)")
            } else {
                url = URL(string: "x-apple.systempreferences:")
            }
        }

        if let validURL = url, NSWorkspace.shared.open(validURL) {
            return .success("Opened System Settings")
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
           NSWorkspace.shared.open(settingsURL) {
            return .success("Opened System Settings")
        }

        return .failure("Failed to open System Settings.")
    }
}
