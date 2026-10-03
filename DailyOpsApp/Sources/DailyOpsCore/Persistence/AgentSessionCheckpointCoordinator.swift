import Foundation

/// Concurrency-safe coordinator for checkpointing agent session state to persistence.
/// Serializes writes, manages active/archived sessions, and isolates persistence failures from the runtime.
public final class AgentSessionCheckpointCoordinator: @unchecked Sendable {
    private let store: AgentSessionStore
    private let lock = NSLock()
    private var currentSessionID: UUID?
    private var isArchiving = false

    public init(store: AgentSessionStore) {
        self.store = store
    }

    /// Returns the current session ID if one is active.
    public var activeSessionID: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return currentSessionID
    }

    /// Checkpoints a session snapshot, updating the active session marker.
    /// For terminal statuses (.completed, .failed, .cancelled), archives and clears the active session.
    /// Persistence failures are logged but do not throw — the runtime remains authoritative.
    public func checkpoint(
        _ snapshot: AgentSessionSnapshot,
        status: PersistedSessionStatus
    ) {
        lock.lock()
        defer { lock.unlock() }

        do {
            // Update the snapshot with the provided status and current timestamp
            let updatedSnapshot = AgentSessionSnapshot(
                schemaVersion: snapshot.schemaVersion,
                sessionID: snapshot.sessionID,
                goalID: snapshot.goalID,
                goalText: snapshot.goalText,
                normalizedIntent: snapshot.normalizedIntent,
                role: snapshot.role,
                intelligenceLevel: snapshot.intelligenceLevel,
                routingReason: snapshot.routingReason,
                planID: snapshot.planID,
                createdAt: snapshot.createdAt,
                updatedAt: Date(),
                status: status,
                tasks: snapshot.tasks,
                pendingApproval: snapshot.pendingApproval,
                recentActivity: snapshot.recentActivity
            )

            // Save as active session (writes to both active.json and Sessions/)
            try store.saveActive(updatedSnapshot)

            // Track the current session ID
            currentSessionID = snapshot.sessionID

            // If terminal status, archive and clear active
            if isTerminal(status) {
                archiveAndClearLocked(sessionID: snapshot.sessionID)
            }

        } catch {
            // Log but don't crash — execution system remains authoritative
            logPersistenceError("checkpoint", error)
        }
    }

    /// Starts a new session, clearing any existing active session identity.
    /// Returns the new session ID.
    public func startNewSession() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let newSessionID = UUID()
        currentSessionID = newSessionID
        return newSessionID
    }

    /// Sets the active session ID to an existing resumed session.
    public func setResumedSessionID(_ sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        currentSessionID = sessionID
    }

    /// Clears the in-memory session identity without touching persisted files.
    /// Call when the user explicitly resets or starts a genuinely new goal.
    public func clearSessionIdentity() {
        lock.lock()
        defer { lock.unlock() }
        currentSessionID = nil
    }

    /// Forces archival of the current session if it exists and is terminal.
    public func forceArchiveIfTerminal() {
        lock.lock()
        defer { lock.unlock() }
        guard let sessionID = currentSessionID else { return }
        archiveAndClearLocked(sessionID: sessionID)
    }

    // MARK: - Private Helpers

    private func isTerminal(_ status: PersistedSessionStatus) -> Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .planned, .executing, .paused, .waitingForApproval:
            return false
        }
    }

    private func archiveAndClearLocked(sessionID: UUID) {
        guard !isArchiving else { return }
        isArchiving = true
        defer { isArchiving = false }

        do {
            // Load the latest snapshot to archive
            let snapshot = try store.load(sessionID: sessionID)
            try store.archive(snapshot)

            // Clear active session identity if it matches
            if currentSessionID == sessionID {
                currentSessionID = nil
            }
        } catch {
            logPersistenceError("archiveAndClear", error)
        }
    }

    private func logPersistenceError(_ operation: String, _ error: Error) {
        // In production, this would use a proper logging framework
        // For now, print to stderr for visibility during development
        fputs("[DailyOps Persistence] \(operation) failed: \(error)\n", stderr)
    }
}