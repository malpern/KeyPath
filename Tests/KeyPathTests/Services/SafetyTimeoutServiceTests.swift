import Foundation
import XCTest
@testable import KeyPath

final class SafetyTimeoutServiceTests: XCTestCase {
    func testTimeoutFiresWhenShouldStopTrue() async throws {
        let service = SafetyTimeoutService()
        let exp = expectation(description: "onTimeout called")

        service.start(
            durationSeconds: 0.05,
            shouldStop: { true },
            onTimeout: {
                exp.fulfill()
            }
        )

        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testTimeoutDoesNotFireWhenShouldStopFalse() async throws {
        let service = SafetyTimeoutService()
        let exp = expectation(description: "onTimeout should not be called")
        exp.isInverted = true

        service.start(
            durationSeconds: 0.05,
            shouldStop: { false },
            onTimeout: {
                exp.fulfill()
            }
        )

        await fulfillment(of: [exp], timeout: 0.3)
    }
}


