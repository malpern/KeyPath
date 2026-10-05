import KeyPathCore
import XCTest

final class SessionCapsInputStateTests: XCTestCase {
    func testInactiveF18AndRawCapsRemainPhysical() {
        var state = SessionCapsInputState()
        for value: UInt64 in [0, 1, 2] {
            XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: value))
            XCTAssertNil(state.logicalUsage(capturedUsage: 57, value: value))
        }
        // A press seen before activation never becomes lease-owned retroactively.
        state.didAdmit(capturedUsage: 109, value: 1, generation: "one")
        state.activate(generation: "one")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 0))
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
        for value: UInt64 in [0, 1, 2] {
            XCTAssertNil(state.logicalUsage(capturedUsage: 57, value: value))
        }
        XCTAssertEqual(state.logicalUsage(capturedUsage: 4, value: 1), 4)
        XCTAssertEqual(state.logicalUsage(capturedUsage: 224, value: 0), 224)
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 3))
    }

    func testReleaseAndRepeatRequireSuccessfullyAdmittedPress() {
        var state = SessionCapsInputState()
        state.activate(generation: "one")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 0))
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
        state.didAdmit(capturedUsage: 109, value: 0, generation: "one")
        state.didAdmit(capturedUsage: 109, value: 2, generation: "one")
        XCTAssertEqual(state.logicalUsage(capturedUsage: 109, value: 1), 57)
        // Translation alone represents an enqueue that might still fail.
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
        state.didAdmit(capturedUsage: 109, value: 1, generation: "one")
        XCTAssertEqual(state.logicalUsage(capturedUsage: 109, value: 2), 57)
        state.didAdmit(capturedUsage: 109, value: 2, generation: "one")
        XCTAssertEqual(state.logicalUsage(capturedUsage: 109, value: 0), 57)
        state.didAdmit(capturedUsage: 109, value: 0, generation: "one")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 0))
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
    }

    func testReplacementAndReactivationDoNotAdoptStalePresses() {
        var state = SessionCapsInputState()
        state.activate(generation: "one")
        state.didAdmit(capturedUsage: 109, value: 1, generation: "one")
        state.activate(generation: "two")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 0))
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
        state.didAdmit(capturedUsage: 109, value: 1, generation: "one")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
        state.didAdmit(capturedUsage: 109, value: 1, generation: "two")
        state.revoke()
        XCTAssertNil(state.leaseGeneration)
        state.activate(generation: "three")
        state.didAdmit(capturedUsage: 109, value: 1, generation: "two")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 0))
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 2))
    }

    func testSameLeaseActivationAndRawCapsDoNotDisturbCommittedPress() {
        var state = SessionCapsInputState()
        state.activate(generation: "one")
        state.didAdmit(capturedUsage: 109, value: 1, generation: "one")
        state.activate(generation: "one")
        state.didAdmit(capturedUsage: 57, value: 0, generation: "one")
        state.didAdmit(capturedUsage: 4, value: 0, generation: "one")
        state.didAdmit(capturedUsage: 109, value: 3, generation: "one")
        XCTAssertEqual(state.logicalUsage(capturedUsage: 109, value: 2), 57)
        state.activate(generation: "")
        XCTAssertNil(state.logicalUsage(capturedUsage: 109, value: 0))
    }

    func testNativeF18CannotBeAttributedByThisTransport() {
        var state = SessionCapsInputState()
        state.activate(generation: "one")
        // The event carries only usage109: native F18 is indistinguishable.
        // Lease/config collision refusal belongs to admission, not this helper.
        XCTAssertEqual(state.logicalUsage(capturedUsage: 109, value: 1), 57)
    }
}
