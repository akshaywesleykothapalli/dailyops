import Foundation

/// Crash-safe, disk-based persistence store for agent session snapshots.
/// Completely decoupled from runtime controllers and execution engines.
public final class AgentSessionStore: @unchecked Sendable {
    public let baseDirectory: URL
    private let lock = NSLock()

    public var sessionsDirectory: URL {
        baseDirectory.appendingPathComponent("Sessions", isDirectory: true)
    }

    public var archiveDirectory: URL {
        baseDirectory.appendingPathComponent("Archive", isDirectory: true)
    }

    public var corruptDirectory: URL {
        baseDirectory.appendingPathComponent("Corrupt", isDirectory: true)
    }

    public var activeFileURL: URL {
        baseDirectory.appendingPathComponent("active.json", isDirectory: false)
    }

    public static var defaultBaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DailyOps/AgentSessions", isDirectory: true)
    }

    public static let shared = AgentSessionStore(baseDirectory: defaultBaseDirectory)

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? ensureDirectoriesExist()
    }

    // MARK: - Directory Management

    public func ensureDirectoriesExist() throws {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        } catch {
            throw PersistenceError.directoryCreationFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Session Operations

    /// Saves a session snapshot atomically to the Sessions directory.
    public func save(_ snapshot: AgentSessionSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        let destinationURL = sessionFileURL(for: snapshot.sessionID)
        try writeSnapshot(snapshot, to: destinationURL)
    }

    /// Loads a session snapshot by its UUID from either Sessions or Archive.
    public func load(sessionID: UUID) throws -> AgentSessionSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let activeSessionURL = sessionFileURL(for: sessionID)
        let archiveSessionURL = archiveFileURL(for: sessionID)

        let targetURL: URL
        if FileManager.default.fileExists(atPath: activeSessionURL.path) {
            targetURL = activeSessionURL
        } else if FileManager.default.fileExists(atPath: archiveSessionURL.path) {
            targetURL = archiveSessionURL
        } else {
            throw PersistenceError.fileNotFound(activeSessionURL.path)
        }

        return try readSnapshot(from: targetURL)
    }

    /// Saves a snapshot as the active running session.
    public func saveActive(_ snapshot: AgentSessionSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        // Save to active.json atomically
        try writeSnapshot(snapshot, to: activeFileURL)
        // Also ensure it is saved in the Sessions collection
        let sessionURL = sessionFileURL(for: snapshot.sessionID)
        try writeSnapshot(snapshot, to: sessionURL)
    }

    /// Loads the currently active session, returning nil if none exists.
    public func loadActive() throws -> AgentSessionSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: activeFileURL.path) else {
            return nil
        }

        return try readSnapshot(from: activeFileURL)
    }

    /// Clears the active session marker.
    public func clearActive() throws {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        if fm.fileExists(atPath: activeFileURL.path) {
            do {
                try fm.removeItem(at: activeFileURL)
            } catch {
                throw PersistenceError.writeFailed(reason: "Failed to remove active session: \(error.localizedDescription)")
            }
        }
    }

    /// Archives a session snapshot into the Archive directory.
    public func archive(_ snapshot: AgentSessionSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        let archiveURL = archiveFileURL(for: snapshot.sessionID)
        try writeSnapshot(snapshot, to: archiveURL)

        // If this snapshot was the active session, clear it
        if FileManager.default.fileExists(atPath: activeFileURL.path) {
            if let activeSnapshot = try? readSnapshot(from: activeFileURL),
               activeSnapshot.sessionID == snapshot.sessionID {
                try? FileManager.default.removeItem(at: activeFileURL)
            }
        }

        // Remove from active Sessions directory if present
        let sessionURL = sessionFileURL(for: snapshot.sessionID)
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            try? FileManager.default.removeItem(at: sessionURL)
        }
    }

    /// Loads recent archived sessions, sorted newest first, up to the specified limit.
    public func loadRecentArchives(limit: Int = 50) throws -> [AgentSessionSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        guard fm.fileExists(atPath: archiveDirectory.path) else {
            return []
        }

        let urls = try fm.contentsOfDirectory(
            at: archiveDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }

        var snapshots: [AgentSessionSnapshot] = []

        for url in urls {
            do {
                let snapshot = try readSnapshot(from: url)
                snapshots.append(snapshot)
            } catch {
                // readSnapshot already quarantines corrupt files
                continue
            }
        }

        // Sort newest first by updatedAt, tie-breaking on createdAt
        snapshots.sort { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        if limit > 0 && snapshots.count > limit {
            return Array(snapshots.prefix(limit))
        }

        return snapshots
    }

    /// Deletes a session by ID from Sessions, Archive, and active.json if matching.
    public func delete(sessionID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        let sessionURL = sessionFileURL(for: sessionID)
        let archiveURL = archiveFileURL(for: sessionID)

        if fm.fileExists(atPath: sessionURL.path) {
            try? fm.removeItem(at: sessionURL)
        }
        if fm.fileExists(atPath: archiveURL.path) {
            try? fm.removeItem(at: archiveURL)
        }
        if fm.fileExists(atPath: activeFileURL.path) {
            if let active = try? readSnapshot(from: activeFileURL), active.sessionID == sessionID {
                try? fm.removeItem(at: activeFileURL)
            }
        }
    }

    // MARK: - Private Helpers

    public func sessionFileURL(for sessionID: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionID.uuidString).json", isDirectory: false)
    }

    public func archiveFileURL(for sessionID: UUID) -> URL {
        archiveDirectory.appendingPathComponent("\(sessionID.uuidString).json", isDirectory: false)
    }

    private func writeSnapshot(_ snapshot: AgentSessionSnapshot, to destinationURL: URL) throws {
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            throw PersistenceError.writeFailed(reason: "Encoding failed: \(error.localizedDescription)")
        }

        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw PersistenceError.writeFailed(reason: "Atomic write failed: \(error.localizedDescription)")
        }
    }

    private func readSnapshot(from sourceURL: URL) throws -> AgentSessionSnapshot {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw PersistenceError.fileNotFound(sourceURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw PersistenceError.corruptedData(reason: "Could not read data: \(error.localizedDescription)")
        }

        let snapshot: AgentSessionSnapshot
        do {
            snapshot = try decoder.decode(AgentSessionSnapshot.self, from: data)
        } catch {
            // Quarantine corrupt file
            quarantineCorruptFile(sourceURL)
            throw PersistenceError.corruptedData(reason: "JSON decoding failed: \(error.localizedDescription)")
        }

        // Verify schema version
        guard snapshot.schemaVersion <= AgentSessionSnapshot.currentSchemaVersion else {
            throw PersistenceError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }

        return snapshot
    }

    private func quarantineCorruptFile(_ fileURL: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: corruptDirectory.path) {
            try? fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let targetName = "\(baseName)_\(timestamp).corrupt.json"
        let targetURL = corruptDirectory.appendingPathComponent(targetName)

        // Attempt move or copy
        if (try? fm.moveItem(at: fileURL, to: targetURL)) == nil {
            try? fm.copyItem(at: fileURL, to: targetURL)
        }
    }
}
