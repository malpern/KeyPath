import XCTest
@testable import KeyPath

final class TCPAuthTokenManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear any persisted token
        TCPAuthTokenManager.clearToken()
    }

    func testGenerateTokenProducesBase64LikeString() {
        let token = TCPAuthTokenManager.generateToken()
        XCTAssertFalse(token.isEmpty)
        // Should be URL-safe-ish when later transformed; here just ensure ASCII
        XCTAssertNil(token.first { $0.unicodeScalars.contains { !$0.isASCII } })
    }

    func testGetOrCreateRoundTrip() {
        let t1 = TCPAuthTokenManager.getOrCreateToken()
        let t2 = TCPAuthTokenManager.getOrCreateToken()
        XCTAssertEqual(t1, t2, "Second call should return same stored token")
    }

    func testSetAndClearToken() async {
        let custom = "custom-token"
        TCPAuthTokenManager.setToken(custom)
        XCTAssertEqual(TCPAuthTokenManager.getOrCreateToken(), custom)
        TCPAuthTokenManager.clearToken()
        let newToken = TCPAuthTokenManager.getOrCreateToken()
        XCTAssertFalse(newToken.isEmpty)
        XCTAssertNotEqual(newToken, custom)
    }
}

