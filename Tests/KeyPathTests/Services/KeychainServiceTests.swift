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

    func testCommunicationConfigDescriptionMentionsTCPAndPort() {
        let prefs = PreferencesService()
        let description = prefs.communicationConfigDescription
        XCTAssertTrue(description.contains("TCP"), "Description should mention TCP transport")
        XCTAssertTrue(description.contains("37001"), "Description should include the fixed driverless session port")
        XCTAssertTrue(
            description.localizedCaseInsensitiveContains("no authentication"),
            "Description should mention the current no-auth status"
        )
    }
}
