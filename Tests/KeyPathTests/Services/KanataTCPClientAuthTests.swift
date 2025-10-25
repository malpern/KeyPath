import XCTest
@testable import KeyPath

final class KanataTCPClientAuthTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
        // Ensure no token present
        let tokenPath = CommunicationSnapshot.tcpAuthTokenPath()
        try? FileManager.default.removeItem(atPath: tokenPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testValidateConfigAlwaysSucceedsForTCP() async {
        let client = KanataTCPClient(port: 37001)
        let result = await client.validateConfig("abcd")
        switch result { case .success: break; default: XCTFail("Expected .success") }
    }

    func testEnsureAuthenticatedUsesSharedToken() async {
        let client = KanataTCPClient(port: 37001)
        // No token -> false
        var ok = await client.ensureAuthenticated()
        XCTAssertFalse(ok)

        // Write token, then ensure auth should succeed (authenticate is client-side only for TCP)
        let token = "unit-test-token"
        XCTAssertTrue(CommunicationSnapshot.writeSharedTCPToken(token))
        ok = await client.ensureAuthenticated()
        XCTAssertTrue(ok)
    }
}

