import Foundation
@testable import KeyPathAppKit
import XCTest

final class QMKKeyboardDatabaseTests: XCTestCase {
    // MARK: - Error Description Tests

    func testNetworkErrorDescription() {
        let error = QMKDatabaseError.networkError("Connection refused")
        XCTAssertEqual(error.errorDescription, "Network error: Connection refused")
    }

    func testParseErrorDescription() {
        let error = QMKDatabaseError.parseError("Invalid JSON structure")
        XCTAssertEqual(error.errorDescription, "Parse error: Invalid JSON structure")
    }

    func testInvalidURLErrorDescription() {
        let error = QMKDatabaseError.invalidURL("Bad URL format")
        XCTAssertEqual(error.errorDescription, "Invalid URL: Bad URL format")
    }

    // MARK: - Index Entry Tests

    func testIndexEntryParsesFlatPath() {
        let entry = QMKKeyboardDatabase.IndexEntry(path: "crkbd")
        XCTAssertEqual(entry.path, "crkbd")
        XCTAssertEqual(entry.vendor, "crkbd")
        XCTAssertEqual(entry.components, ["crkbd"])
    }

    func testIndexEntryParsesNestedPath() {
        let entry = QMKKeyboardDatabase.IndexEntry(path: "mode/m65s")
        XCTAssertEqual(entry.path, "mode/m65s")
        XCTAssertEqual(entry.vendor, "mode")
        XCTAssertEqual(entry.components, ["mode", "m65s"])
    }

    func testIndexEntryParsesDeeplyNestedPath() {
        let entry = QMKKeyboardDatabase.IndexEntry(path: "keychron/q1/ansi/rgb")
        XCTAssertEqual(entry.vendor, "keychron")
        XCTAssertEqual(entry.components, ["keychron", "q1", "ansi", "rgb"])
    }

    // MARK: - Path Formatting Tests

    func testFormatPathCapitalizes() {
        XCTAssertEqual(QMKKeyboardDatabase.formatPath(["crkbd"]), "Crkbd")
        XCTAssertEqual(QMKKeyboardDatabase.formatPath(["mode", "m65s"]), "Mode M65s")
    }

    func testFormatPathFiltersRevisions() {
        XCTAssertEqual(QMKKeyboardDatabase.formatPath(["crkbd", "rev1"]), "Crkbd")
        XCTAssertEqual(QMKKeyboardDatabase.formatPath(["sofle", "rev1"]), "Sofle")
    }

    func testFormatPathFiltersMicrocontrollers() {
        XCTAssertEqual(QMKKeyboardDatabase.formatPath(["bastardkb", "charybdis", "rp2040"]), "Bastardkb Charybdis")
    }

    func testFormatPathKeepsAllWhenOnlyRevision() {
        // If filtering would leave nothing, keep all components
        XCTAssertEqual(QMKKeyboardDatabase.formatPath(["rev1"]), "Rev1")
    }

    // MARK: - Search Scoring Tests

    func testExactComponentMatchScoresHighest() {
        let score = QMKKeyboardDatabase.searchScore(
            query: "mode", name: "mode m65s", id: "mode/m65s", manufacturer: nil
        )
        XCTAssertEqual(score, 100)
    }

    func testPrefixMatchScoresHigh() {
        let score = QMKKeyboardDatabase.searchScore(
            query: "mod", name: "mode m65s", id: "mode/m65s", manufacturer: nil
        )
        XCTAssertEqual(score, 80)
    }

    func testSubstringMatchOnPathScoresLowerThanExact() {
        // "mode" is a prefix of "model_m" component → scores 80 (prefix match)
        // But "mode" as exact component in "mode/m65s" → scores 100
        let modelScore = QMKKeyboardDatabase.searchScore(
            query: "mode", name: "ibm model m", id: "ibm/model_m/del", manufacturer: "IBM"
        )
        let modeScore = QMKKeyboardDatabase.searchScore(
            query: "mode", name: "SixtyFive S", id: "mode/m65s", manufacturer: "Mode"
        )
        XCTAssertGreaterThan(modeScore, modelScore, "Exact component match should score higher than prefix match")
    }

    func testModeRanksAboveModelM() {
        let modeScore = QMKKeyboardDatabase.searchScore(
            query: "mode", name: "SixtyFive S", id: "mode/m65s", manufacturer: "Mode"
        )
        let modelMScore = QMKKeyboardDatabase.searchScore(
            query: "mode", name: "ibm model m", id: "ibm/model_m", manufacturer: "IBM"
        )
        XCTAssertGreaterThan(modeScore, modelMScore, "mode/m65s should rank above ibm/model_m for query 'mode'")
    }

    func testManufacturerPrefixMatch() {
        let score = QMKKeyboardDatabase.searchScore(
            query: "glor", name: "GMMK Pro", id: "gmmk/pro/rev1/ansi", manufacturer: "glorious"
        )
        XCTAssertEqual(score, 70)
    }

    func testNoMatchReturnsZero() {
        let score = QMKKeyboardDatabase.searchScore(
            query: "xyz", name: "Corne", id: "crkbd/rev1", manufacturer: "foostan"
        )
        XCTAssertEqual(score, 0)
    }

    // MARK: - Multi-Word Search Scoring Tests

    func testMultiWordAllWordsMustMatch() {
        let score = QMKKeyboardDatabase.multiWordScore(
            words: ["mode", "80"],
            name: "eighty",
            id: "mode/m80h",
            manufacturer: "Mode"
        )
        XCTAssertGreaterThan(score, 0, "'mode 80' should match mode/m80h")
    }

    func testMultiWordNoMatchIfOneWordMissing() {
        let score = QMKKeyboardDatabase.multiWordScore(
            words: ["mode", "xyz"],
            name: "eighty",
            id: "mode/m80h",
            manufacturer: "Mode"
        )
        XCTAssertEqual(score, 0, "Should not match if any word is missing")
    }

    func testMultiWordSingleWordDelegates() {
        let multi = QMKKeyboardDatabase.multiWordScore(
            words: ["mode"],
            name: "mode m65s",
            id: "mode/m65s",
            manufacturer: nil
        )
        let single = QMKKeyboardDatabase.searchScore(
            query: "mode", name: "mode m65s", id: "mode/m65s", manufacturer: nil
        )
        XCTAssertEqual(multi, single)
    }

    func testMultiWordScoreIsMinimum() {
        // "mode" matches exactly on component (100), "80" matches as substring on path (20)
        let score = QMKKeyboardDatabase.multiWordScore(
            words: ["mode", "80"],
            name: "eighty",
            id: "mode/m80h",
            manufacturer: "Mode"
        )
        // The weaker match (80 as substring) should pull the score down
        XCTAssertLessThanOrEqual(score, 100)
    }

    // MARK: - Search Integration Tests (with seeded data)

    func testSearchWithSeededIndexReturnsResults() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [
            .init(path: "crkbd/rev1"),
            .init(path: "mode/m65s"),
            .init(path: "planck/rev6"),
        ])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("crkbd")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "crkbd/rev1")
    }

    func testSearchByVendor() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [
            .init(path: "mode/m65s"),
            .init(path: "mode/m75h"),
            .init(path: "crkbd/rev1"),
        ])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("mode")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.id.hasPrefix("mode/") })
    }

    func testSearchUsesMetadataNames() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [.init(path: "crkbd/rev1")])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [
            "crkbd/rev1": .init(name: "Corne", manufacturer: "foostan"),
        ])

        let results = try await database.searchKeyboards("corne")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Corne")
        XCTAssertEqual(results.first?.manufacturer, "foostan")
    }

    func testBundledKeyboardsPrioritizedInSearch() async throws {
        let database = QMKKeyboardDatabase.shared

        let bundled = KeyboardMetadata(
            id: "crkbd/rev1",
            name: "Corne (crkbd)",
            manufacturer: "foostan",
            tags: ["split"],
            isBundled: true
        )
        await database.seedBundledKeyboards(with: [bundled])
        await database.seedIndex(with: [
            .init(path: "crkbd/rev1"),
            .init(path: "crkbd/rev4_0/mini"),
        ])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("crkbd")
        XCTAssertEqual(results.first?.id, "crkbd/rev1", "Bundled keyboard should be first")
        XCTAssertTrue(results.first?.isBundled == true)
    }

    func testEmptySearchReturnsBundledOnly() async throws {
        let database = QMKKeyboardDatabase.shared

        let bundled = [
            KeyboardMetadata(id: "crkbd/rev1", name: "Corne", isBundled: true),
            KeyboardMetadata(id: "sofle/rev1", name: "Sofle", isBundled: true),
        ]
        await database.seedBundledKeyboards(with: bundled)
        await database.seedIndex(with: [
            .init(path: "crkbd/rev1"),
            .init(path: "some-other-board"),
        ])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("")
        XCTAssertEqual(results.count, 2, "Empty query should return only bundled keyboards")
        XCTAssertTrue(results.allSatisfy(\.isBundled))
    }

    func testSearchResultsCappedAt50() async throws {
        let database = QMKKeyboardDatabase.shared

        let entries = (0 ..< 60).map {
            QMKKeyboardDatabase.IndexEntry(path: "test/board\($0)")
        }
        await database.seedIndex(with: entries)
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("test")
        XCTAssertEqual(results.count, 50, "Results should be capped at 50")
    }

    func testSearchIsCaseInsensitive() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [.init(path: "ErgoDox/ez")])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("ergodox")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchResultsRankedByRelevance() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [
            .init(path: "ibm/model_m"),
            .init(path: "mode/m65s"),
            .init(path: "mode/m75h"),
        ])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [
            "mode/m65s": .init(name: "SixtyFive S", manufacturer: "Mode"),
            "mode/m75h": .init(name: "SeventyFive H", manufacturer: "Mode"),
            "ibm/model_m": .init(name: "Model M", manufacturer: "IBM"),
        ])

        let results = try await database.searchKeyboards("mode")
        // mode/* should rank above ibm/model_m because "mode" is an exact component match
        XCTAssertTrue(results.first?.id.hasPrefix("mode/") ?? false,
                      "Mode keyboards should rank first, got: \(results.first?.id ?? "nil")")
    }

    // MARK: - Multi-Word Search Integration

    func testMultiWordSearchFindsResults() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [
            .init(path: "mode/m80h"),
            .init(path: "mode/m65s"),
            .init(path: "crkbd/rev1"),
        ])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [
            "mode/m80h": .init(name: "Eighty", manufacturer: "Mode"),
            "mode/m65s": .init(name: "SixtyFive S", manufacturer: "Mode"),
        ])

        let results = try await database.searchKeyboards("mode 80")
        XCTAssertEqual(results.count, 1, "Only mode/m80h should match 'mode 80'")
        XCTAssertEqual(results.first?.id, "mode/m80h")
    }

    func testMultiWordSearchExcludesPartialMatches() async throws {
        let database = QMKKeyboardDatabase.shared

        await database.seedIndex(with: [
            .init(path: "mode/m65s"),
            .init(path: "crkbd/rev1"),
        ])
        await database.seedBundledKeyboards(with: [])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("mode 80")
        XCTAssertEqual(results.count, 0, "'mode 80' should not match mode/m65s")
    }

    // MARK: - Legacy seedCache compatibility

    func testSeedCacheSetsBundledKeyboards() async throws {
        let database = QMKKeyboardDatabase.shared

        let kb = KeyboardMetadata(id: "legacy-test", name: "Legacy Board")
        await database.seedCache(with: [kb])
        await database.seedIndex(with: [])
        await database.seedMetadata(with: [:])

        let results = try await database.searchKeyboards("")
        XCTAssertTrue(results.contains { $0.id == "legacy-test" })
    }
}
