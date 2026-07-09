import AppKit
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import SnapshotTesting
import SwiftUI
import XCTest

/// Scenario-based snapshot tests: views rendered in post-interaction states.
///
/// Unlike static snapshots (render a view with defaults), these set up
/// specific scenarios a user would reach through interaction — installing
/// a pack, selecting a mapping, resolving a conflict — and verify the
/// visual result.
final class ScenarioSnapshotTests: ScreenshotTestCase {
    // MARK: - Mapper Keycap Pair Scenarios

    func testMapperKeycapPair_PlainKeyRemap() {
        let view = MapperKeycapPair(
            inputLabel: "A",
            inputKeyCode: 0,
            outputLabel: "B",
            isRecordingInput: false,
            isRecordingOutput: false,
            onInputTap: {},
            onOutputTap: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "mapper-pair-plain-remap")
    }

    func testMapperKeycapPair_HyperMapping() {
        let view = MapperKeycapPair(
            inputLabel: "⇪",
            inputKeyCode: 57,
            outputLabel: "✦",
            isRecordingInput: false,
            isRecordingOutput: false,
            onInputTap: {},
            onOutputTap: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "mapper-pair-hyper")
    }

    func testMapperKeycapPair_AppLaunch() {
        let appInfo = AppLaunchInfo(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            icon: NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
        )
        let view = MapperKeycapPair(
            inputLabel: "S",
            inputKeyCode: 1,
            outputLabel: "Safari",
            isRecordingInput: false,
            isRecordingOutput: false,
            outputAppInfo: appInfo,
            onInputTap: {},
            onOutputTap: {}
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.card,
            named: "mapper-pair-app-launch",
            precision: 0.97,
            perceptualPrecision: 0.97
        )
    }

    func testMapperKeycapPair_SystemAction() {
        let actionInfo = SystemActionInfo(
            id: "spotlight",
            name: "Spotlight",
            sfSymbol: "magnifyingglass"
        )
        let view = MapperKeycapPair(
            inputLabel: "D",
            inputKeyCode: 2,
            outputLabel: "Spotlight",
            isRecordingInput: false,
            isRecordingOutput: false,
            outputSystemActionInfo: actionInfo,
            onInputTap: {},
            onOutputTap: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "mapper-pair-system-action")
    }

    func testMapperKeycapPair_RecordingOutput() {
        let view = MapperKeycapPair(
            inputLabel: "A",
            inputKeyCode: 0,
            outputLabel: "Press a key…",
            isRecordingInput: false,
            isRecordingOutput: true,
            onInputTap: {},
            onOutputTap: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "mapper-pair-recording")
    }

    // MARK: - Overlay Keycap Scenarios

    func testKeycap_DefaultIdle() {
        let key = makePhysicalKey(keyCode: 0, label: "A")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-idle")
    }

    func testKeycap_Pressed() {
        let key = makePhysicalKey(keyCode: 0, label: "A")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: true,
            scale: 1.0
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-pressed")
    }

    func testKeycap_HoldActiveWithHyper() {
        let key = makePhysicalKey(keyCode: 57, label: "⇪", width: 1.75)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "⇪",
            isPressed: true,
            scale: 1.0,
            holdLabel: "✦",
            isHoldActive: true
        )
        assertScreenshot(of: view, size: wideKeycapSize, named: "keycap-hold-hyper")
    }

    func testKeycap_TapHoldIdleLabel() {
        let key = makePhysicalKey(keyCode: 57, label: "⇪", width: 1.75)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "⇪",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "base",
            tapHoldIdleLabel: "⎋"
        )
        assertScreenshot(of: view, size: wideKeycapSize, named: "keycap-taphold-idle-esc")
    }

    func testKeycap_WithLayerMapping() {
        let key = makePhysicalKey(keyCode: 4, label: "H")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-layer-mapped")
    }

    func testKeycap_Selected() {
        let key = makePhysicalKey(keyCode: 0, label: "A")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0,
            isSelected: true,
            isInspectorVisible: true
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-selected")
    }

    // MARK: - Pack Card Scenarios

    // MARK: - Overlay with Tap-Hold Idle Labels

    func testOverlay_WithTapHoldIdleLabels() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
        viewModel.tapHoldIdleLabels = [
            57: "⎋", // Caps Lock shows Escape when idle
        ]
        let uiState = MockFactories.overlayUIState()
        let view = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: 0,
            isMapperAvailable: true,
            kanataViewModel: nil
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 1200, height: 450),
            named: "overlay-with-taphold-idle",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - Collection-Colored Keycaps

    func testKeycap_VimCollectionColor() {
        let key = makePhysicalKey(keyCode: 4, label: "H")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: RuleCollectionIdentifier.vimNavigation
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-vim-orange")
    }

    func testKeycap_WindowSnappingColor() {
        let key = makePhysicalKey(keyCode: 4, label: "H")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: RuleCollectionIdentifier.windowSnapping
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "window",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-window-purple")
    }

    func testKeycap_SymbolLayerColor() {
        let key = makePhysicalKey(keyCode: 18, label: "1")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "!",
            outputKey: "S-1",
            outputKeyCode: nil,
            collectionId: RuleCollectionIdentifier.symbolLayer
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "1",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "sym",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-symbol-blue")
    }

    // MARK: - Mapper Input with Shift Symbol

    func testMapperInputKeycap_WithShiftSymbol() {
        let view = MapperInputKeycap(
            label: "1",
            keyCode: 18,
            isRecording: false,
            customShiftSymbol: "!",
            onTap: {}
        )
        assertScreenshot(of: view, size: CGSize(width: 120, height: 120), named: "mapper-input-with-shift")
    }

    func testMapperInputKeycap_CapsLockWide() {
        let view = MapperInputKeycap(
            label: "⇪",
            keyCode: 57,
            isRecording: false,
            onTap: {}
        )
        assertScreenshot(of: view, size: CGSize(width: 120, height: 120), named: "mapper-input-capslock")
    }

    func testMapperKeycapPair_WithCustomShiftOutput() {
        let view = MapperKeycapPair(
            inputLabel: "1",
            inputKeyCode: 18,
            outputLabel: "2",
            isRecordingInput: false,
            isRecordingOutput: false,
            onInputTap: {},
            onOutputTap: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "mapper-pair-number-remap")
    }

    // MARK: - Overlay with Inspector Open

    func testOverlay_WithInspectorOpen() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
        let uiState = MockFactories.overlayUIState(isInspectorOpen: true)
        let view = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: 450,
            isMapperAvailable: true,
            kanataViewModel: nil
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 1650, height: 450),
            named: "overlay-with-inspector-open",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - Overlay with Collection-Colored Keys (Vim Nav Layer)

    func testOverlay_VimNavLayer() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
        viewModel.currentLayerName = "nav"
        // Set up vim nav layer mappings with vimLabels (arrows must survive augmentation)
        viewModel.layerKeyMap = Self.vimNavLayerMap
        let uiState = MockFactories.overlayUIState()
        let view = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: 0,
            isMapperAvailable: true,
            kanataViewModel: nil
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 1200, height: 450),
            named: "overlay-vim-nav-layer",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - HJKL Arrow Regression Tests

    /// Base layer should show normal HJKL letter floating labels.
    /// Regression: floating labels were hidden when KindaVim pack was installed
    /// even in insert mode, leaving HJKL blank.
    func testOverlay_BaseLayer_HJKLShowLetters() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
        viewModel.currentLayerName = "base"
        let uiState = MockFactories.overlayUIState()
        let view = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: 0,
            isMapperAvailable: true,
            kanataViewModel: nil
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 1200, height: 450),
            named: "overlay-base-hjkl-letters",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    /// Nav layer HJKL keycaps should show arrow symbols (← ↓ ↑ →) with vimLabels.
    /// Regression: augmentation overwrote vimLabels, showing "H — Left" text instead.
    func testKeycap_NavLayer_HArrow() {
        let key = makePhysicalKey(keyCode: 4, label: "H")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: RuleCollectionIdentifier.vimNavigation,
            vimLabel: "←"
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-nav-h-arrow")
    }

    /// Nav layer HJKL keycap should NOT show the key letter in top-left corner
    /// when the action is an arrow symbol.
    func testKeycap_NavLayer_JArrow() {
        let key = makePhysicalKey(keyCode: 38, label: "J")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "↓",
            outputKey: "down",
            outputKeyCode: 125,
            collectionId: RuleCollectionIdentifier.vimNavigation,
            vimLabel: "↓"
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "J",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-nav-j-arrow")
    }

    /// Full overlay on nav layer with HJKL arrows and other vim keys.
    /// Regression: augmentation dropped vimLabels, making HJKL show description text.
    func testOverlay_NavLayer_HJKLArrows() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
        viewModel.currentLayerName = "nav"
        viewModel.layerKeyMap = Self.vimNavLayerMap
        let uiState = MockFactories.overlayUIState()
        let view = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: 0,
            isMapperAvailable: true,
            kanataViewModel: nil
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 1200, height: 450),
            named: "overlay-nav-hjkl-arrows",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - Launcher Mode Keycap Scenarios

    func testKeycap_LauncherMode_WithAppMapping() {
        let key = makePhysicalKey(keyCode: 1, label: "S")
        let mapping = MockFactories.launcherMapping(
            key: "s",
            action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "S",
            isPressed: false,
            scale: 1.0,
            isLauncherMode: true,
            launcherMapping: mapping
        )
        assertScreenshot(
            of: view,
            size: keycapSize,
            named: "keycap-launcher-app-mapped",
            precision: 0.99,
            perceptualPrecision: 0.99
        )
    }

    func testKeycap_LauncherMode_UnmappedKey() {
        let key = makePhysicalKey(keyCode: 12, label: "Q")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "Q",
            isPressed: false,
            scale: 1.0,
            isLauncherMode: true
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-launcher-unmapped")
    }

    // MARK: - Layer Mode Keycap Scenarios

    func testKeycap_LayerMode_WindowAction() {
        let key = makePhysicalKey(keyCode: 4, label: "H")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "Left Half",
            outputKey: "left-half",
            outputKeyCode: nil,
            collectionId: RuleCollectionIdentifier.windowSnapping
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "window",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-layer-window-action")
    }

    func testKeycap_LayerMode_UnmappedKey() {
        let key = makePhysicalKey(keyCode: 12, label: "Q")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "Q",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav"
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-layer-unmapped")
    }

    func testKeycap_LayerMode_SystemAction() {
        let key = makePhysicalKey(keyCode: 1, label: "S")
        let layerInfo = LayerKeyInfo.systemAction(
            action: "spotlight",
            description: "Spotlight"
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "S",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-layer-system-action")
    }

    func testKeycap_LayerMode_ZoneSubtitle() {
        let key = makePhysicalKey(keyCode: 0, label: "A")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "base",
            zoneSubtitle: "⌃"
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-zone-subtitle")
    }

    // MARK: - Base Layer Keycap Scenarios

    func testKeycap_BaseLayer_DualSymbol() {
        let key = makePhysicalKey(keyCode: 18, label: "1")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "1",
            isPressed: false,
            scale: 1.0,
            shiftLabelOverride: "!"
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-base-dual-symbol")
    }

    func testKeycap_BaseLayer_FunctionKey() {
        let key = makePhysicalKey(keyCode: 122, label: "F1", width: 1.0, height: 0.5)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "F1",
            isPressed: false,
            scale: 1.0
        )
        assertScreenshot(of: view, size: CGSize(width: 80, height: 50), named: "keycap-base-function-key")
    }

    func testKeycap_BaseLayer_NarrowModifier() {
        let key = makePhysicalKey(keyCode: 63, label: "fn", width: 1.0)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "fn",
            isPressed: false,
            scale: 1.0
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-base-narrow-modifier")
    }

    func testKeycap_BaseLayer_Arrow() {
        let key = makePhysicalKey(keyCode: 123, label: "←", width: 1.0, height: 0.5)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "←",
            isPressed: false,
            scale: 1.0
        )
        assertScreenshot(of: view, size: CGSize(width: 80, height: 50), named: "keycap-base-arrow")
    }

    func testKeycap_BaseLayer_EscKey() {
        let key = makePhysicalKey(keyCode: 53, label: "esc", width: 1.0, height: 0.5)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "esc",
            isPressed: false,
            scale: 1.0
        )
        assertScreenshot(of: view, size: CGSize(width: 80, height: 50), named: "keycap-base-esc")
    }

    func testKeycap_InlineLayer_Arrow() {
        let key = makePhysicalKey(keyCode: 4, label: "H")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "H",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "home-arrows",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-inline-layer-arrow")
    }

    func testKeycap_NavIdentityMapping() {
        let key = makePhysicalKey(keyCode: 0, label: "A")
        let layerInfo = LayerKeyInfo.mapped(
            displayLabel: "A",
            outputKey: "a",
            outputKeyCode: 0,
            collectionId: RuleCollectionIdentifier.vimNavigation
        )
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0,
            currentLayerName: "nav",
            layerKeyInfo: layerInfo
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-nav-identity-mapping")
    }

    // MARK: - Legend Style Scenarios

    func testKeycap_DotsLegend_Alpha() {
        let key = makePhysicalKey(keyCode: 0, label: "A")
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0,
            colorway: GMKColorway.find(id: "dots") ?? .default
        )
        assertScreenshot(of: view, size: keycapSize, named: "keycap-dots-alpha")
    }

    func testKeycap_DotsLegend_Modifier() {
        let key = makePhysicalKey(keyCode: 55, label: "⌘", width: 1.25)
        let view = OverlayKeycapView(
            key: key,
            baseLabel: "⌘",
            isPressed: false,
            scale: 1.0,
            colorway: GMKColorway.find(id: "dots") ?? .default
        )
        assertScreenshot(of: view, size: CGSize(width: 100, height: 80), named: "keycap-dots-modifier")
    }

    // MARK: - Helpers

    /// Standard vim nav layer mapping for HJKL with vimLabels preserved
    private static let vimNavLayerMap: [UInt16: LayerKeyInfo] = [
        4: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: 123, collectionId: RuleCollectionIdentifier.vimNavigation, vimLabel: "←"),
        38: .mapped(displayLabel: "↓", outputKey: "down", outputKeyCode: 125, collectionId: RuleCollectionIdentifier.vimNavigation, vimLabel: "↓"),
        40: .mapped(displayLabel: "↑", outputKey: "up", outputKeyCode: 126, collectionId: RuleCollectionIdentifier.vimNavigation, vimLabel: "↑"),
        37: .mapped(displayLabel: "→", outputKey: "right", outputKeyCode: 124, collectionId: RuleCollectionIdentifier.vimNavigation, vimLabel: "→"),
    ]

    private let keycapSize = CGSize(width: 80, height: 80)
    private let wideKeycapSize = CGSize(width: 120, height: 80)

    private func makePhysicalKey(
        keyCode: UInt16,
        label: String,
        x: Double = 0,
        y: Double = 0,
        width: Double = 1.0,
        height: Double = 1.0
    ) -> PhysicalKey {
        PhysicalKey(
            keyCode: keyCode,
            label: label,
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}
