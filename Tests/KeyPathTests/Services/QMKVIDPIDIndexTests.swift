@testable import KeyPathAppKit
import XCTest

final class QMKVIDPIDIndexTests: XCTestCase {
    override func setUp() {
        QMKVIDPIDIndex.resetCache()
    }

    override func tearDown() {
        QMKVIDPIDIndex.resetCache()
    }

    func testExactVIDPIDMatch() {
        QMKVIDPIDIndex.seededEntries = [
            "4653:0001": ["sofle/rev1"],
            "4653": ["sofle", "sofle/rev1", "sofle/keyhive"],
        ]

        let match = QMKVIDPIDIndex.lookup(vendorID: 0x4653, productID: 0x0001)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchType, .exactVIDPID)
        XCTAssertEqual(match?.keyboardPaths, ["sofle/rev1"])
    }

    func testVIDOnlyFallback() {
        QMKVIDPIDIndex.seededEntries = [
            "4653": ["sofle", "sofle/rev1"],
        ]

        // Unknown PID but known VID
        let match = QMKVIDPIDIndex.lookup(vendorID: 0x4653, productID: 0x9999)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchType, .vidOnly)
        XCTAssertEqual(match?.keyboardPaths, ["sofle", "sofle/rev1"])
    }

    func testNoMatch() {
        QMKVIDPIDIndex.seededEntries = [
            "4653:0001": ["sofle/rev1"],
        ]

        let match = QMKVIDPIDIndex.lookup(vendorID: 0x0000, productID: 0x0000)
        XCTAssertNil(match)
    }

    func testExactMatchTakesPriorityOverVIDOnly() {
        QMKVIDPIDIndex.seededEntries = [
            "CB10:1256": ["crkbd/rev4_0/standard"],
            "CB10": ["crkbd", "crkbd/rev1", "crkbd/r2g"],
        ]

        let match = QMKVIDPIDIndex.lookup(vendorID: 0xCB10, productID: 0x1256)
        XCTAssertEqual(match?.matchType, .exactVIDPID)
        XCTAssertEqual(match?.keyboardPaths, ["crkbd/rev4_0/standard"])
    }

    func testFormatKey() {
        XCTAssertEqual(QMKVIDPIDIndex.formatKey(vendorID: 0x4653, productID: 0x0001), "4653:0001")
        XCTAssertEqual(QMKVIDPIDIndex.formatKey(vendorID: 0x05AC, productID: 0x0342), "05AC:0342")
    }

    func testFormatVIDKey() {
        XCTAssertEqual(QMKVIDPIDIndex.formatVIDKey(vendorID: 0x4653), "4653")
        XCTAssertEqual(QMKVIDPIDIndex.formatVIDKey(vendorID: 0x05AC), "05AC")
    }

    func testEmptyIndex() {
        QMKVIDPIDIndex.seededEntries = [:]

        let match = QMKVIDPIDIndex.lookup(vendorID: 0x4653, productID: 0x0001)
        XCTAssertNil(match)
    }
}

// MARK: - MatchType Equatable

extension QMKVIDPIDIndex.MatchType: @retroactive Equatable {
    public static func == (lhs: QMKVIDPIDIndex.MatchType, rhs: QMKVIDPIDIndex.MatchType) -> Bool {
        switch (lhs, rhs) {
        case (.exactVIDPID, .exactVIDPID): true
        case (.vidOnly, .vidOnly): true
        default: false
        }
    }
}
