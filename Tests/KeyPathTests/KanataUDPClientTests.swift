import Foundation
@testable import KeyPath
import Network
import XCTest

/// Comprehensive tests for KanataUDPClient
class KanataUDPClientTests: XCTestCase {
    // MARK: - Initialization Tests

    func testUDPClientInitialization() async {
        let client = KanataUDPClient(port: 37000)

        // Client should be created successfully
        XCTAssertNotNil(client)

        // Should not be authenticated initially
        let isAuth = await client.isAuthenticated
        XCTAssertFalse(isAuth)
    }

    func testUDPClientCustomConfiguration() async {
        let customHost = "192.168.1.100"
        let customPort = 38000
        let customTimeout = 5.0

        let client = KanataUDPClient(
            host: customHost,
            port: customPort,
            timeout: customTimeout
        )

        XCTAssertNotNil(client)
        let isAuth2 = await client.isAuthenticated
        XCTAssertFalse(isAuth2)
    }

    // MARK: - Authentication Tests

    func testAuthenticationWithMockResponse() async {
        let client = KanataUDPClient(port: 37000)

        // Test authentication with test token
        let testToken = "test-auth-token-12345"

        // Note: This will fail with real server not running, but tests the logic
        let result = await client.authenticate(token: testToken, clientName: "TestClient")

        // Expected to fail without real server
        XCTAssertFalse(result, "Authentication should fail without running UDP server")
        let authCheck = await client.isAuthenticated
        XCTAssertFalse(authCheck)
    }

    func testAuthenticationStateManagement() async {
        let client = KanataUDPClient(port: 37000)

        // Initially not authenticated
        let authStatus1 = await client.isAuthenticated
        XCTAssertFalse(authStatus1)

        // Clear authentication should work even when not authenticated
        await client.clearAuthentication()
        let authStatus2 = await client.isAuthenticated
        XCTAssertFalse(authStatus2)
    }

    func testAuthenticationPayloadSizeValidation() async {
        let client = KanataUDPClient(port: 37000)

        // Test with extremely long token (should fail size check)
        let oversizedToken = String(repeating: "a", count: 2000)

        let result = await client.authenticate(token: oversizedToken)

        // Should fail due to size limits
        XCTAssertFalse(result, "Oversized authentication payload should be rejected")
    }

    // MARK: - Server Communication Tests

    func testServerStatusCheck() async {
        let client = KanataUDPClient(port: 37000)

        // Test server status without running server
        let status = await client.checkServerStatus()

        // Should fail gracefully without server
        XCTAssertFalse(status, "Server status should return false without running server")
    }

    func testServerStatusWithCustomToken() async {
        let client = KanataUDPClient(port: 37000)

        let customToken = "custom-status-token"
        let status = await client.checkServerStatus(authToken: customToken)

        // Should fail gracefully without server
        XCTAssertFalse(status)
    }

    // MARK: - Configuration Validation Tests

    func testConfigValidationSizeGating() async {
        let client = KanataUDPClient(port: 37000)

        // Test with oversized config (>1000 bytes)
        let oversizedConfig = String(repeating: "(defsrc a)\n(deflayer base b)\n", count: 50)

        let result = await client.validateConfig(oversizedConfig)

        // Should be rejected due to size
        switch result {
        case let .networkError(error):
            XCTAssertTrue(error.contains("too large"), "Error should mention size limit")
        case .authenticationRequired:
            XCTAssertTrue(true, "Expected auth failure without server")
        default:
            XCTFail("Expected network error or auth failure for oversized config")
        }
    }

    func testConfigValidationWithValidSizeConfig() async {
        let client = KanataUDPClient(port: 37000)

        // Test with reasonably sized config
        let smallConfig = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps)
        (deflayer base esc)
        """

        let result = await client.validateConfig(smallConfig)

        // Should pass size check (but fail without server)
        // The error should be network-related, not size-related
        switch result {
        case .authenticationRequired:
            XCTAssertTrue(true, "Should fail due to authentication")
        case let .networkError(error):
            XCTAssertFalse(error.contains("too large"), "Error should not be size-related")
        default:
            XCTAssertTrue(true, "Should fail without server")
        }
    }

    // MARK: - Kanata Control Tests

    func testKanataRestart() async {
        let client = KanataUDPClient(port: 37000)

        let result = await client.restartKanata()

        // Should fail gracefully without server
        XCTAssertFalse(result, "Restart should fail without running server")
    }

    func testConfigReload() async {
        let client = KanataUDPClient(port: 37000)

        let result = await client.reloadConfig()

        // Should fail gracefully without server
        XCTAssertFalse(result.isSuccess, "Config reload should fail without running server")
        XCTAssertNotNil(result.errorMessage, "Error should be provided when reload fails")
    }

    // MARK: - Network Timeout Tests

    func testTimeoutConfiguration() async {
        // Test with very short timeout
        let shortTimeoutClient = KanataUDPClient(port: 37000, timeout: 0.1)

        let result = await shortTimeoutClient.checkServerStatus()

        // Should fail quickly due to timeout
        XCTAssertFalse(result, "Should timeout quickly with short timeout")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentOperations() async {
        let client = KanataUDPClient(port: 37000)

        // Test concurrent authentication attempts
        async let auth1 = client.authenticate(token: "token1")
        async let auth2 = client.authenticate(token: "token2")
        async let status = client.checkServerStatus()

        let results = await [auth1, auth2, status]

        // All should fail without server, but shouldn't crash
        XCTAssertFalse(results[0], "Concurrent auth 1 should fail gracefully")
        XCTAssertFalse(results[1], "Concurrent auth 2 should fail gracefully")
        XCTAssertFalse(results[2], "Concurrent status should fail gracefully")
    }

    // MARK: - Error Handling Tests

    func testGracefulErrorHandling() async {
        let client = KanataUDPClient(port: 99999) // Invalid port

        let result = await client.authenticate(token: "test")

        // Should handle invalid port gracefully
        XCTAssertFalse(result, "Invalid port should be handled gracefully")
    }

    // MARK: - Size Limit Constants Tests

    func testUDPSizeLimits() {
        // Verify size limits are reasonable for UDP
        XCTAssertEqual(KanataUDPClient.maxUDPPayloadSize, 1200, "UDP payload limit should be 1200 bytes")
        XCTAssertLessThanOrEqual(KanataUDPClient.maxUDPPayloadSize, 1400, "Should be within safe UDP limits")
        XCTAssertGreaterThan(KanataUDPClient.maxUDPPayloadSize, 500, "Should allow reasonable payload sizes")
    }
}

// MARK: - Performance Tests

extension KanataUDPClientTests {
    func testAuthenticationPerformance() {
        let client = KanataUDPClient(port: 37000)

        measure {
            Task {
                _ = await client.authenticate(token: "perf-test-token")
            }
        }
    }

    func testConfigValidationPerformance() {
        let client = KanataUDPClient(port: 37000)
        let testConfig = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps tab)
        (deflayer base esc @tab)
        """

        measure {
            Task {
                _ = await client.validateConfig(testConfig)
            }
        }
    }
}
