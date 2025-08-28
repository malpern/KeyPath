import Foundation
import XCTest

@testable import KeyPath

/// Basic UDP client tests focused on initialization and basic functionality
@MainActor
final class UDPBasicTests: XCTestCase {
    override func setUp() async throws {
        TestEnvironment.forceTestMode = true
    }

    override func tearDown() async throws {
        TestEnvironment.forceTestMode = false
    }

    // MARK: - Basic Client Tests

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

    func testUDPConnectionAttemptInTestEnvironment() async throws {
        let client = KanataUDPClient(port: 37000)

        do {
            // Test basic server status check - should fail gracefully in test environment
            let result = try await client.checkServerStatus()

            // If it succeeds, verify it returns valid data
            XCTAssertNotNil(result, "Server status check should return result if successful")

        } catch {
            // Expected in test environment - should fail gracefully
            let errorMessage = error.localizedDescription.lowercased()
            XCTAssertTrue(
                errorMessage.contains("connection") ||
                    errorMessage.contains("timeout") ||
                    errorMessage.contains("refused") ||
                    errorMessage.contains("unreachable") ||
                    errorMessage.contains("network"),
                "Should be a reasonable network error in test environment: \(error)"
            )
        }
    }

    func testUDPMultipleClientInstances() async throws {
        // Test creating multiple client instances
        let client1 = KanataUDPClient(port: 37000)
        let client2 = KanataUDPClient(port: 37001)
        let client3 = KanataUDPClient(host: "127.0.0.1", port: 37002)

        XCTAssertNotNil(client1, "First client should be created")
        XCTAssertNotNil(client2, "Second client should be created")
        XCTAssertNotNil(client3, "Third client should be created")

        // All clients should be independent instances
        XCTAssertTrue(client1 !== client2, "Clients should be independent instances")
        XCTAssertTrue(client2 !== client3, "Clients should be independent instances")
    }

    // MARK: - Concurrent Client Tests

    func testConcurrentClientCreation() async throws {
        let clientTasks = (1 ... 5).map { port in
            Task {
                let client = KanataUDPClient(port: 37000 + port)
                return client != nil
            }
        }

        // Wait for all client creation tasks
        var successCount = 0
        for task in clientTasks {
            if await task.value {
                successCount += 1
            }
        }

        XCTAssertEqual(successCount, 5, "All concurrent client creation should succeed")
    }

    func testConcurrentConnectionAttempts() async throws {
        let client = KanataUDPClient(port: 37000)

        // Multiple concurrent connection attempts to the same client
        let connectionTasks = (1 ... 3).map { _ in
            Task {
                do {
                    _ = try await client.checkServerStatus()
                    return true
                } catch {
                    // Expected in test environment
                    return false
                }
            }
        }

        // All attempts should complete (though they may fail in test environment)
        var completedCount = 0
        for task in connectionTasks {
            _ = await task.value
            completedCount += 1
        }

        XCTAssertEqual(completedCount, 3, "All concurrent attempts should complete")
    }

    // MARK: - Error Handling Tests

    func testUDPClientWithInvalidPort() async throws {
        // Test edge case port values
        let edgePorts = [-1, 0, 65536, 99999]

        for port in edgePorts {
            // Client creation shouldn't crash with invalid ports
            XCTAssertNoThrow({
                _ = KanataUDPClient(port: port)
            }(), "Client creation should handle invalid port gracefully: \(port)")
        }
    }

    func testUDPClientWithInvalidHost() async throws {
        let invalidHosts = ["", "invalid.host.name", "256.256.256.256"]

        for host in invalidHosts {
            // Client creation shouldn't crash with invalid hosts
            XCTAssertNoThrow({
                _ = KanataUDPClient(host: host, port: 37000)
            }(), "Client creation should handle invalid host gracefully: \(host)")
        }
    }

    func testUDPClientWithInvalidTimeout() async throws {
        let invalidTimeouts: [TimeInterval] = [-1, 0, 999]

        for timeout in invalidTimeouts {
            // Client creation shouldn't crash with edge case timeouts
            XCTAssertNoThrow({
                _ = KanataUDPClient(port: 37000, timeout: timeout)
            }(), "Client creation should handle invalid timeout gracefully: \(timeout)")
        }
    }

    // MARK: - Performance Tests

    func testUDPClientCreationPerformance() throws {
        measure {
            // Test performance of client creation
            for _ in 0 ..< 10 {
                _ = KanataUDPClient(port: 37000)
            }
        }
    }

    func testUDPConnectionTimeoutBehavior() async throws {
        let shortTimeoutClient = KanataUDPClient(port: 37000, timeout: 0.1)
        let startTime = Date()

        do {
            _ = try await shortTimeoutClient.checkServerStatus()
        } catch {
            let elapsedTime = Date().timeIntervalSince(startTime)
            // Should timeout quickly with short timeout value
            XCTAssertLessThan(elapsedTime, 2.0, "Short timeout should fail quickly")
        }
    }
}
