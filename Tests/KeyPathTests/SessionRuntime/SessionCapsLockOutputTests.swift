import XCTest
@testable import KeyPathAppKit

final class SessionCapsLockOutputTests: XCTestCase {
    func testPressTogglesOnceUntilReleaseAndIgnoresRepeat() throws {
        var toggles = 0
        let output = SessionCapsLockOutput { toggles += 1 }
        try output.receive(value: 1)
        try output.receive(value: 2)
        try output.receive(value: 1)
        XCTAssertEqual(toggles, 1)
        try output.receive(value: 0)
        XCTAssertEqual(toggles, 1)
        try output.receive(value: 1)
        XCTAssertEqual(toggles, 2)
    }

    func testFailedPressDoesNotLatchAndCanRetry() throws {
        var attempts = 0
        let output = SessionCapsLockOutput {
            attempts += 1
            if attempts == 1 { throw SessionCapsLockOutput.Failure.verification }
        }
        XCTAssertThrowsError(try output.receive(value: 1))
        try output.receive(value: 1)
        XCTAssertEqual(attempts, 2)
        XCTAssertThrowsError(try output.receive(value: 3))
    }

    func testReleaseAndOrphanRepeatNeverToggle() throws {
        let output = SessionCapsLockOutput { XCTFail("unexpected toggle") }
        try output.receive(value: 0)
        try output.receive(value: 2)
    }
}
