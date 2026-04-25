@testable import KeyPathAppKit
import XCTest

/// Tests for the local-only telemetry store. Uses a temp file URL and
/// an isolated UserDefaults suite per test so we never touch real
/// Application Support or the production opt-in flag.
@MainActor
final class KindaVimTelemetryStoreTests: XCTestCase {
    private var tempFileURL: URL!
    private var defaults: UserDefaults!

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kindavim-telemetry-\(UUID().uuidString).json")

        // Per-test UserDefaults suite so the opt-in flag doesn't leak
        // between tests (and never touches the user's real prefs).
        suiteName = "KindaVimTelemetryStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        defaults?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> KindaVimTelemetryStore {
        KindaVimTelemetryStore(fileURL: tempFileURL, userDefaults: defaults)
    }

    // MARK: - Opt-in gate

    func testRecordingIsNoOpWhenOptOut() {
        let store = makeStore()
        XCTAssertFalse(store.isEnabled, "Should default to off")

        store.recordCommand("h")
        store.recordModeDwell("normal", duration: 5)
        store.recordStrategySample("accessibility")
        store.recordOperatorPendingExit(completed: true)

        let snapshot = store.loadSnapshot()
        XCTAssertTrue(snapshot.commandFrequency.isEmpty)
        XCTAssertTrue(snapshot.modeDwellSeconds.isEmpty)
        XCTAssertTrue(snapshot.strategySamples.isEmpty)
        XCTAssertEqual(snapshot.operatorPendingCompleted, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path),
                       "Should not have written anything to disk while opted out")
    }

    // MARK: - Recording (opted in)

    func testCommandFrequencyAccumulates() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordCommand("h")
        store.recordCommand("h")
        store.recordCommand("J")  // case-insensitive
        store.recordCommand("k")

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.commandFrequency["h"], 2)
        XCTAssertEqual(snapshot.commandFrequency["j"], 1, "should lowercase")
        XCTAssertEqual(snapshot.commandFrequency["k"], 1)
    }

    func testModeDwellAccumulates() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordModeDwell("normal", duration: 5)
        store.recordModeDwell("normal", duration: 3)
        store.recordModeDwell("insert", duration: 100)

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.modeDwellSeconds["normal"], 8)
        XCTAssertEqual(snapshot.modeDwellSeconds["insert"], 100)
    }

    func testZeroOrNegativeDurationIsIgnored() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordModeDwell("normal", duration: 0)
        store.recordModeDwell("normal", duration: -3)

        let snapshot = store.loadSnapshot()
        XCTAssertNil(snapshot.modeDwellSeconds["normal"])
    }

    func testStrategySampleCounts() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordStrategySample("accessibility")
        store.recordStrategySample("accessibility")
        store.recordStrategySample("keyboard")

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.strategySamples["accessibility"], 2)
        XCTAssertEqual(snapshot.strategySamples["keyboard"], 1)
    }

    func testOperatorPendingExitClassification() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordOperatorPendingExit(completed: true)
        store.recordOperatorPendingExit(completed: true)
        store.recordOperatorPendingExit(completed: false)

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.operatorPendingCompleted, 2)
        XCTAssertEqual(snapshot.operatorPendingCancelled, 1)
    }

    // MARK: - Persistence + roundtrip

    func testRoundtripThroughDisk() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)

        do {
            let storeA = makeStore()
            storeA.recordCommand("h")
            storeA.recordModeDwell("normal", duration: 12)
        }

        // New store instance reading the same file should see the data.
        let storeB = makeStore()
        let snapshot = storeB.loadSnapshot()
        XCTAssertEqual(snapshot.commandFrequency["h"], 1)
        XCTAssertEqual(snapshot.modeDwellSeconds["normal"], 12)
        XCTAssertNotNil(snapshot.firstRecordedAt)
        XCTAssertNotNil(snapshot.lastUpdatedAt)
    }

    // MARK: - Clear

    func testClearAllWipesFileAndCache() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        store.recordCommand("h")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        store.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path),
                       "clearAll should remove the file")
        let snapshot = store.loadSnapshot()
        XCTAssertTrue(snapshot.commandFrequency.isEmpty,
                      "After clear, snapshot should be empty (and cache cleared)")
    }

    // MARK: - Missing file is harmless

    func testLoadSnapshotWithNoFileReturnsEmpty() {
        let store = makeStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot, KindaVimTelemetrySnapshot())
    }
}
