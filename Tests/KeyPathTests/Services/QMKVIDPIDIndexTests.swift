@testable import KeyPathAppKit
import XCTest

final class KeyboardDetectionIndexTests: XCTestCase {
    override func setUp() {
        KeyboardDetectionIndex.resetCache()
    }

    override func tearDown() {
        KeyboardDetectionIndex.resetCache()
    }

    func testExactVIDPIDMatch() {
        KeyboardDetectionIndex.seedIndex(
            exactEntries: [
                .init(
                    matchKey: "4653:0001",
                    matchType: .exactVIDPID,
                    source: .via,
                    confidence: .high,
                    displayName: "Sofle",
                    manufacturer: nil,
                    qmkPath: "sofle/rev1",
                    builtInLayoutId: "sofle"
                )
            ],
            vendorFallbackEntries: [
                .init(
                    matchKey: "4653",
                    matchType: .vendorOnly,
                    source: .qmk,
                    confidence: .low,
                    displayName: "Sofle",
                    manufacturer: nil,
                    qmkPath: "sofle",
                    builtInLayoutId: "sofle"
                )
            ]
        )

        let match = KeyboardDetectionIndex.lookup(vendorID: 0x4653, productID: 0x0001)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchType, .exactVIDPID)
        XCTAssertEqual(match?.record.qmkPath, "sofle/rev1")
        XCTAssertEqual(match?.record.source, .via)
    }

    func testVIDOnlyFallback() {
        KeyboardDetectionIndex.seedIndex(
            exactEntries: [],
            vendorFallbackEntries: [
                .init(
                    matchKey: "4653",
                    matchType: .vendorOnly,
                    source: .qmk,
                    confidence: .low,
                    displayName: "Sofle",
                    manufacturer: nil,
                    qmkPath: "sofle",
                    builtInLayoutId: "sofle"
                )
            ]
        )

        let match = KeyboardDetectionIndex.lookup(vendorID: 0x4653, productID: 0x9999)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchType, .vendorOnly)
        XCTAssertEqual(match?.record.qmkPath, "sofle")
        XCTAssertEqual(match?.record.confidence, .low)
    }

    func testNoMatch() {
        KeyboardDetectionIndex.seedIndex(exactEntries: [])

        let match = KeyboardDetectionIndex.lookup(vendorID: 0x0000, productID: 0x0000)
        XCTAssertNil(match)
    }

    func testExactMatchTakesPriorityOverVIDOnly() {
        KeyboardDetectionIndex.seedIndex(
            exactEntries: [
                .init(
                    matchKey: "CB10:1256",
                    matchType: .exactVIDPID,
                    source: .via,
                    confidence: .high,
                    displayName: "Corne Keyboard",
                    manufacturer: nil,
                    qmkPath: "crkbd/rev4_0/standard",
                    builtInLayoutId: "corne"
                )
            ],
            vendorFallbackEntries: [
                .init(
                    matchKey: "CB10",
                    matchType: .vendorOnly,
                    source: .qmk,
                    confidence: .low,
                    displayName: "Corne",
                    manufacturer: nil,
                    qmkPath: "crkbd",
                    builtInLayoutId: "corne"
                )
            ]
        )

        let match = KeyboardDetectionIndex.lookup(vendorID: 0xCB10, productID: 0x1256)
        XCTAssertEqual(match?.matchType, .exactVIDPID)
        XCTAssertEqual(match?.record.qmkPath, "crkbd/rev4_0/standard")
    }

    func testFormatKey() {
        XCTAssertEqual(KeyboardDetectionIndex.formatKey(vendorID: 0x4653, productID: 0x0001), "4653:0001")
        XCTAssertEqual(KeyboardDetectionIndex.formatKey(vendorID: 0x05AC, productID: 0x0342), "05AC:0342")
    }

    func testFormatVIDKey() {
        XCTAssertEqual(KeyboardDetectionIndex.formatVIDKey(vendorID: 0x4653), "4653")
        XCTAssertEqual(KeyboardDetectionIndex.formatVIDKey(vendorID: 0x05AC), "05AC")
    }

    func testEmptyIndex() {
        KeyboardDetectionIndex.seedIndex(exactEntries: [])

        let match = KeyboardDetectionIndex.lookup(vendorID: 0x4653, productID: 0x0001)
        XCTAssertNil(match)
    }
}
