import Foundation
@testable import KeyPath
import Network
import XCTest

/// Simplified tests for KanataUDPClient - focused on core functionality
///
/// Design: Tests the simplified localhost IPC client, not distributed networking features.
/// Most tests expect failure without a running UDP server - that's normal and correct.
class KanataUDPClientTests: XCTestCase {
    // MARK: - Initialization Tests

    func testClientCreation() {
        let client = KanataUDPClient(port: 37000)
        XCTAssertNotNil(client, "UDP client should be created successfully")
    }

    func testClientWithCustomConfiguration() {
        let client = KanataUDPClient(
            host: "127.0.0.1",
            port: 38000,
            timeout: 3.0
        )
        XCTAssertNotNil(client, "UDP client should accept custom configuration")
    }

    // MARK: - Authentication Tests

    func testAuthenticationWithoutServer() async {
        let client = KanataUDPClient(port: 37000)

        let result = await client.authenticate(token: "test-token", clientName: "TestClient")

        // Expected to fail gracefully without running server
        XCTAssertFalse(result, "Authentication should fail without running UDP server")
    }

    func testClearAuthentication() async {
        let client = KanataUDPClient(port: 37000)

        // Should not crash when clearing non-existent auth
        await client.clearAuthentication()

        XCTAssertTrue(true, "clearAuthentication should work even when not authenticated")
    }

    func testEnsureAuthenticated() async {
        let client = KanataUDPClient(port: 37000)

        let result = await client.ensureAuthenticated()

        // Should return false without server or shared token
        XCTAssertFalse(result, "ensureAuthenticated should fail without server")
    }

    // MARK: - Server Communication Tests

    func testCheckServerStatus() async {
        let client = KanataUDPClient(port: 37000)

        let status = await client.checkServerStatus()

        // Should fail gracefully without running server
        XCTAssertFalse(status, "Server status should return false without running server")
    }

    func testCheckServerStatusWithToken() async {
        let client = KanataUDPClient(port: 37000)

        let status = await client.checkServerStatus(authToken: "test-token")

        // Should fail gracefully without server
        XCTAssertFalse(status, "Server check with token should fail without running server")
    }

    // MARK: - Configuration Operations

    func testValidateConfig() async {
        let client = KanataUDPClient(port: 37000)

        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps)
        (deflayer base esc)
        """

        let result = await client.validateConfig(config)

        // Validation always returns success (kanata doesn't support UDP validation)
        if case .success = result {
            XCTAssertTrue(true, "Config validation should return success (validates on file load)")
        } else {
            XCTFail("Config validation should return .success")
        }
    }

    func testReloadConfigWithoutAuth() async {
        let client = KanataUDPClient(port: 37000)

        let result = await client.reloadConfig()

        // Should fail due to missing authentication
        if case .authenticationRequired = result {
            XCTAssertTrue(true, "Reload should fail without authentication")
        } else {
            XCTFail("Reload should return .authenticationRequired without auth")
        }
    }

    func testRestartKanataWithoutAuth() async {
        let client = KanataUDPClient(port: 37000)

        let result = await client.restartKanata()

        // Should fail due to missing authentication
        XCTAssertFalse(result, "Restart should fail without authentication")
    }

    // MARK: - Connection Cancellation

    func testCancelInflightAndCloseConnection() async {
        let client = KanataUDPClient(port: 37000)

        // Should not crash (even though we simplified to a no-op)
        await client.cancelInflightAndCloseConnection()

        XCTAssertTrue(true, "cancelInflightAndCloseConnection should not crash")
    }

    // MARK: - Error Handling

    func testGracefulFailureWithoutServer() async {
        let client = KanataUDPClient(port: 37000)

        // All operations should fail gracefully, not crash
        _ = await client.checkServerStatus()
        _ = await client.authenticate(token: "test")
        _ = await client.validateConfig("test")
        _ = await client.reloadConfig()
        _ = await client.restartKanata()

        XCTAssertTrue(true, "All operations should fail gracefully without server")
    }

    // MARK: - Integration Test (Manual)

    /// This test requires a running Kanata UDP server with known token
    /// Run manually only when you have kanata running locally
    func testRealServerCommunication() async throws {
        // Skip in CI - requires manual testing with running server
        try XCTSkipIf(true, "Requires running Kanata UDP server - test manually")

        let client = KanataUDPClient(port: 37000)

        // Check if server is responding
        let serverStatus = await client.checkServerStatus()
        XCTAssertTrue(serverStatus, "Server should be running for this test")

        // Try authentication with test token
        // (Replace with actual token from your test setup)
        let authResult = await client.authenticate(token: "your-test-token")
        XCTAssertTrue(authResult, "Authentication should succeed with valid token")
    }
}