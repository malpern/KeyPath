@testable import KeyPathAppKit
import XCTest

final class LayerKeyMapperLabelTests: XCTestCase {
    func testHyperDetectionWithRightSideAliases() {
        let outputs: Set = ["rctl", "rmet", "ralt", "rsft"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { key in key }
        XCTAssertEqual(label, "✦")
    }

    func testHyperDetectionWithPlainModifierNames() {
        let outputs: Set = ["lctl", "lmet", "lalt", "lsft"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { key in key }
        XCTAssertEqual(label, "✦")
    }

    func testMehDetectionWithMixedAliases() {
        let outputs: Set = ["control", "lalt", "shift"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { key in key }
        XCTAssertEqual(label, "◆")
    }

    func testSingleKeyFallback() {
        let outputs: Set = ["escape"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { _ in "⎋" }
        XCTAssertEqual(label, "⎋")
    }

    func testComboFallbackJoinsLabels() {
        let outputs: Set = ["lmet", "left"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { key in
            switch key {
            case "lmet": "⌘"
            case "left": "←"
            default: key
            }
        }
        XCTAssertEqual(Set(label ?? ""), Set(["⌘", "←"]), "Should include both labels")
    }
}
