import Foundation
@testable import KeyPath
import XCTest

/// Test that verifies UDP client improvements for handling non-existent servers
class UDPClientFixTest: XCTestCase {
    /// Test that checkServerStatus fails quickly when no UDP server is running
    func testCheckServerStatusWithNoServer() async {
        let client = KanataUDPClient(port: 54141, timeout: 3.0)

        let startTime = Date()

        let result = await client.checkServerStatus()

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Should fail quickly (within 2 seconds due to our connection establishment timeout)
        XCTAssertFalse(result, "Server status should return false when no server is running")
        XCTAssertLessThan(duration, 2.0, "Should fail quickly when no server is running (got \(duration)s)")

        print("✅ UDP client failed in \(String(format: "%.2f", duration))s - fix is working!")
    }

    /// Test that authentication fails quickly when no UDP server is running
    func testAuthenticateWithNoServer() async {
        let client = KanataUDPClient(port: 54141, timeout: 3.0)

        let startTime = Date()

        let result = await client.authenticate(token: "test-token")

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Should fail quickly
        XCTAssertFalse(result, "Authentication should return false when no server is running")
        XCTAssertLessThan(duration, 2.0, "Should fail quickly when no server is running (got \(duration)s)")

        print("✅ UDP authentication failed in \(String(format: "%.2f", duration))s - fix is working!")
    }
}
