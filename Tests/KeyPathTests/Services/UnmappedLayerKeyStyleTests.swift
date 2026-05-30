@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
import XCTest

/// Tests for the "unmapped keys on layers" overlay setting: a transparent
/// (unmapped) key leaves layer mode — rendering base-style — when the user
/// prefers `.baseLayer`, while mapped keys keep full layer styling.
@MainActor
final class UnmappedLayerKeyStyleTests: XCTestCase {
    private var savedStyle: UnmappedLayerKeyStyle!

    override func setUp() {
        super.setUp()
        savedStyle = PreferencesService.shared.unmappedLayerKeyStyle
    }

    override func tearDown() {
        PreferencesService.shared.unmappedLayerKeyStyle = savedStyle
        super.tearDown()
    }

    private func keycap(layer: String, info: LayerKeyInfo?, zoneSubtitle: String? = nil) -> OverlayKeycapView {
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 12, label: "Q", x: 1, y: 2, width: 1, height: 1),
            baseLabel: "Q",
            isPressed: false,
            scale: 1.0,
            currentLayerName: layer,
            layerKeyInfo: info,
            zoneSubtitle: zoneSubtitle
        )
    }

    func testUnmappedKey_baseLayerPref_leavesLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(layer: "nav", info: .transparent(fallbackLabel: "Q"))
        XCTAssertFalse(
            view.isLayerMode,
            "An unmapped key should render base-style (not layer mode) when base-style is preferred"
        )
    }

    func testUnmappedKey_nilInfo_baseLayerPref_leavesLayerMode() {
        // Production emits transparent LayerKeyInfo per key, but hand-built maps
        // (and passthrough) use nil — both mean "unmapped" and should render base.
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(layer: "nav", info: nil)
        XCTAssertFalse(view.isLayerMode, "A nil-info (unmapped) key should also render base-style")
    }

    func testUnmappedKey_withZoneSubtitle_staysInLayerMode() {
        // A key carrying a nav-hint subtitle keeps layer styling so the subtitle
        // still renders (avoids a stray subtitle on a base-styled keycap).
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(layer: "nav", info: .transparent(fallbackLabel: "Q"), zoneSubtitle: "◀")
        XCTAssertTrue(view.isLayerMode, "Keys with a zone subtitle keep layer styling even under base-style")
    }

    func testUnmappedKey_dimmedPref_staysInLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .dimmed
        let view = keycap(layer: "nav", info: .transparent(fallbackLabel: "Q"))
        XCTAssertTrue(
            view.isLayerMode,
            "An unmapped key should stay dimmed (layer mode) when dimmed is preferred"
        )
    }

    func testMappedKey_baseLayerPref_staysInLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            layer: "nav",
            info: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: 123)
        )
        XCTAssertTrue(
            view.isLayerMode,
            "Mapped keys keep full layer styling regardless of the unmapped-key preference"
        )
    }

    func testBaseLayer_isNeverLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .dimmed
        let view = keycap(layer: "base", info: .transparent(fallbackLabel: "Q"))
        XCTAssertFalse(view.isLayerMode, "The base layer is never in layer mode")
    }
}
