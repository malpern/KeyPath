import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// The decisions the worker makes when a fleet check returns.
@MainActor
final class SessionCapsCheckHandlingTests: XCTestCase {
    private typealias Failure = SessionRuntimeWorker.CapsCheckFailure
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func device(_ id: UInt64) -> SessionCapsMappingPolicy.DeviceIdentity {
        .init(registryEntryID: id, vendorID: 0x1234, productID: 1, serialNumber: nil, locationID: UInt32(id))
    }

    func testABusyLeaseIsNotAFailureOfOwnership() {
        XCTAssertEqual(Failure(SessionCapsMappingLease.Refusal.busy), .busy)
    }

    func testAnUnreadableInventoryIsNotALossOfOwnership() {
        XCTAssertEqual(Failure(SessionRuntimeWorker.CapsInventoryFailure.unavailable), .inventoryUnavailable)
    }

    func testAnyOtherErrorEndsTheSession() {
        struct Unexpected: Error {}
        XCTAssertEqual(Failure(Unexpected()), .ownershipLost)
        XCTAssertEqual(Failure(SessionCapsRuntimeSupport.Refusal.configIdentity), .ownershipLost)
    }

    func testCapsInputStartsWithTheFirstCoveredKeyboardOnly() {
        XCTAssertEqual(SessionRuntimeWorker.capsInputChange(previous: [], current: [1]), .activate)
        XCTAssertEqual(SessionRuntimeWorker.capsInputChange(previous: [1], current: [1, 2]), .none)
    }

    func testCapsInputStopsWhenNoKeyboardIsCovered() {
        XCTAssertEqual(SessionRuntimeWorker.capsInputChange(previous: [1], current: []), .revoke)
        XCTAssertEqual(SessionRuntimeWorker.capsInputChange(previous: [], current: []), .revoke)
    }

    func testACoveredKeyboardIsVerifiedEvenDuringABackoff() {
        let retryAfter: [UInt64: Date] = [1: now.addingTimeInterval(10), 2: now.addingTimeInterval(10)]
        let retryable = SessionRuntimeWorker.retryableDevices(
            [device(1), device(2), device(3)], covered: [1], retryAfter: retryAfter, now: now
        )
        XCTAssertEqual(retryable.map(\.registryEntryID), [1, 3], "2 is still backing off; 3 has no backoff")
    }

    func testAKeyboardIsRetriedWhenItsBackoffEnds() {
        let retryable = SessionRuntimeWorker.retryableDevices([device(2)], covered: [], retryAfter: [2: now], now: now)
        XCTAssertEqual(retryable.map(\.registryEntryID), [2])
    }

    func testBackoffsFollowEachKeyboardsResult() {
        let earlier = now.addingTimeInterval(5)
        let next = SessionRuntimeWorker.nextBackoffs(
            [1: earlier, 2: earlier, 3: earlier], covered: [1], failed: [4], departed: [2], now: now
        )
        XCTAssertEqual(next, [3: earlier, 4: now.addingTimeInterval(SessionRuntimeWorker.failureBackoff)],
                       "covered 1 and departed 2 are cleared, 3 is untouched, failed 4 backs off")
    }

    func testAKeyboardThatFailedThisCheckKeepsItsBackoffEvenIfReadAsDeparted() {
        let next = SessionRuntimeWorker.nextBackoffs([:], covered: [], failed: [4], departed: [4], now: now)
        XCTAssertEqual(next.keys.sorted(), [4])
    }
}
