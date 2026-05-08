import AppKit
@testable import KeyPathAppKit
import KeyPathCore
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

    func testPackCard_NotInstalled() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape") else {
            return XCTFail("Pack not found")
        }
        let view = PackCardView(
            pack: pack,
            isInstalled: false,
            onSelect: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "pack-card-not-installed")
    }

    func testPackCard_Installed() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape") else {
            return XCTFail("Pack not found")
        }
        let view = PackCardView(
            pack: pack,
            isInstalled: true,
            onSelect: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "pack-card-installed")
    }

    func testPackCard_HomeRowMods() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.home-row-mods") else {
            return XCTFail("Pack not found")
        }
        let view = PackCardView(
            pack: pack,
            isInstalled: false,
            onSelect: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "pack-card-hrm")
    }

    func testPackCard_VimNavigation() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.vim-navigation") else {
            return XCTFail("Pack not found")
        }
        let view = PackCardView(
            pack: pack,
            isInstalled: true,
            onSelect: {}
        )
        assertScreenshot(of: view, size: SnapshotSize.card, named: "pack-card-vim-installed")
    }

    // MARK: - Overlay with Tap-Hold Idle Labels

    func testOverlay_WithTapHoldIdleLabels() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
        viewModel.tapHoldIdleLabels = [
            57: "⎋",  // Caps Lock shows Escape when idle
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

    // MARK: - Helpers

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
