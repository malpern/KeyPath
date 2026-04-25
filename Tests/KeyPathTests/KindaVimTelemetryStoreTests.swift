@testable import KeyPathAppKit
import XCTest

/// Tests for the local-only telemetry store. Uses a temp file URL and
/// an isolated UserDefaults suite per test so we never touch real
/// Application Support or the production opt-in flag.
///
/// Note: not class-level `@MainActor`. XCTestCase's `setUp`/`tearDown`
/// are nonisolated, and CI's strict concurrency rejects mutations of
/// MainActor-isolated stored properties from those overrides. Test
/// methods call into the MainActor-isolated `KindaVimTelemetryStore`
/// via short `MainActor.assumeIsolated` blocks.
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

    @MainActor
    private func makeStore() -> KindaVimTelemetryStore {
        KindaVimTelemetryStore(fileURL: tempFileURL, userDefaults: defaults)
    }

    // MARK: - Opt-in gate

    @MainActor func testRecordingIsNoOpWhenOptOut() {
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

    @MainActor func testCommandFrequencyAccumulates() {
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

    @MainActor func testModeDwellAccumulates() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordModeDwell("normal", duration: 5)
        store.recordModeDwell("normal", duration: 3)
        store.recordModeDwell("insert", duration: 100)

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.modeDwellSeconds["normal"], 8)
        XCTAssertEqual(snapshot.modeDwellSeconds["insert"], 100)
    }

    @MainActor func testZeroOrNegativeDurationIsIgnored() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordModeDwell("normal", duration: 0)
        store.recordModeDwell("normal", duration: -3)

        let snapshot = store.loadSnapshot()
        XCTAssertNil(snapshot.modeDwellSeconds["normal"])
    }

    @MainActor func testStrategySampleCounts() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()

        store.recordStrategySample("accessibility")
        store.recordStrategySample("accessibility")
        store.recordStrategySample("keyboard")

        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.strategySamples["accessibility"], 2)
        XCTAssertEqual(snapshot.strategySamples["keyboard"], 1)
    }

    @MainActor func testOperatorPendingExitClassification() {
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

    @MainActor func testRoundtripThroughDisk() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)

        do {
            let storeA = makeStore()
            storeA.recordCommand("h")
            storeA.recordModeDwell("normal", duration: 12)
            storeA.flushNow()  // force the debounced write before storeA goes away
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

    @MainActor func testClearAllWipesFileAndCache() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        store.recordCommand("h")
        store.flushNow()  // force the debounced write
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))

        store.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path),
                       "clearAll should remove the file")
        let snapshot = store.loadSnapshot()
        XCTAssertTrue(snapshot.commandFrequency.isEmpty,
                      "After clear, snapshot should be empty (and cache cleared)")
    }

    // MARK: - Non-vim navigation + daily snapshots

    @MainActor func testNonVimNavigationCounterIncrements() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        store.recordNonVimNavigation("left")
        store.recordNonVimNavigation("LEFT")  // case-insensitive
        store.recordNonVimNavigation("right")
        let snap = store.loadSnapshot()
        XCTAssertEqual(snap.nonVimNavigationFrequency["left"], 2)
        XCTAssertEqual(snap.nonVimNavigationFrequency["right"], 1)
    }

    @MainActor func testHjklRecordingPopulatesDailyHjklCount() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        store.recordCommand("h")
        store.recordCommand("h")
        store.recordCommand("j")
        store.recordCommand("w")  // not hjkl, doesn't count toward daily hjkl
        let snap = store.loadSnapshot()
        XCTAssertEqual(snap.dailySnapshots.count, 1)
        XCTAssertEqual(snap.dailySnapshots.last?.hjklCount, 3)
    }

    @MainActor func testArrowsAccumulateInDailySnapshot() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        store.recordNonVimNavigation("left")
        store.recordNonVimNavigation("up")
        store.recordNonVimNavigation("up")
        let snap = store.loadSnapshot()
        XCTAssertEqual(snap.dailySnapshots.last?.nonVimNavigationCount, 3)
    }

    @MainActor func testVocabularySizeUpdatesAfterTenPresses() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        // 9 presses of `h` — not yet fluent
        for _ in 0..<9 { store.recordCommand("h") }
        XCTAssertEqual(store.loadSnapshot().dailySnapshots.last?.vocabularySize, 0)

        // 10th press crosses the threshold
        store.recordCommand("h")
        XCTAssertEqual(store.loadSnapshot().dailySnapshots.last?.vocabularySize, 1)
    }

    @MainActor func testDailySnapshotMergesSameDayWrites() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        store.recordCommand("h")
        store.recordNonVimNavigation("left")
        store.recordModeDwell("normal", duration: 5)
        // All recorded same day — should be one daily entry, not three
        XCTAssertEqual(store.loadSnapshot().dailySnapshots.count, 1)
    }

    // MARK: - Schema migration (forward-compat with old files)

    @MainActor func testDecodesOldFileWithoutNewFields() throws {
        // Simulate a file written by the original PR #328 store: no
        // nonVimNavigationFrequency, no dailySnapshots.
        let legacyJSON = """
        {
          "commandFrequency": { "h": 5 },
          "modeDwellSeconds": { "normal": 12 },
          "strategySamples": {},
          "operatorPendingCompleted": 0,
          "operatorPendingCancelled": 0
        }
        """
        try legacyJSON.write(to: tempFileURL, atomically: true, encoding: .utf8)

        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = makeStore()
        let snap = store.loadSnapshot()
        XCTAssertEqual(snap.commandFrequency["h"], 5)
        XCTAssertEqual(snap.nonVimNavigationFrequency, [:])
        XCTAssertEqual(snap.dailySnapshots, [])
    }

    // MARK: - Debounced flush

    @MainActor func testRecordingWithoutFlushDoesNotWriteImmediately() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = KindaVimTelemetryStore(
            fileURL: tempFileURL,
            userDefaults: defaults,
            flushInterval: 60  // long enough that the debounce won't fire
        )
        store.recordCommand("h")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path),
                       "Disk write should be debounced")
    }

    @MainActor func testFlushNowForcesWriteSynchronously() {
        defaults.set(true, forKey: KindaVimTelemetryStore.optInKey)
        let store = KindaVimTelemetryStore(
            fileURL: tempFileURL,
            userDefaults: defaults,
            flushInterval: 60
        )
        store.recordCommand("h")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
        store.flushNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFileURL.path))
    }

    // MARK: - Missing file is harmless

    @MainActor func testLoadSnapshotWithNoFileReturnsEmpty() {
        let store = makeStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFileURL.path))
        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot, KindaVimTelemetrySnapshot())
    }
}
