@testable import KeyPathAppKit
import XCTest

final class ValidationFailureStateTests: XCTestCase {
    func testFallbackWhenErrorsEmpty() {
        let state = ValidationFailureState(rawErrors: [])
        XCTAssertEqual(state.errors, [ValidationFailureState.fallbackMessage])
        XCTAssertEqual(state.copyText, ValidationFailureState.fallbackMessage)
    }

    func testTrimsWhitespaceAndFiltersBlanks() {
        let state = ValidationFailureState(rawErrors: ["  First error  ", "", "Second error\n", "   "])
        XCTAssertEqual(state.errors, ["First error", "Second error"])
        XCTAssertEqual(state.copyText, "First error\nSecond error")
    }

    func testFallbackWhenOnlyWhitespaceProvided() {
        let state = ValidationFailureState(rawErrors: ["   ", "\n\n"])
        XCTAssertEqual(state.errors, [ValidationFailureState.fallbackMessage])
    }
}
