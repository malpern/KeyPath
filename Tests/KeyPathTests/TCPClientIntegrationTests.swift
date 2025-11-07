import XCTest
@testable import KeyPath

final class TCPClientIntegrationTests: XCTestCase {
    private let port: Int = 37001

    private func serverReachable(timeout: TimeInterval = 1.0) async -> Bool {
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
        var received: Data = Data()

        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp)
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                let payload = "{\"Reload\":{\"wait\":true,\"timeout_ms\":1200}}\n".data(using: .utf8)!
                conn.send(content: payload, completion: .contentProcessed { _ in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, _ in
                        if let content { received = content }
                        exp.fulfill()
                    }
                })
            }
        }
        conn.start(queue: .global())
        await fulfillment(of: [exp], timeout: 3.0)
        conn.cancel()

        let s = String(data: received, encoding: .utf8) ?? ""
        // Expect exactly one JSON object line: ReloadResult
        let lines = s.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, "Expected single JSON object, got: \(lines.count) -> \(s)")
        XCTAssertTrue(lines.first?.contains("\"ReloadResult\"") ?? false, "Missing ReloadResult in response")
    }
}


