import XCTest
import SwiftData
@testable import DailyOps

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testHistoryStoreDefaultInitialization() {
        let store = HistoryStore()
        XCTAssertNotNil(store.container)
        XCTAssertNil(store.initializationError)
        XCTAssertTrue(store.isPersistent)
    }

    func testHistoryStoreWithInjectedInMemoryContainer() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationEntry.self, configurations: config)
        let store = HistoryStore(container: container)

        XCTAssertFalse(store.isPersistent, "In-memory container must report isPersistent == false")
        XCTAssertNil(store.initializationError)

        store.record(raw: "Testing 1 2 3", cleaned: "Testing 1, 2, 3.", duration: 1.5, appName: "TextEdit")

        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try store.container.mainContext.fetch(descriptor)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.raw, "Testing 1 2 3")
        XCTAssertEqual(entries.first?.cleaned, "Testing 1, 2, 3.")
        XCTAssertEqual(entries.first?.appName, "TextEdit")
    }

    func testHistoryStoreFallbackOnInitializationFailure() throws {
        let expectedError = NSError(domain: "com.akshaywesley.DailyOps.test.sqlite", code: 999, userInfo: [NSLocalizedDescriptionKey: "Simulated SQLite failure"])
        let store = HistoryStore(containerProvider: { throw expectedError })

        XCTAssertFalse(store.isPersistent, "Fallback store must report isPersistent == false")
        XCTAssertNotNil(store.initializationError, "initializationError must report the root cause error")
        XCTAssertEqual((store.initializationError as? NSError)?.code, 999)

        // Store remains usable in-memory during the current session
        store.record(raw: "In-memory raw", cleaned: "In-memory cleaned.", duration: 1.0, appName: "Safari")

        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try store.container.mainContext.fetch(descriptor)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.raw, "In-memory raw")
        XCTAssertEqual(entries.first?.cleaned, "In-memory cleaned.")

        store.deleteAll()
        let postDeleteEntries = try store.container.mainContext.fetch(descriptor)
        XCTAssertEqual(postDeleteEntries.count, 0)
    }

    func testHistoryStoreDeleteAll() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DictationEntry.self, configurations: config)
        let store = HistoryStore(container: container)

        store.record(raw: "First", cleaned: "First.", duration: 1.0, appName: "Notes")
        store.record(raw: "Second", cleaned: "Second.", duration: 2.0, appName: "Notes")

        let descriptor = FetchDescriptor<DictationEntry>()
        var entries = try store.container.mainContext.fetch(descriptor)
        XCTAssertEqual(entries.count, 2)

        store.deleteAll()

        entries = try store.container.mainContext.fetch(descriptor)
        XCTAssertEqual(entries.count, 0)
    }
}
