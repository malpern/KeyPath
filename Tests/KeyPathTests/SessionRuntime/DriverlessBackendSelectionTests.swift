import Foundation
@testable import KeyPathCore
import XCTest

final class DriverlessBackendSelectionTests: XCTestCase {
    func testSelectedRuntimeIsAlwaysUnprivilegedSession() {
        XCTAssertEqual(KanataRuntimeBackend.selected, .session)
        XCTAssertFalse(KanataRuntimeBackend.selected.requiresPrivilegedServices)
    }

    func testHistoricalDriverKitDataStillDecodesWithoutChangingSelection() throws {
        let historical = try JSONDecoder().decode(KanataRuntimeBackend.self, from: Data(#""driverKit""#.utf8))
        XCTAssertEqual(historical, .driverKit)
        XCTAssertEqual(KanataRuntimeBackend.selected, .session)
    }
}
