@testable import KeyPathAppKit
import KeyPathCore
import XCTest

extension KanataTCPClient {
    fileprivate func seedBundledCapabilities() {
        cachedHello = TcpHelloOk(
            version: "1.12.1-prerelease-1", protocolVersion: 1,
            capabilities: ["reload", "layer-names", "current-layer-name"]
        )
    }
}

final class TCPStatusCapabilityTests: XCTestCase {
    func testUnadvertisedStatusRefusedBeforeOpeningConnection() async throws {
        let client = KanataTCPClient(port: 1, timeout: 0.1)
        await client.seedBundledCapabilities()
        do {
            _ = try await client.getStatus()
            XCTFail("A server without the status capability must not receive Status")
        } catch KeyPathError.communication(.invalidResponse) {
            // Capability refusal, rather than an attempted connection to port 1.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let connectionAbsent = await client.connection == nil
        XCTAssertTrue(connectionAbsent)
        let hello = try await client.hello()
        XCTAssertEqual(hello.capabilities, ["reload", "layer-names", "current-layer-name"])
    }
}
