import Foundation
import XCTest

@testable import KeyPath

/// Basic UDP client tests focused on initialization and simple operations
@MainActor
final class UDPBasicTests: XCTestCase {
    override func setUp() async throws {
        TestEnvironment.forceTestMode = true
    }

    override func tearDown() async throws {
        TestEnvironment.forceTestMode = false
    }

    // MARK: - Basic Client Creation Tests

    func testUDPClientCreation() async throws {
        let client = KanataUDPClient(port: 37000)
        XCTAssertNotNil(client, "UDP client should be created successfully")
    }

    func testUDPClientWithCustomPort() async throws {
        let customPort = 38000
        let client = KanataUDPClient(port: customPort)
        XCTAssertNotNil(client, "UDP client should accept custom port")
    }

    func testUDPClientWithCustomHost() async throws {
        let client = KanataUDPClient(host: "localhost", port: 37000)
        XCTAssertNotNil(client, "UDP client should accept custom host")
    }

    func testUDPClientWithTimeout() async throws {
        let client = KanataUDPClient(port: 37000, timeout: 3.0)
        XCTAssertNotNil(client, "UDP client should accept custom timeout")
    }

    // MARK: - Connection Tests in Test Environment

    func testServerStatusCheckInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        // checkServerStatus returns Bool, not throws
        let result = await client.checkServerStatus()

        // Expected to fail in test environment (no server running)
        XCTAssertFalse(result, "Server status should return false in test environment")
    }

    func testMultipleClientInstances() async throws {
        // Test creating multiple independent client instances
        let client1 = KanataUDPClient(port: 37000)
        let client2 = KanataUDPClient(port: 37001)
        let client3 = KanataUDPClient(host: "127.0.0.1", port: 37002)

        XCTAssertNotNil(client1, "First client should be created")
        XCTAssertNotNil(client2, "Second client should be created")
        XCTAssertNotNil(client3, "Third client should be created")

        // Verify they're independent instances (not the same actor)
        XCTAssertTrue(client1 !== client2, "Clients should be independent instances")
        XCTAssertTrue(client2 !== client3, "Clients should be independent instances")
    }

    func testAuthenticationInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        let result = await client.authenticate(token: "test-token", clientName: "TestClient")

        // Expected to fail without running server
        XCTAssertFalse(result, "Authentication should fail in test environment")
    }

    func testValidateConfigInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        let config = "(defcfg process-unmapped-keys yes)"
        let result = await client.validateConfig(config)

        // Should return success (kanata validates on file load, not via UDP)
        if case .success = result {
            XCTAssertTrue(true, "Config validation should return success")
        } else {
            XCTFail("Config validation should return .success")
        }
    }

    // MARK: - Error Handling Tests

    func testGracefulFailureInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        // All operations should fail gracefully, not crash
        _ = await client.checkServerStatus()
        _ = await client.authenticate(token: "test")
        _ = await client.reloadConfig()
        _ = await client.restartKanata()

        XCTAssertTrue(true, "All operations should complete without crashing")
    }

    func testClearAuthenticationInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        // Should not crash when clearing non-existent auth
        await client.clearAuthentication()

        XCTAssertTrue(true, "clearAuthentication should not crash")
    }

    func testCancelInflightInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        // Should not crash (simplified to no-op)
        await client.cancelInflightAndCloseConnection()

        XCTAssertTrue(true, "cancelInflightAndCloseConnection should not crash")
    }
}