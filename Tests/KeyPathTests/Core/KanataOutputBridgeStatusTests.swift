@testable import KeyPathCore
import XCTest

final class KanataOutputBridgeStatusTests: XCTestCase {
    func testDecodesLegacyPayloadWithoutCompanionRunning() throws {
        let payload = """
        {
          "available": true,
          "requiresPrivilegedBridge": true,
          "socketDirectory": "/Library/KeyPath/run/kpko",
          "detail": "legacy payload"
        }
        """

        let status = try JSONDecoder().decode(
            KanataOutputBridgeStatus.self,
            from: Data(payload.utf8)
        )

        XCTAssertTrue(status.available)
        XCTAssertTrue(status.companionRunning)
        XCTAssertTrue(status.requiresPrivilegedBridge)
        XCTAssertEqual(status.socketDirectory, "/Library/KeyPath/run/kpko")
        XCTAssertEqual(status.detail, "legacy payload")
    }
}
