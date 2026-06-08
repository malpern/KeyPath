@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
@preconcurrency import XCTest

/// Tests for the "unmapped keys on layers" overlay setting: a transparent
/// (unmapped) key leaves layer mode — rendering base-style — when the user
/// prefers `.baseLayer`, while mapped keys keep full layer styling.
@MainActor
final class UnmappedLayerKeyStyleTests: KeyPathTestCase {
    private var savedStyle: UnmappedLayerKeyStyle!

    override func setUp() async throws {
        try await super.setUp()
        // Tripwire: the isLayerMode tests drive the view through
        // PreferencesService.shared, which only works because the default
        // @Environment(\.services) ServiceContainer uses `.shared` for its
        // preferences. Fail loudly (not silently) if that ever decouples.
        XCTAssertTrue(
            ServiceContainer().preferences === PreferencesService.shared,
            "Tests assume the default ServiceContainer uses PreferencesService.shared"
        )
        savedStyle = PreferencesService.shared.unmappedLayerKeyStyle
    }

    override func tearDown() async throws {
        PreferencesService.shared.unmappedLayerKeyStyle = savedStyle
        try await super.tearDown()
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

    private func keycap(
        keyCode: UInt16,
        label: String,
        layer: String = "nav",
        info: LayerKeyInfo?,
        zoneSubtitle: String? = nil
    ) -> OverlayKeycapView {
        OverlayKeycapView(
            key: PhysicalKey(keyCode: keyCode, label: label, x: 1, y: 2, width: 1, height: 1),
            baseLabel: label,
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

    func testUnmappedKey_withZoneSubtitle_baseLayerPref_leavesLayerMode() {
        // A subtitle should not force a transparent/pass-through key into layer
        // styling. The subtitle can still render inline on the base-styled keycap.
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(layer: "nav", info: .transparent(fallbackLabel: "Q"), zoneSubtitle: "◀")
        XCTAssertFalse(view.isLayerMode, "Transparent keys keep base styling even when a subtitle exists")
    }

    func testExplicitlyBlockedKey_baseLayerPref_leavesLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 47,
            label: ".",
            info: LayerKeyInfo(
                displayLabel: "",
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false
            )
        )
        XCTAssertTrue(view.isVisuallyUnmappedLayerKey)
        XCTAssertFalse(view.isLayerMode, "XX-blocked punctuation should render base-style under the base-style preference")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: GMKColorway.default.alphaBaseColor)
        )
    }

    func testFallbackSameLabelNoOutput_baseLayerPref_leavesLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 44,
            label: "/",
            info: LayerKeyInfo(
                displayLabel: "/",
                outputKey: nil,
                outputKeyCode: nil,
                isTransparent: false,
                isLayerSwitch: false
            )
        )
        XCTAssertTrue(view.isVisuallyUnmappedLayerKey)
        XCTAssertFalse(view.isLayerMode, "Fallback punctuation with no output should render as visually unmapped")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: GMKColorway.default.alphaBaseColor)
        )
    }

    func testLiteralPunctuationIdentity_baseLayerPref_leavesLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 44,
            label: "/",
            info: LayerKeyInfo(
                displayLabel: "/",
                outputKey: "/",
                outputKeyCode: 44,
                isTransparent: false,
                isLayerSwitch: false
            )
        )
        XCTAssertTrue(view.isVisuallyUnmappedLayerKey)
        XCTAssertFalse(view.isLayerMode, "Literal slash output should normalize as identity/pass-through")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: GMKColorway.default.alphaBaseColor)
        )
    }

    func testTransparentFn_baseLayerPref_leavesLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 63,
            label: "fn",
            info: .transparent(fallbackLabel: "fn")
        )
        XCTAssertTrue(view.isVisuallyUnmappedLayerKey)
        XCTAssertFalse(view.isLayerMode, "Transparent fn should not pick up layer fallback coloring")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: GMKColorway.default.alphaBaseColor)
        )
    }

    func testFnModifierOutput_baseLayerPref_leavesLayerMode() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 63,
            label: "fn",
            info: LayerKeyInfo(
                displayLabel: "fn",
                outputKey: "fn",
                outputKeyCode: 63,
                isTransparent: false,
                isLayerSwitch: false
            )
        )
        XCTAssertTrue(view.isVisuallyUnmappedLayerKey)
        XCTAssertFalse(view.isLayerMode, "fn should not be treated as an active layer mapping")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: GMKColorway.default.alphaBaseColor)
        )
    }

    func testMappedSlashWithCollection_baseLayerPref_keepsCollectionLayerColor() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 44,
            label: "/",
            info: .mapped(
                displayLabel: "find",
                outputKey: "f",
                outputKeyCode: 3,
                collectionId: RuleCollectionIdentifier.vimNavigation,
                vimLabel: "find"
            )
        )
        XCTAssertFalse(view.isVisuallyUnmappedLayerKey)
        XCTAssertTrue(view.isLayerMode, "Mapped punctuation should still render as an active layer key")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.vimNavigation))
        )
    }

    func testNavIdentityMapping_baseLayerPref_keepsCollectionLayerColor() {
        PreferencesService.shared.unmappedLayerKeyStyle = .baseLayer
        let view = keycap(
            keyCode: 0,
            label: "A",
            info: .mapped(
                displayLabel: "A",
                outputKey: "a",
                outputKeyCode: 0,
                collectionId: RuleCollectionIdentifier.vimNavigation
            )
        )

        XCTAssertTrue(view.isNavIdentityMapping)
        XCTAssertFalse(view.isVisuallyUnmappedLayerKey)
        XCTAssertTrue(view.isLayerMode, "Nav identity mappings should keep collection styling")
        XCTAssertEqual(
            String(describing: view.backgroundColor),
            String(describing: KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.vimNavigation))
        )
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

    // MARK: - FloatingLabelVisibility (the keyboard-view half)

    /// Under base-style the keyboard view forces `isLayerMode: false` into
    /// FloatingLabelVisibility so unmapped keys' floating legends return —
    /// while mapped keys stay hidden via `remappedLabels`.
    func testFloatingLabels_baseStyle_showsUnmapped_hidesRemapped() {
        let visibility = FloatingLabelVisibility(
            labelToKeyCode: ["A": 0, "S": 1],
            isLauncherMode: false,
            isLayerMode: false, // what baseStyleUnmapped forces
            vimHintsActive: false,
            remappedLabels: ["S"], // S is mapped on this layer
            zoneSubtitleLabels: []
        )
        XCTAssertTrue(visibility.isVisible("A"), "Unmapped key's floating legend shows under base-style")
        XCTAssertFalse(visibility.isVisible("S"), "Mapped key stays excluded via remappedLabels")
    }

    func testFloatingLabels_dimmed_suppressesAll() {
        let visibility = FloatingLabelVisibility(
            labelToKeyCode: ["A": 0],
            isLauncherMode: false,
            isLayerMode: true, // dimmed style keeps real layer mode
            vimHintsActive: false,
            remappedLabels: [],
            zoneSubtitleLabels: []
        )
        XCTAssertFalse(visibility.isVisible("A"), "Dimmed style keeps floating legends suppressed on layers")
    }

    // MARK: - Persistence

    func testPreference_persistsAcrossReload() {
        let writer = PreferencesService()
        writer.unmappedLayerKeyStyle = .dimmed
        // A fresh instance hydrates from UserDefaults in init().
        let reloaded = PreferencesService()
        XCTAssertEqual(reloaded.unmappedLayerKeyStyle, .dimmed, "Value should survive a UserDefaults round-trip")
        writer.unmappedLayerKeyStyle = .baseLayer // restore default-backed state
    }
}
