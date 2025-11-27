@testable import KeyPathAppKit
import XCTest

final class WizardTelemetryTests: XCTestCase {
    func testRingBufferWrapsAndKeepsNewest() async {
        let telemetry = WizardTelemetry(capacity: 3)
        await telemetry.reset()

        let events = (1 ... 5).map {
            WizardEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval($0)),
                category: .autofixer,
                name: "e\($0)",
                result: "ok",
                details: nil
            )
        }
        for e in events {
            await telemetry.record(e)
        }

        let snapshot = await telemetry.snapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot.map(\.name), ["e3", "e4", "e5"])
    }
}
