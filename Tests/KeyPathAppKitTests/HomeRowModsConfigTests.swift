import XCTest
@testable import KeyPathAppKit

final class HomeRowModsConfigTests: XCTestCase {

    func testDefaultMappingUsesMacCAGS() {
        let config = HomeRowModsConfig()
        XCTAssertEqual(config.modifierAssignments["a"], "lsft")
        XCTAssertEqual(config.modifierAssignments["s"], "lctl")
        XCTAssertEqual(config.modifierAssignments["d"], "lalt")
        XCTAssertEqual(config.modifierAssignments["f"], "lmet")
        XCTAssertEqual(config.modifierAssignments["j"], "rmet")
        XCTAssertEqual(config.modifierAssignments["k"], "ralt")
        XCTAssertEqual(config.modifierAssignments["l"], "rctl")
        XCTAssertEqual(config.modifierAssignments[";"], "rsft")
    }

    func testTimingDefaultsDisableQuickTapAndOffsets() {
        let timing = HomeRowModsConfig().timing
        XCTAssertFalse(timing.quickTapEnabled)
        XCTAssertTrue(timing.tapOffsets.isEmpty)
        XCTAssertEqual(timing.quickTapTermMs, 0)
    }
}
