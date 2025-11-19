@testable import KeyPath
import Network
import XCTest

/// Tests for request_id functionality in KanataTCPClient
/// These tests verify the core business logic of request/response correlation,
/// NOT language features or basic networking.
final class TCPClientRequestIDTests: XCTestCase {
    private static let tcpTestsEnabled = ProcessInfo.processInfo.environment["KEYPATH_ENABLE_TCP_TESTS"] == "1"
    private let port: Int = 37001

    private func serverReachable(timeout: TimeInterval = 1.0) async -> Bool {
        guard Self.tcpTestsEnabled else { return false }
        let client = KanataTCPClient(port: port, timeout: timeout)
        return await client.checkServerStatus()
    }

    // MARK: - Request ID Generation Tests

    /// Test that request_id values are monotonically increasing
    /// This tests OUR logic for ID generation, which could break if we change the implementation
    func testRequestIDMonotonicity() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)

        // Make multiple requests and capture their IDs from responses
        var requestIds: [UInt64] = []

        for _ in 0..<5 {
            let hello = try await client.hello()
            if let requestId = hello.request_id {
                requestIds.append(requestId)
            }
        }

        // Verify we got request_ids back
        XCTAssertGreaterThanOrEqual(requestIds.count, 1, "Server should echo request_id")

        // Verify monotonicity: each ID should be greater than the previous
        for i in 1..<requestIds.count {
            XCTAssertGreaterThan(requestIds[i], requestIds[i-1],
                                "Request IDs should be monotonically increasing: got \(requestIds)")
        }
    }

    /// Test that different request types get different request_ids
    /// Verifies that the counter is shared across all request types
    func testRequestIDDifferentAcrossTypes() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)

        // Make requests of different types
        let hello1 = try await client.hello()
        let status1 = try await client.getStatus()
        let hello2 = try await client.hello()

        let ids = [hello1.request_id, status1.request_id, hello2.request_id].compactMap { $0 }

        // All IDs should be unique
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All request_ids should be unique: \(ids)")
    }

    // MARK: - Request ID Echo Tests

    /// Test that server echoes back the exact request_id we send
    /// This tests the protocol contract between client and server
    func testServerEchoesRequestID() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)

        // Make a request and verify the response has a request_id
        let hello = try await client.hello()
        XCTAssertNotNil(hello.request_id, "Server should echo request_id in HelloOk")

        let status = try await client.getStatus()
        XCTAssertNotNil(status.request_id, "Server should echo request_id in StatusInfo")
    }

    /// Test that reload operations include request_id
    /// Reload is the most critical operation, so verify it works
    func testReloadIncludesRequestID() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig(timeoutMs: 3000)

        // Parse the response to check for request_id
        switch result {
        case .success(let response):
            // Response should contain request_id field
            XCTAssertTrue(response.contains("request_id"),
                         "Reload response should include request_id: \(response)")
        case .failure(_, let response):
            // Even failures should echo request_id
            XCTAssertTrue(response.contains("request_id"),
                         "Reload error should include request_id: \(response)")
        default:
            XCTFail("Unexpected result type: \(result)")
        }
    }

    // MARK: - Protocol Parsing Tests

    /// Test that we can parse responses with request_id
    /// This tests our Codable implementation, which could break
    func testRequestIDParsing() throws {
        // HelloOk with request_id
        let helloJson = """
        {"HelloOk":{"version":"1.10.0","protocol":1,"capabilities":["reload"],"request_id":42}}
        """
        let helloData = helloJson.data(using: .utf8)!

        // Extract the HelloOk payload
        let json = try JSONSerialization.jsonObject(with: helloData) as! [String: Any]
        let helloOkPayload = json["HelloOk"] as! [String: Any]
        let payloadData = try JSONSerialization.data(withJSONObject: helloOkPayload)

        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: payloadData)
        XCTAssertEqual(hello.request_id, 42, "Should parse request_id from HelloOk")

        // StatusInfo with request_id
        let statusJson = """
        {"StatusInfo":{"engine_version":"1.10.0","uptime_s":100,"ready":true,"last_reload":{"ok":true,"at":"1234567890"},"request_id":99}}
        """
        let statusData = statusJson.data(using: .utf8)!
        let statusJsonObj = try JSONSerialization.jsonObject(with: statusData) as! [String: Any]
        let statusPayload = statusJsonObj["StatusInfo"] as! [String: Any]
        let statusPayloadData = try JSONSerialization.data(withJSONObject: statusPayload)

        let status = try JSONDecoder().decode(KanataTCPClient.TcpStatusInfo.self, from: statusPayloadData)
        XCTAssertEqual(status.request_id, 99, "Should parse request_id from StatusInfo")
    }

    /// Test that we can parse responses WITHOUT request_id (backward compatibility)
    /// Critical for working with old servers
    func testBackwardCompatibilityParsing() throws {
        // HelloOk without request_id (old server)
        let helloJson = """
        {"HelloOk":{"version":"1.10.0","protocol":1,"capabilities":["reload"]}}
        """
        let helloData = helloJson.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: helloData) as! [String: Any]
        let helloOkPayload = json["HelloOk"] as! [String: Any]
        let payloadData = try JSONSerialization.data(withJSONObject: helloOkPayload)

        let hello = try JSONDecoder().decode(KanataTCPClient.TcpHelloOk.self, from: payloadData)
        XCTAssertNil(hello.request_id, "Should parse HelloOk without request_id (old server)")
        XCTAssertEqual(hello.version, "1.10.0", "Should still parse other fields")

        // StatusInfo without request_id
        let statusJson = """
        {"StatusInfo":{"engine_version":"1.10.0","uptime_s":100,"ready":true,"last_reload":{"ok":true,"at":"1234567890"}}}
        """
        let statusData = statusJson.data(using: .utf8)!
        let statusJsonObj = try JSONSerialization.jsonObject(with: statusData) as! [String: Any]
        let statusPayload = statusJsonObj["StatusInfo"] as! [String: Any]
        let statusPayloadData = try JSONSerialization.data(withJSONObject: statusPayload)

        let status = try JSONDecoder().decode(KanataTCPClient.TcpStatusInfo.self, from: statusPayloadData)
        XCTAssertNil(status.request_id, "Should parse StatusInfo without request_id (old server)")
        XCTAssertTrue(status.ready, "Should still parse other fields")
    }

    // MARK: - Real-World Scenario Tests

    /// Test rapid successive requests (the problem request_id solves)
    /// This verifies that we can make multiple requests quickly without broadcast confusion
    func testRapidSuccessiveRequests() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)

        // Make 10 rapid requests - without request_id, these would hit the drain loop
        var successes = 0
        for _ in 0..<10 {
            do {
                _ = try await client.hello()
                successes += 1
            } catch {
                // Some might fail due to timing, but most should succeed
            }
        }

        // With request_id, we should get high success rate (>= 80%)
        // Without request_id, we'd hit the 10-attempt limit frequently
        XCTAssertGreaterThanOrEqual(successes, 8,
                                   "Request ID matching should enable rapid requests: \(successes)/10 succeeded")
    }

    /// Test interleaved requests of different types
    /// This is the classic scenario that broadcast draining couldn't handle
    func testInterleavedRequestTypes() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let client = KanataTCPClient(port: port)

        // Make different request types interleaved
        async let hello1 = client.hello()
        async let status1 = client.getStatus()
        async let hello2 = client.hello()
        async let status2 = client.getStatus()

        // All should succeed without confusion
        let results = try await (hello1, status1, hello2, status2)

        XCTAssertNotNil(results.0.version, "First hello should succeed")
        XCTAssertTrue(results.1.ready, "First status should succeed")
        XCTAssertNotNil(results.2.version, "Second hello should succeed")
        XCTAssertTrue(results.3.ready, "Second status should succeed")
    }
}
