@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Right-click "Remap…" on an overlay key opens the mapper for that key, with the
/// drawer open or closed. A closed drawer receives the key as a pending selection.
@MainActor
final class OverlayKeyRemapContextMenuTests: XCTestCase {
    override func tearDown() async throws {
        MapperDrawerSelectionRequest.pending = nil
        try await super.tearDown()
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

    // MARK: - Reset to Default

    private func rule(_ input: String, layer: RuleCollectionLayer = .base, pack: String? = nil) -> CustomRule {
        CustomRule(input: input, action: .keystroke(key: "esc"), targetLayer: layer, packSource: pack)
    }

    func testResetOffersOnlyTheUsersRuleOnTheCurrentLayer() {
        let mine = rule("A")
        let rules = [rule("a", layer: .navigation), rule("a", pack: "home-row-mods"), mine]
        XCTAssertEqual(LiveKeyboardOverlayController.resettableRule(input: "a", layer: "base", in: rules)?.id, mine.id)
        XCTAssertNil(LiveKeyboardOverlayController.resettableRule(input: "b", layer: "base", in: rules))
    }

    func testPackRulesAndOtherLayersAreNeverResettable() {
        let rules = [rule("caps", pack: "caps-lock-remap"), rule("j", layer: .navigation)]
        XCTAssertNil(LiveKeyboardOverlayController.resettableRule(input: "caps", layer: "base", in: rules))
        XCTAssertNil(LiveKeyboardOverlayController.resettableRule(input: "j", layer: "base", in: rules))
        XCTAssertEqual(LiveKeyboardOverlayController.resettableInputs(in: rules, layer: "nav"), ["j"])
        XCTAssertEqual(LiveKeyboardOverlayController.resettableInputs(in: rules, layer: "base"), [])
    }
}
