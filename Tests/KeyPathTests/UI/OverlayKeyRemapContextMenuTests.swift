@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Right-click "Remap…" on an overlay key opens the mapper for that key, with the
/// drawer open or closed. A closed drawer receives the key as a pending selection.
@MainActor
final class OverlayKeyRemapContextMenuTests: XCTestCase {
    override func tearDown() {
        MapperDrawerSelectionRequest.pending = nil
        super.tearDown()
    }

    func testPendingSelectionIsConsumedOnce() {
        MapperDrawerSelectionRequest.pending = ["keyCode": UInt16(57), "inputKey": "caps", "outputKey": "esc"]
        let first = MapperDrawerSelectionRequest.take()
        XCTAssertEqual(first?["inputKey"] as? String, "caps")
        XCTAssertNil(MapperDrawerSelectionRequest.take(), "A consumed selection must not reselect on the next drawer open")
    }

    func testRightClickSelectionMatchesLeftClickPayload() {
        let controller = LiveKeyboardOverlayController.shared
        let key = PhysicalKey(keyCode: 57, label: "caps", x: 0, y: 0, width: 1, height: 1)
        let layerInfo = LayerKeyInfo.mapped(displayLabel: "✦", outputKey: "esc", outputKeyCode: nil)
        let payload = controller.mapperSelection(key: key, layerInfo: layerInfo)
        XCTAssertEqual(payload["keyCode"] as? UInt16, 57)
        XCTAssertEqual(payload["inputKey"] as? String, OverlayKeyboardView.keyCodeToKanataName(57))
        XCTAssertEqual(payload["outputKey"] as? String, "esc")
        XCTAssertEqual(payload["displayLabel"] as? String, "✦")
    }

    func testRemapWithoutMapperOrOnDrawerKeyLeavesNoPendingSelection() {
        let controller = LiveKeyboardOverlayController.shared
        let drawerKey = PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 0, y: 0, width: 1, height: 1)
        XCTAssertEqual(drawerKey.layoutRole, .touchId)
        controller.openMapper(for: drawerKey, layerInfo: nil)
        XCTAssertNil(MapperDrawerSelectionRequest.pending)
    }
}
