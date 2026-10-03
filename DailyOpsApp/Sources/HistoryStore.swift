import Foundation
import os
import SwiftData

private let historyLog = Logger(subsystem: AppBrand.bundleIdentifier, category: "history")

@Model
final class DictationEntry {
    var date: Date
    var raw: String
    var cleaned: String
    var duration: TimeInterval
    var appName: String
    /// Stored optional flag for SwiftData lightweight migration compatibility.
    /// Existing stores on disk will read nil, which is treated as false.
    var isCommandStored: Bool?
    /// Short human-readable summary of what the command did, e.g.
    /// "Opened Safari" or "Reminder created: Buy milk". Nil for dictation entries.
    var commandSummary: String?

    /// True when this entry was created by a voice command rather than plain dictation.
    var isCommand: Bool {
        get { isCommandStored ?? false }
        set { isCommandStored = newValue }
    }

    init(
        date: Date = .now,
        raw: String,
        cleaned: String,
        duration: TimeInterval,
        appName: String,
        isCommand: Bool = false,
        commandSummary: String? = nil
    ) {
        self.date = date
        self.raw = raw
        self.cleaned = cleaned
        self.duration = duration
        self.appName = appName
        self.isCommandStored = isCommand
        self.commandSummary = commandSummary
    }
}

/// Local-only persistence for past dictations.
@MainActor
final class HistoryStore {
    let container: ModelContainer
    private(set) var isPersistent: Bool = true
    private(set) var initializationError: Error? = nil

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "historyEnabled") as? Bool ?? true
    }

    private static var defaultStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppBrand.applicationSupportDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("DailyOps.store")
    }

    init(
        container: ModelContainer? = nil,
        isPersistent: Bool? = nil,
        containerProvider: (() throws -> ModelContainer)? = nil
    ) {
        if let injected = container {
            self.container = injected
            if let explicitPersistent = isPersistent {
                self.isPersistent = explicitPersistent
            } else {
                let isInMemory = injected.configurations.contains { $0.isStoredInMemoryOnly }
                self.isPersistent = !isInMemory
            }
            return
        }

        do {
            if let provider = containerProvider {
                self.container = try provider()
            } else {
                let configuration = ModelConfiguration(url: Self.defaultStoreURL)
                self.container = try ModelContainer(for: DictationEntry.self, configurations: configuration)
            }
            let isInMemory = self.container.configurations.contains { $0.isStoredInMemoryOnly }
            self.isPersistent = !isInMemory
        } catch {
            historyLog.error("Could not create persistent history store: \(error.localizedDescription). Falling back to in-memory container.")
            self.initializationError = error
            self.isPersistent = false
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                self.container = try ModelContainer(for: DictationEntry.self, configurations: config)
            } catch let inMemoryError {
                historyLog.fault("Critical failure: in-memory history container failed: \(inMemoryError.localizedDescription)")
                fatalError("Could not create fallback in-memory history store: \(inMemoryError)")
            }
        }
    }

    func record(raw: String, cleaned: String, duration: TimeInterval, appName: String) {
        guard Self.isEnabled else { return }
        let entry = DictationEntry(raw: raw, cleaned: cleaned, duration: duration, appName: appName)
        container.mainContext.insert(entry)
        do {
            try container.mainContext.save()
        } catch {
            // A dropped save silently loses the dictation from history *and*
            // from every Insights aggregate derived from it; matching
            // `deleteAll()`, at least say so in the log.
            log.error("Could not save history entry: \(error.localizedDescription)")
        }
    }

    /// Records a successful or attempted voice command execution.
    /// Stored separately from dictation so the History UI can badge/filter them.
    /// `spoken` is the raw transcript; `summary` is the executor's feedback string.
    func recordCommand(spoken: String, summary: String, appName: String) {
        guard Self.isEnabled else { return }
        let entry = DictationEntry(
            raw: spoken,
            cleaned: summary,
            duration: 0,
            appName: appName,
            isCommand: true,
            commandSummary: summary
        )
        container.mainContext.insert(entry)
        do {
            try container.mainContext.save()
        } catch {
            log.error("Could not save command history entry: \(error.localizedDescription)")
        }
    }

    func deleteAll() {
        do {
            try container.mainContext.delete(model: DictationEntry.self)
            try container.mainContext.save()
        } catch {
            log.error("Could not clear history: \(error.localizedDescription)")
        }
    }

}
