@testable import KeyPathAppKit
import XCTest

final class LayerKeyMapperLabelTests: XCTestCase {
    func testHyperDetectionWithRightSideAliases() {
        let outputs: Set<String> = ["rctl", "rmet", "ralt", "rsft"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { key in key }
        XCTAssertEqual(label, "✦")
    }

    func testMehDetectionWithMixedAliases() {
        let outputs: Set<String> = ["control", "lalt", "shift"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { key in key }
        XCTAssertEqual(label, "◆")
    }

    func testSingleKeyFallback() {
        let outputs: Set<String> = ["escape"]
        let label = LayerKeyMapper.labelForOutputKeys(outputs) { _ in "⎋" }
        XCTAssertEqual(label, "⎋")
    }

    func testComboFallbackJoinsLabels() {
        let outputs: Set<String> = ["lmet", "left"]
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
