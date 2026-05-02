import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class KindaVimStateAdapterTests: XCTestCase {
    func testParseModeFromValidPayload() throws {
        let data = try XCTUnwrap(#"{"mode":"insert"}"#.data(using: .utf8))
        XCTAssertEqual(KindaVimStateAdapter.parseMode(from: data), "insert")
    }

    func testParseModeFromInvalidPayloadReturnsNil() throws {
        let data = try XCTUnwrap(#"{"not_mode":"insert"}"#.data(using: .utf8))
        XCTAssertNil(KindaVimStateAdapter.parseMode(from: data))
    }

    func testNormalizedModeMapping() {
        XCTAssertEqual(KindaVimStateAdapter.normalizedMode(from: "insert"), .insert)
        XCTAssertEqual(KindaVimStateAdapter.normalizedMode(from: "normal"), .normal)
        XCTAssertEqual(KindaVimStateAdapter.normalizedMode(from: "visual"), .visual)
        XCTAssertEqual(KindaVimStateAdapter.normalizedMode(from: "visual line"), .visual)
        XCTAssertEqual(KindaVimStateAdapter.normalizedMode(from: nil), .unknown)
        XCTAssertEqual(KindaVimStateAdapter.normalizedMode(from: "operator_pending"), .operatorPending)
    }

    func testValidJSONEmitsJSONStateWithHighConfidence() async throws {
        let fileURL = try makeTempEnvironmentFile(contents: #"{"mode":"normal"}"#)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let adapter = KindaVimStateAdapter(
            environmentURL: fileURL,
            nowProvider: { now }
        )

        await adapter.refreshForTesting()

        XCTAssertEqual(adapter.state.mode, .normal)
        XCTAssertEqual(adapter.state.source, .json)
        XCTAssertEqual(adapter.state.confidence, .high)
        XCTAssertFalse(adapter.state.isStale)
        XCTAssertEqual(adapter.state.timestamp, now)
    }

    func testMalformedJSONFallsBackToUnknown() async throws {
        let fileURL = try makeTempEnvironmentFile(contents: #"{"mode":"nor"#)
        let adapter = KindaVimStateAdapter(
            environmentURL: fileURL,
            nowProvider: Date.init
        )

        await adapter.refreshForTesting()

        XCTAssertEqual(adapter.state.mode, .unknown)
        XCTAssertEqual(adapter.state.source, .fallback)
        XCTAssertEqual(adapter.state.confidence, .low)
        XCTAssertTrue(adapter.state.isStale)
    }

    func testStalenessMarksJSONStateWithoutChangingMode() async throws {
        let fileURL = try makeTempEnvironmentFile(contents: #"{"mode":"visual"}"#)
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let adapter = KindaVimStateAdapter(
            environmentURL: fileURL,
            nowProvider: { now }
        )

        await adapter.refreshForTesting()
        XCTAssertEqual(adapter.state.mode, .visual)
        XCTAssertFalse(adapter.state.isStale)

        now = now.addingTimeInterval(6)
        adapter.evaluateStalenessForTesting()

        XCTAssertEqual(adapter.state.mode, .visual)
        XCTAssertEqual(adapter.state.source, .json)
        XCTAssertTrue(adapter.state.isStale)
    }

    func testRefreshDeduplicatesUnchangedModeEvents() async throws {
        let fileURL = try makeTempEnvironmentFile(contents: #"{"mode":"insert"}"#)
        let adapter = KindaVimStateAdapter(
            environmentURL: fileURL,
            nowProvider: Date.init
        )

        await adapter.refreshForTesting()
        let baselineSequence = adapter.updateSequence

        await adapter.refreshForTesting()
        await adapter.refreshForTesting()

        XCTAssertEqual(adapter.state.mode, .insert)
        XCTAssertEqual(adapter.updateSequence, baselineSequence)
    }

    func testMissingFileFallsBackToUnknown() async {
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("environment.json")

        let adapter = KindaVimStateAdapter(
            environmentURL: missingURL,
            nowProvider: Date.init
        )

        await adapter.refreshForTesting()

        XCTAssertFalse(adapter.isEnvironmentFilePresent)
        XCTAssertEqual(adapter.state.mode, .unknown)
        XCTAssertEqual(adapter.state.source, .fallback)
        XCTAssertTrue(adapter.state.isStale)
    }

    private func makeTempEnvironmentFile(contents: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("environment.json")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
