import Testing
import Foundation
@testable import DailyOps

@Suite("AgentSessionStore Tests")
struct AgentSessionStoreTests {

    private func createTempStore() -> (AgentSessionStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DailyOpsTest_\(UUID().uuidString)", isDirectory: true)
        let store = AgentSessionStore(baseDirectory: tempDir)
        return (store, tempDir)
    }

    private func cleanupTempStore(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeSampleSnapshot(
        id: UUID = UUID(),
        goalText: String = "Test goal",
        role: EmployeeRole = .developer,
        intelligenceLevel: IntelligenceLevel = .L4,
        status: PersistedSessionStatus = .executing,
        updatedAt: Date = Date(),
        taskCount: Int = 2,
        withApproval: Bool = false
    ) -> AgentSessionSnapshot {
        let tasks = (0..<taskCount).map { i in
            PersistedTaskSnapshot(
                taskID: UUID(),
                title: "Task \(i)",
                description: "Description \(i)",
                order: i,
                status: i == 0 ? .completed : .inProgress,
                toolID: "test_tool_\(i)",
                riskLevel: .safe,
                dependencies: []
            )
        }

        let approval: PersistedApprovalSnapshot? = withApproval ? PersistedApprovalSnapshot(
            requestID: UUID(),
            taskID: tasks.first?.taskID ?? UUID(),
            toolID: "file_write",
            toolName: "File Write",
            description: "Write config file",
            riskLevel: .confirmationRequired,
            reason: "Modifies filesystem",
            status: .pending
        ) : nil

        let activities = [
            PersistedActivityEvent(stageKind: "Goal understood", detail: goalText, status: "completed"),
            PersistedActivityEvent(stageKind: "Plan created", detail: "2 tasks", status: "completed")
        ]

        return AgentSessionSnapshot(
            schemaVersion: 1,
            sessionID: id,
            goalID: UUID(),
            goalText: goalText,
            normalizedIntent: goalText,
            role: role,
            intelligenceLevel: intelligenceLevel,
            routingReason: "Complex developer workflow",
            planID: UUID(),
            createdAt: Date().addingTimeInterval(-60),
            updatedAt: updatedAt,
            status: status,
            tasks: tasks,
            pendingApproval: approval,
            recentActivity: activities
        )
    }

    // 1. Snapshot Codable roundtrip
    @Test("Snapshot Codable roundtrip preserves all fields")
    func snapshotCodableRoundtrip() throws {
        let original = makeSampleSnapshot(withApproval: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AgentSessionSnapshot.self, from: data)

        #expect(decoded.schemaVersion == original.schemaVersion)
        #expect(decoded.sessionID == original.sessionID)
        #expect(decoded.goalText == original.goalText)
        #expect(decoded.role == original.role)
        #expect(decoded.intelligenceLevel == original.intelligenceLevel)
        #expect(decoded.routingReason == original.routingReason)
        #expect(decoded.status == original.status)
        #expect(decoded.tasks.count == original.tasks.count)
        #expect(decoded.pendingApproval?.requestID == original.pendingApproval?.requestID)
        #expect(decoded.recentActivity.count == original.recentActivity.count)
    }

    // 2. Save + load by ID
    @Test("Save and load by ID retrieves identical snapshot")
    func saveAndLoadByID() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let original = makeSampleSnapshot()
        try store.save(original)

        let loaded = try store.load(sessionID: original.sessionID)
        #expect(loaded.sessionID == original.sessionID)
        #expect(loaded.goalText == original.goalText)
        #expect(loaded.status == original.status)
    }

    // 3. Save active + load active
    @Test("Save active and load active")
    func saveActiveAndLoadActive() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        #expect(try store.loadActive() == nil)

        let snapshot = makeSampleSnapshot()
        try store.saveActive(snapshot)

        let active = try store.loadActive()
        #expect(active != nil)
        #expect(active?.sessionID == snapshot.sessionID)
    }

    // 4. Replace active session
    @Test("Replacing active session updates active.json")
    func replaceActiveSession() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let first = makeSampleSnapshot()
        let second = makeSampleSnapshot()

        try store.saveActive(first)
        #expect(try store.loadActive()?.sessionID == first.sessionID)

        try store.saveActive(second)
        #expect(try store.loadActive()?.sessionID == second.sessionID)
    }

    // 5. Clear active session
    @Test("Clear active session removes active marker")
    func clearActiveSession() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot()
        try store.saveActive(snapshot)
        #expect(try store.loadActive() != nil)

        try store.clearActive()
        #expect(try store.loadActive() == nil)
    }

    // 6. Archive session
    @Test("Archiving session moves to Archive directory and clears active if matching")
    func archiveSession() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot()
        try store.saveActive(snapshot)

        try store.archive(snapshot)
        #expect(try store.loadActive() == nil)

        let loaded = try store.load(sessionID: snapshot.sessionID)
        #expect(loaded.sessionID == snapshot.sessionID)
    }

    // 7. Recent archives ordered newest first
    @Test("Recent archives are returned newest first")
    func recentArchivesOrderedNewestFirst() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let older = makeSampleSnapshot(id: UUID(), updatedAt: Date().addingTimeInterval(-200))
        let middle = makeSampleSnapshot(id: UUID(), updatedAt: Date().addingTimeInterval(-100))
        let newest = makeSampleSnapshot(id: UUID(), updatedAt: Date())

        try store.archive(older)
        try store.archive(middle)
        try store.archive(newest)

        let archives = try store.loadRecentArchives()
        #expect(archives.count == 3)
        #expect(archives[0].sessionID == newest.sessionID)
        #expect(archives[1].sessionID == middle.sessionID)
        #expect(archives[2].sessionID == older.sessionID)
    }

    // 8. Archive limit respected
    @Test("Archive limit restricts returned count")
    func archiveLimitRespected() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        for i in 0..<10 {
            let s = makeSampleSnapshot(id: UUID(), updatedAt: Date().addingTimeInterval(Double(i)))
            try store.archive(s)
        }

        let limited = try store.loadRecentArchives(limit: 4)
        #expect(limited.count == 4)
    }

    // 9. Delete session
    @Test("Delete session removes files from disk")
    func deleteSession() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot()
        try store.save(snapshot)

        try store.delete(sessionID: snapshot.sessionID)

        #expect(throws: PersistenceError.self) {
            try store.load(sessionID: snapshot.sessionID)
        }
    }

    // 10. Corrupt JSON handled without crash
    @Test("Corrupted JSON throws typed PersistenceError instead of crashing")
    func corruptJSONHandledSafely() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let sessionID = UUID()
        let fileURL = store.sessionFileURL(for: sessionID)
        try "{ this is invalid json".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(throws: PersistenceError.self) {
            try store.load(sessionID: sessionID)
        }
    }

    // 11. Corrupt file quarantined
    @Test("Corrupt file is quarantined into Corrupt directory")
    func corruptFileQuarantined() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        try "broken json data".write(to: store.activeFileURL, atomically: true, encoding: .utf8)

        #expect(throws: PersistenceError.self) {
            try store.loadActive()
        }

        let corruptFiles = try FileManager.default.contentsOfDirectory(atPath: store.corruptDirectory.path)
        #expect(!corruptFiles.isEmpty)
        #expect(corruptFiles.contains { $0.contains("corrupt.json") })
    }

    // 12. Unsupported schema rejected
    @Test("Unsupported schema version is rejected with typed error")
    func unsupportedSchemaRejected() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let sessionID = UUID()
        let futureJSON = """
        {
            "schemaVersion": 999,
            "sessionID": "\(sessionID.uuidString)",
            "goalID": "\(UUID().uuidString)",
            "goalText": "Future goal",
            "normalizedIntent": "Future goal",
            "role": "general",
            "intelligenceLevel": "L0",
            "routingReason": "Future",
            "planID": "\(UUID().uuidString)",
            "createdAt": "2026-10-03T12:00:00Z",
            "updatedAt": "2026-10-03T12:00:00Z",
            "status": "planned",
            "tasks": [],
            "recentActivity": []
        }
        """

        let fileURL = store.sessionFileURL(for: sessionID)
        try futureJSON.write(to: fileURL, atomically: true, encoding: .utf8)

        do {
            _ = try store.load(sessionID: sessionID)
            #expect(Bool(false), "Should have thrown unsupportedSchemaVersion")
        } catch let PersistenceError.unsupportedSchemaVersion(version) {
            #expect(version == 999)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    // 13. Activity list capped appropriately
    @Test("Activity list is capped at maxActivityEvents")
    func activityListCapped() {
        let manyEvents = (0..<150).map { i in
            PersistedActivityEvent(stageKind: "Event", detail: "Step \(i)", status: "completed")
        }

        let snapshot = AgentSessionSnapshot(
            goalText: "Capped activity goal",
            recentActivity: manyEvents
        )

        #expect(snapshot.recentActivity.count == 100)
        #expect(snapshot.recentActivity.last?.detail == "Step 149")
        #expect(snapshot.recentActivity.first?.detail == "Step 50")
    }

    // 14. Timestamps survive roundtrip
    @Test("Timestamps survive roundtrip with ISO8601 precision")
    func timestampsSurviveRoundtrip() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let original = makeSampleSnapshot()
        try store.save(original)

        let loaded = try store.load(sessionID: original.sessionID)
        let diffCreated = abs(loaded.createdAt.timeIntervalSince(original.createdAt))
        let diffUpdated = abs(loaded.updatedAt.timeIntervalSince(original.updatedAt))

        #expect(diffCreated < 1.0)
        #expect(diffUpdated < 1.0)
    }

    // 15. Role survives roundtrip
    @Test("All EmployeeRole cases survive roundtrip")
    func rolesSurviveRoundtrip() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        for role in EmployeeRole.allCases {
            let snapshot = makeSampleSnapshot(id: UUID(), role: role)
            try store.save(snapshot)
            let loaded = try store.load(sessionID: snapshot.sessionID)
            #expect(loaded.role == role)
        }
    }

    // 16. Routing information survives roundtrip
    @Test("Routing intelligence level and reason survive roundtrip")
    func routingInfoSurvivesRoundtrip() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(intelligenceLevel: .L4)
        try store.save(snapshot)

        let loaded = try store.load(sessionID: snapshot.sessionID)
        #expect(loaded.intelligenceLevel == .L4)
        #expect(loaded.routingReason == "Complex developer workflow")
    }

    // 17. Task statuses survive roundtrip
    @Test("All PersistedTaskStatus cases survive roundtrip")
    func taskStatusesSurviveRoundtrip() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let tasks = PersistedTaskStatus.allCases.enumerated().map { (index, status) in
            PersistedTaskSnapshot(
                taskID: UUID(),
                title: "Task for status \(status)",
                description: "Test description",
                order: index,
                status: status
            )
        }

        let snapshot = AgentSessionSnapshot(
            goalText: "Task status test",
            tasks: tasks
        )
        try store.save(snapshot)

        let loaded = try store.load(sessionID: snapshot.sessionID)
        for (index, status) in PersistedTaskStatus.allCases.enumerated() {
            #expect(loaded.tasks[index].status == status)
        }
    }

    // 18. Pending approval survives roundtrip
    @Test("Pending approval snapshot fields survive roundtrip")
    func pendingApprovalSurvivesRoundtrip() throws {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        let snapshot = makeSampleSnapshot(withApproval: true)
        try store.save(snapshot)

        let loaded = try store.load(sessionID: snapshot.sessionID)
        let loadedApproval = try #require(loaded.pendingApproval)
        let originalApproval = try #require(snapshot.pendingApproval)

        #expect(loadedApproval.requestID == originalApproval.requestID)
        #expect(loadedApproval.taskID == originalApproval.taskID)
        #expect(loadedApproval.toolID == originalApproval.toolID)
        #expect(loadedApproval.toolName == originalApproval.toolName)
        #expect(loadedApproval.riskLevel == originalApproval.riskLevel)
        #expect(loadedApproval.reason == originalApproval.reason)
        #expect(loadedApproval.status == originalApproval.status)
    }

    // 19. Tests never write to real DailyOps Application Support
    @Test("Tests use isolated temporary directories and never touch real Application Support")
    func testsNeverTouchRealApplicationSupport() {
        let (store, tempDir) = createTempStore()
        defer { cleanupTempStore(tempDir) }

        #expect(store.baseDirectory != AgentSessionStore.defaultBaseDirectory)
        #expect(store.baseDirectory.path.contains("DailyOpsTest_"))
        #expect(!store.baseDirectory.path.contains("Application Support/DailyOps/AgentSessions"))
    }

    // 20. Separate store instances remain isolated
    @Test("Separate store instances operate in complete isolation")
    func separateStoresRemainIsolated() throws {
        let (storeA, tempDirA) = createTempStore()
        let (storeB, tempDirB) = createTempStore()
        defer {
            cleanupTempStore(tempDirA)
            cleanupTempStore(tempDirB)
        }

        let snapshotA = makeSampleSnapshot()
        try storeA.save(snapshotA)

        #expect(throws: PersistenceError.self) {
            try storeB.load(sessionID: snapshotA.sessionID)
        }

        let snapshotB = makeSampleSnapshot()
        try storeB.saveActive(snapshotB)

        #expect(try storeA.loadActive() == nil)
        #expect(try storeB.loadActive()?.sessionID == snapshotB.sessionID)
    }
}
