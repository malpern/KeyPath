import XCTest
@testable import KeyPathAppKit

final class KeychainServiceTests: XCTestCase {
    func testKeychainServiceSourceHasNoUDPLegacyReferences() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = root.appendingPathComponent("Sources/KeyPathAppKit/Services/KeychainService.swift")
        let contents = try String(contentsOf: sourceURL)

        XCTAssertFalse(
            contents.localizedCaseInsensitiveContains("udp"),
            "KeychainService.swift should not reference UDP after TCP migration"
        )
    }

    func testCommunicationConfigDescriptionMentionsTCPAndPort() {
        let prefs = PreferencesService()
        let originalPort = prefs.tcpServerPort
        defer { prefs.tcpServerPort = originalPort }

        prefs.tcpServerPort = 42424

        let description = prefs.communicationConfigDescription
        XCTAssertTrue(description.contains("TCP"), "Description should mention TCP transport")
        XCTAssertTrue(description.contains("42424"), "Description should include the configured port")
        XCTAssertTrue(
            description.localizedCaseInsensitiveContains("no authentication"),
            "Description should mention the current no-auth status"
        )
    }
}
