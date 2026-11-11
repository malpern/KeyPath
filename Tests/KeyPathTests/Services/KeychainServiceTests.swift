@testable import KeyPathAppKit
@preconcurrency import XCTest

final class KeychainServiceTests: XCTestCase {
    func testKeychainServiceSourceHasNoUDPLegacyReferences() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = root.appendingPathComponent("Sources/KeyPathAppKit/Services/System/KeychainService.swift")
        let contents = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            contents.localizedCaseInsensitiveContains("udp"),
            "KeychainService.swift should not reference UDP after TCP migration"
        )
    }

    func testCommunicationConfigDescriptionNamesTheOwnerCheckedSocket() {
        let description = PreferencesService().communicationConfigDescription
        XCTAssertTrue(description.contains("owner-checked"))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("no authentication"))
    }
}
