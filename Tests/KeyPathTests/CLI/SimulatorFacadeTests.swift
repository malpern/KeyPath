@testable import KeyPathAppKit
import XCTest

final class SimulatorFacadeTests: XCTestCase {
    private let facade = SimulatorFacade()

    func testValidateKeyReturnsCanonicalForm() {
        XCTAssertEqual(facade.validateKey("caps"), "caps")
        XCTAssertEqual(facade.validateKey("Escape"), "esc")
        XCTAssertEqual(facade.validateKey("LALT"), "lalt")
    }

    func testValidateKeyReturnsNilForInvalid() {
        XCTAssertNil(facade.validateKey("blahblah"))
        XCTAssertNil(facade.validateKey("notakey123"))
    }
}
