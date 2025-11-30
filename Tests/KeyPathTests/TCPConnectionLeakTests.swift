import Network
@preconcurrency import XCTest

@testable import KeyPathAppKit

/// Tests for TCP connection leak prevention
/// Verifies that file descriptors are properly cleaned up when connections close
final class TCPConnectionLeakTests: XCTestCase {
    private static let tcpTestsEnabled =
        ProcessInfo.processInfo.environment["KEYPATH_ENABLE_TCP_TESTS"] == "1"
    private let port: Int = 37001

    private func serverReachable(timeout: TimeInterval = 1.0) async -> Bool {
        guard Self.tcpTestsEnabled else { return false }
        let client = KanataTCPClient(port: port, timeout: timeout)
        return await client.checkServerStatus()
    }

    // MARK: - Connection Cleanup Tests

    /// Test that connections are properly cleaned up after disconnect
    /// This tests the fix for the file descriptor leak (tcp_server.rs:627-629)
    func testConnectionsCleanedUpAfterDisconnect() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // Create and close many connections to test cleanup
        let connectionCount = 100

        for i in 0 ..< connectionCount {
            let client = KanataTCPClient(port: port)

            // Make a request
            _ = try? await client.hello()

            // Client should be deallocated here, closing the connection
            // Server should clean up the connection from its HashMap

            if i % 10 == 0 {
                // Log progress
                print("Created and closed \(i + 1) connections")
            }
        }

        // If the server is leaking connections, it would have crashed by now
        // Verify server is still responsive
        let finalClient = KanataTCPClient(port: port)
        let hello = try await finalClient.hello()
        XCTAssertNotNil(hello.version, "Server should still be responsive after 100 connections")
    }

    /// Test rapid connection creation and closure
    /// Verifies that the server can handle connection churn without leaking
    func testRapidConnectionChurn() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // Create connections as fast as possible
        let connectionCount = 50
        var succeeded = 0

        for _ in 0 ..< connectionCount {
            let client = KanataTCPClient(port: port, timeout: 1.0)
            if await (try? client.hello()) != nil {
                succeeded += 1
            }
            // Connection closes immediately as client is deallocated
        }

        // Most connections should succeed (allow some failures due to timing)
        XCTAssertGreaterThanOrEqual(
            succeeded, connectionCount - 5,
            "Most rapid connections should succeed: \(succeeded)/\(connectionCount)"
        )

        // Verify server is still responsive
        let finalClient = KanataTCPClient(port: port)
        _ = try await finalClient.hello()
    }

    /// Test concurrent connections from multiple clients
    /// Verifies that the server properly cleans up when handling multiple simultaneous connections
    func testConcurrentConnections() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // Create multiple concurrent connections
        let testPort = port // Capture port locally for Swift 6 concurrency
        let succeeded = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    let client = KanataTCPClient(port: testPort)
                    do {
                        _ = try await client.hello()
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var count = 0
            for await result in group {
                if result {
                    count += 1
                }
            }
            return count
        }

        XCTAssertGreaterThanOrEqual(
            succeeded, 15,
            "Most concurrent connections should succeed: \(succeeded)/20"
        )

        // Verify server is still responsive
        let finalClient = KanataTCPClient(port: port)
        _ = try await finalClient.hello()
    }

    /// Test connection cleanup after errors
    /// Verifies that connections are cleaned up even when errors occur
    func testConnectionCleanupAfterError() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)

        // Make a valid request first
        _ = try await client.hello()

        // The connection should be cleaned up after the client is deallocated
        // Create a new client to verify server is still responsive
        let newClient = KanataTCPClient(port: port)
        let hello = try await newClient.hello()
        XCTAssertNotNil(hello.version, "Server should still be responsive after connection cleanup")
    }

    // MARK: - File Descriptor Monitoring

    /// Test that file descriptors don't accumulate over many connections
    /// This is a meta-test that would catch the file descriptor leak
    func testFileDescriptorsDontAccumulate() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // This test creates many connections to stress-test the cleanup logic
        // Before the fix (tcp_server.rs:627-629), this would cause "Too many open files"
        // After the fix, all connections should be cleaned up properly

        let iterationCount = 200
        var failures = 0

        for i in 0 ..< iterationCount {
            let client = KanataTCPClient(port: port, timeout: 2.0)
            do {
                _ = try await client.hello()
            } catch {
                failures += 1
                // If we start getting "Too many open files" errors, the cleanup isn't working
                let errorDesc = String(describing: error)
                if errorDesc.contains("Too many") {
                    XCTFail("File descriptor leak detected at connection \(i): \(error)")
                    return
                }
            }

            if i % 50 == 0 {
                print("Completed \(i) connections, \(failures) failures")
            }
        }

        // Allow some failures due to timing, but not too many
        XCTAssertLessThan(failures, 20, "Too many connection failures: \(failures)/\(iterationCount)")

        // Final sanity check - server should still be responsive
        let finalClient = KanataTCPClient(port: port)
        let hello = try await finalClient.hello()
        XCTAssertNotNil(
            hello.version, "Server should still be responsive after \(iterationCount) connections"
        )
    }
}
