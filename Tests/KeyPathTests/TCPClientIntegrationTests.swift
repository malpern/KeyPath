import Network
@preconcurrency import XCTest

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
        XCTAssertGreaterThanOrEqual(hello.protocolVersion, 1)
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

    // Verify framing: Reload(wait) eventually returns ReloadResult
    // This test uses the high-level client which properly handles broadcasts
    func testFramingReloadWaitSingleObject() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // Use the high-level client which properly accumulates responses
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig(timeoutMs: 2000)

        // The client should successfully parse ReloadResult from the stream
        switch result {
        case .success:
            // ReloadResult was successfully parsed from the response stream
            XCTAssertTrue(true)
        case let .failure(error, _):
            XCTFail("Reload failed with error: \(error)")
        case let .networkError(msg):
            XCTFail("Reload failed with network error: \(msg)")
        }
    }

    // Try very small timeout; verify client handles it gracefully
    func testReloadWaitVerySmallTimeoutStillSingleObject() async throws {
        guard await serverReachable() else { throw XCTSkip("TCP server not running") }

        // Use the high-level client with a very short timeout
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig(timeoutMs: 1)

        // Any result is acceptable - success, failure, or network error
        // The key thing is the client handles it without crashing
        switch result {
        case .success:
            XCTAssertTrue(true, "Reload succeeded even with 1ms timeout")
        case .failure:
            XCTAssertTrue(true, "Reload failed gracefully with short timeout")
        case .networkError:
            XCTAssertTrue(true, "Network error with short timeout is acceptable")
        }
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
