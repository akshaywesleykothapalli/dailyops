import AppKit
import Foundation

/// A known macOS application descriptor supported natively by DailyOps.
struct KnownApplication: Equatable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let defaultPath: String?
    let aliases: Set<String>

    init(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        defaultPath: String? = nil,
        aliases: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.defaultPath = defaultPath
        var normalizedAliases = Set(aliases.map { CommandTextNormalizer.normalize($0) })
        normalizedAliases.insert(CommandTextNormalizer.normalize(displayName))
        normalizedAliases.insert(CommandTextNormalizer.normalize(id))
        self.aliases = normalizedAliases
    }

    func matches(query: String) -> Bool {
        let normalized = CommandTextNormalizer.normalize(query)
        return aliases.contains(normalized)
    }
}

/// Registry providing deterministic resolution of common desktop application names to system bundles.
@MainActor
final class ApplicationRegistry {
    private var knownApplications: [String: KnownApplication] = [:]

    init(applications: [KnownApplication] = ApplicationRegistry.standardApplications) {
        for app in applications {
            register(app)
        }
    }

    func register(_ application: KnownApplication) {
        knownApplications[application.id] = application
    }

    func findKnownApplication(named query: String) -> KnownApplication? {
        let normalized = CommandTextNormalizer.normalize(query)
        for app in knownApplications.values {
            if app.matches(query: normalized) {
                return app
            }
        }
        return nil
    }

    /// Resolves an application name to an `ApplicationReference` using system APIs (bundle ID or path)
    /// without ever accepting arbitrary executable paths from user text.
    func resolve(named query: String) -> ApplicationReference? {
        if let known = findKnownApplication(named: query) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: known.bundleIdentifier) {
                return ApplicationReference(displayName: known.displayName, bundleURL: url)
            }
            if let path = known.defaultPath, FileManager.default.fileExists(atPath: path) {
                return ApplicationReference(displayName: known.displayName, bundleURL: URL(fileURLWithPath: path))
            }
            return ApplicationReference(displayName: known.displayName, bundleURL: nil)
        }
        return nil
    }

    static let standardApplications: [KnownApplication] = [
        KnownApplication(
            id: "whatsapp",
            displayName: "WhatsApp",
            bundleIdentifier: "net.whatsapp.WhatsApp",
            defaultPath: "/Applications/WhatsApp.app",
            aliases: ["whatsapp", "whats app"]
        ),
        KnownApplication(
            id: "safari",
            displayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            defaultPath: "/Applications/Safari.app",
            aliases: ["safari", "apple safari"]
        ),
        KnownApplication(
            id: "chrome",
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            defaultPath: "/Applications/Google Chrome.app",
            aliases: ["chrome", "google chrome", "googlechrome"]
        ),
        KnownApplication(
            id: "finder",
            displayName: "Finder",
            bundleIdentifier: "com.apple.finder",
            defaultPath: "/System/Library/CoreServices/Finder.app",
            aliases: ["finder", "macos finder"]
        ),
        KnownApplication(
            id: "settings",
            displayName: "System Settings",
            bundleIdentifier: "com.apple.systempreferences",
            defaultPath: "/System/Applications/System Settings.app",
            aliases: ["system settings", "settings", "preferences", "system preferences", "sys pref"]
        ),
        KnownApplication(
            id: "notes",
            displayName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            defaultPath: "/System/Applications/Notes.app",
            aliases: ["notes", "apple notes"]
        ),
        KnownApplication(
            id: "calendar",
            displayName: "Calendar",
            bundleIdentifier: "com.apple.iCal",
            defaultPath: "/System/Applications/Calendar.app",
            aliases: ["calendar", "apple calendar", "ical"]
        ),
        KnownApplication(
            id: "reminders",
            displayName: "Reminders",
            bundleIdentifier: "com.apple.reminders",
            defaultPath: "/System/Applications/Reminders.app",
            aliases: ["reminders", "apple reminders"]
        ),
        KnownApplication(
            id: "music",
            displayName: "Music",
            bundleIdentifier: "com.apple.Music",
            defaultPath: "/System/Applications/Music.app",
            aliases: ["music", "apple music"]
        ),
        KnownApplication(
            id: "terminal",
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            defaultPath: "/System/Applications/Utilities/Terminal.app",
            aliases: ["terminal", "apple terminal"]
        )
    ]
}
