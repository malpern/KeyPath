import Network
import XCTest

@testable import KeyPathAppKit

final class TCPClientIntegrationTests: XCTestCase {
    private static let tcpTestsEnabled =
        ProcessInfo.processInfo.environment["KEYPATH_ENABLE_TCP_TESTS"] == "1"
    private let port: Int = 37001

    private func serverReachable(timeout: TimeInterval = 1.0) async -> Bool {
        guard Self.tcpTestsEnabled else { return false }
        let client = KanataTCPClient(port: port, timeout: timeout)
        return await client.checkServerStatus()
    }

    func testHelloProtocolAndCapabilities() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }
        let client = KanataTCPClient(port: port)
        let hello = try await client.hello()
        XCTAssertGreaterThanOrEqual(hello.protocolVersion, 2)
        XCTAssertTrue(hello.capabilities.contains("reload"))
        XCTAssertTrue(hello.capabilities.contains("status"))
    }

    func testReloadWaitReturnsResult() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig(timeoutMs: 3000)
        switch result {
        case .success:
            XCTAssertTrue(true)
        default:
            XCTFail("Reload(wait) did not succeed: \(result)")
        }
    }

    func testStatusIncludesLastReloadOptional() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }
        let client = KanataTCPClient(port: port)
        let status = try await client.getStatus()
        // last_reload is optional; if present validate shape
        if let last = status.last_reload {
            XCTAssertNotNil(last.epoch)
        }
    }

    // Verify framing: Reload(wait) returns exactly one JSON object (ReloadResult)
    func testFramingReloadWaitSingleObject() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // Use a raw connection to inspect bytes
        let exp = expectation(description: "recv")
        final class ReceivedData: @unchecked Sendable {
            var value: Data = .init()
        }
        let received = ReceivedData()

        let conn = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp
        )
        conn.stateUpdateHandler = { (state: NWConnection.State) in
            if case .ready = state {
                let payload = Data("{\"Reload\":{\"wait\":true,\"timeout_ms\":1200}}\n".utf8)
                conn.send(
                    content: payload,
                    completion: .contentProcessed { (_: NWError?) in
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, _ in
                            if let content { received.value = content }
                            exp.fulfill()
                        }
                    }
                )
            }
        }
        conn.start(queue: DispatchQueue.global())
        await fulfillment(of: [exp], timeout: 3.0)
        conn.cancel()

        let s = String(data: received.value, encoding: .utf8) ?? ""
        // Expect exactly one JSON object line: ReloadResult
        let lines = s.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, "Expected single JSON object, got: \(lines.count) -> \(s)")
        XCTAssertTrue(
            lines.first?.contains("\"ReloadResult\"") ?? false, "Missing ReloadResult in response"
        )
    }

    // After a successful Reload(wait), Status should report last_reload with duration and epoch
    func testReloadThenStatusHasLastReloadFields() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig(timeoutMs: 4000)
        switch result {
        case .success:
            let status = try await client.getStatus()
            guard let last = status.last_reload else {
                return XCTFail("Expected last_reload present after reload")
            }
            XCTAssertTrue(last.ok, "last_reload.ok should be true after successful reload")
            XCTAssertNotNil(last.duration_ms, "last_reload.duration_ms should be set")
            XCTAssertNotNil(last.epoch, "last_reload.epoch should be set")
        default:
            XCTFail("Reload(wait) did not succeed: \(result)")
        }
    }

    // Try very small timeout; assert single JSON object framing is preserved
    func testReloadWaitVerySmallTimeoutStillSingleObject() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        let exp = expectation(description: "recv-timeout")
        final class ReceivedData: @unchecked Sendable {
            var value: Data = .init()
        }
        let received = ReceivedData()

        let conn = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp
        )
        conn.stateUpdateHandler = { (state: NWConnection.State) in
            if case .ready = state {
                let payload = Data("{\"Reload\":{\"wait\":true,\"timeout_ms\":1}}\n".utf8)
                conn.send(
                    content: payload,
                    completion: .contentProcessed { (_: NWError?) in
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, _ in
                            if let content { received.value = content }
                            exp.fulfill()
                        }
                    }
                )
            }
        }
        conn.start(queue: DispatchQueue.global())
        await fulfillment(of: [exp], timeout: 3.0)
        conn.cancel()

        let s = String(data: received.value, encoding: .utf8) ?? ""
        let lines = s.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, "Expected single JSON object, got: \(lines.count) -> \(s)")
        XCTAssertTrue(
            lines.first?.contains("\"ReloadResult\"") ?? false, "Missing ReloadResult in response"
        )
        // Accept either timeout or immediate success; framing is the key invariant
    }

    // MARK: - FakeKey Tests

    /// Test that actOnFakeKey returns appropriate result for non-existent key
    /// Note: This requires Kanata to have virtual keys defined to test success path
    func testActOnFakeKeyWithNonExistentKey() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }
        let client = KanataTCPClient(port: port)

        // Using a key name that almost certainly doesn't exist
        let result = await client.actOnFakeKey(name: "nonexistent_test_key_12345", action: .tap)

        switch result {
        case .success:
            // Kanata may succeed even for non-existent keys (silent no-op)
            XCTAssertTrue(true)
        case let .error(message):
            // Expected: key doesn't exist
            XCTAssertTrue(message.lowercased().contains("not found") || message.lowercased().contains("unknown"))
        case let .networkError(message):
            XCTFail("Unexpected network error: \(message)")
        }
    }

    /// Test all FakeKeyAction variants serialize correctly
    func testFakeKeyActionSerialization() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }
        let client = KanataTCPClient(port: port)

        // Test each action type - they should all complete without network errors
        for action in [KanataTCPClient.FakeKeyAction.tap, .press, .release, .toggle] {
            let result = await client.actOnFakeKey(name: "test_key", action: action)
            switch result {
            case let .networkError(message):
                XCTFail("Network error for action \(action.rawValue): \(message)")
            default:
                // success or error (key not found) is fine - proves serialization worked
                break
            }
        }
    }

    /// Test FakeKeyAction raw values match Kanata protocol
    func testFakeKeyActionRawValues() {
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.press.rawValue, "Press")
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.release.rawValue, "Release")
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.tap.rawValue, "Tap")
        XCTAssertEqual(KanataTCPClient.FakeKeyAction.toggle.rawValue, "Toggle")
    }
}
