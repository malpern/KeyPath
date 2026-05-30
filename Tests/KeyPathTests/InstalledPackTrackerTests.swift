@testable import KeyPathAppKit
import XCTest

final class InstalledPackTrackerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledPackTrackerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeTracker() -> InstalledPackTracker {
        let fileURL = tempDir.appendingPathComponent("installed-packs.json")
        return InstalledPackTracker(fileURL: fileURL)
    }

    // MARK: - Empty state

    func testEmptyTracker_AllInstalledReturnsEmpty() async {
        let tracker = makeTracker()
        let all = await tracker.allInstalled()
        XCTAssertTrue(all.isEmpty)
    }

    func testEmptyTracker_IsInstalledReturnsFalse() async {
        let tracker = makeTracker()
        let installed = await tracker.isInstalled(packID: "com.keypath.pack.test")
        XCTAssertFalse(installed)
    }

    func testEmptyTracker_RecordReturnsNil() async {
        let tracker = makeTracker()
        let record = await tracker.record(for: "com.keypath.pack.test")
        XCTAssertNil(record)
    }

    // MARK: - Upsert and query

    func testUpsert_MakesPackInstalled() async throws {
        let tracker = makeTracker()
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.test",
            version: "1.0.0",
            installedAt: Date()
        )
        try await tracker.upsert(record)

        let isInstalled = await tracker.isInstalled(packID: "com.keypath.pack.test")
        XCTAssertTrue(isInstalled)
    }

    func testUpsert_RecordRetrievable() async throws {
        let tracker = makeTracker()
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.test",
            version: "2.0.0",
            quickSettingValues: ["holdTimeout": 200]
        )
        try await tracker.upsert(record)

        let fetched = await tracker.record(for: "com.keypath.pack.test")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.version, "2.0.0")
        XCTAssertEqual(fetched?.quickSettingValues["holdTimeout"], 200)
    }

    func testUpsert_OverwritesExistingRecord() async throws {
        let tracker = makeTracker()
        let v1 = InstalledPackRecord(packID: "com.keypath.pack.test", version: "1.0.0")
        try await tracker.upsert(v1)

        let v2 = InstalledPackRecord(packID: "com.keypath.pack.test", version: "2.0.0")
        try await tracker.upsert(v2)

        let fetched = await tracker.record(for: "com.keypath.pack.test")
        XCTAssertEqual(fetched?.version, "2.0.0")

        let all = await tracker.allInstalled()
        XCTAssertEqual(all.count, 1)
    }

    func testMultipleUpserts_AllInstalledReturnsSortedByDate() async throws {
        let tracker = makeTracker()
        let older = InstalledPackRecord(
            packID: "com.keypath.pack.old",
            version: "1.0.0",
            installedAt: Date(timeIntervalSinceNow: -3600)
        )
        let newer = InstalledPackRecord(
            packID: "com.keypath.pack.new",
            version: "1.0.0",
            installedAt: Date()
        )
        try await tracker.upsert(older)
        try await tracker.upsert(newer)

        let all = await tracker.allInstalled()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.packID, "com.keypath.pack.new")
        XCTAssertEqual(all.last?.packID, "com.keypath.pack.old")
    }

    // MARK: - Remove

    func testRemove_MakesPackNotInstalled() async throws {
        let tracker = makeTracker()
        let record = InstalledPackRecord(packID: "com.keypath.pack.test", version: "1.0.0")
        try await tracker.upsert(record)
        try await tracker.remove(packID: "com.keypath.pack.test")

        let isInstalled = await tracker.isInstalled(packID: "com.keypath.pack.test")
        XCTAssertFalse(isInstalled)
    }

    func testRemove_NonexistentPackDoesNotThrow() async throws {
        let tracker = makeTracker()
        try await tracker.remove(packID: "com.keypath.pack.nonexistent")
    }

    // MARK: - Persistence round-trip

    func testPersistence_SurvivesNewTrackerInstance() async throws {
        let fileURL = tempDir.appendingPathComponent("installed-packs.json")
        let tracker1 = InstalledPackTracker(fileURL: fileURL)
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.persisted",
            version: "1.0.0",
            quickSettingValues: ["holdTimeout": 250]
        )
        try await tracker1.upsert(record)

        let tracker2 = InstalledPackTracker(fileURL: fileURL)
        let fetched = await tracker2.record(for: "com.keypath.pack.persisted")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.version, "1.0.0")
        XCTAssertEqual(fetched?.quickSettingValues["holdTimeout"], 250)
    }

    func testPersistence_RemovalPersists() async throws {
        let fileURL = tempDir.appendingPathComponent("installed-packs.json")
        let tracker1 = InstalledPackTracker(fileURL: fileURL)
        try await tracker1.upsert(InstalledPackRecord(packID: "com.keypath.pack.a", version: "1.0.0"))
        try await tracker1.upsert(InstalledPackRecord(packID: "com.keypath.pack.b", version: "1.0.0"))
        try await tracker1.remove(packID: "com.keypath.pack.a")

        let tracker2 = InstalledPackTracker(fileURL: fileURL)
        let all = await tracker2.allInstalled()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.packID, "com.keypath.pack.b")
    }

    func testPersistence_CorruptFileStartsFresh() async throws {
        let fileURL = tempDir.appendingPathComponent("installed-packs.json")
        try "this is not valid json!!!".write(to: fileURL, atomically: true, encoding: .utf8)

        let tracker = InstalledPackTracker(fileURL: fileURL)
        let all = await tracker.allInstalled()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - InstalledPackRecord Codable

    func testInstalledPackRecordCodableRoundTrip() throws {
        let original = InstalledPackRecord(
            packID: "com.keypath.pack.test",
            version: "1.0.0",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            quickSettingValues: ["holdTimeout": 200, "speed": 5]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InstalledPackRecord.self, from: data)

        XCTAssertEqual(decoded.packID, original.packID)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.quickSettingValues, original.quickSettingValues)
    }

    func testInstalledPackRecordEquality() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = InstalledPackRecord(packID: "x", version: "1", installedAt: date, quickSettingValues: ["k": 1])
        let b = InstalledPackRecord(packID: "x", version: "1", installedAt: date, quickSettingValues: ["k": 1])
        let c = InstalledPackRecord(packID: "x", version: "2", installedAt: date, quickSettingValues: ["k": 1])

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
