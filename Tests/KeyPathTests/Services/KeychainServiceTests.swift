import XCTest
@testable import KeyPath

@MainActor
final class KeychainServiceTests: XCTestCase {
    override func setUp() async throws {
        // Clean any prior value; ignore errors if not present
        try? KeychainService.shared.deleteTCPToken()
    }

    func testStoreRetrieveDeleteTCPToken() throws {
        // Initially absent
        XCTAssertFalse(KeychainService.shared.hasTCPToken)
        XCTAssertNil(try KeychainService.shared.retrieveTCPToken())

        // Store
        let token = "unit-test-token-\(UUID().uuidString)"
        try KeychainService.shared.storeTCPToken(token)
        XCTAssertTrue(KeychainService.shared.hasTCPToken)

        // Retrieve
        let loaded = try KeychainService.shared.retrieveTCPToken()
        XCTAssertEqual(loaded, token)

        // Delete
        try KeychainService.shared.deleteTCPToken()
        XCTAssertFalse(KeychainService.shared.hasTCPToken)
        XCTAssertNil(try KeychainService.shared.retrieveTCPToken())
    }
}

