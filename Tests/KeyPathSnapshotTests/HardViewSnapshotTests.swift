@testable import KeyPathAppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Snapshot tests for views with heavy dependencies (@AppStorage, view models, 25+ params).
/// These require UserDefaults isolation and factory methods for complex init signatures.
final class HardViewSnapshotTests: ScreenshotTestCase {
    // MARK: - OverlayInspectorPanel — Custom Rules Tab

    func testInspectorCustomRulesTab() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .customRules,
            hasCustomRules: true
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "tap-hold-custom-rules-tab",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    func testInspectorCustomRulesWithApps() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .customRules,
            hasCustomRules: true,
            appKeymaps: [MockFactories.safariKeymap, MockFactories.terminalKeymap]
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "window-mgmt-custom-rules",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    func testInspectorKarabinerComparison() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .customRules,
            hasCustomRules: true
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "karabiner-custom-rules-comparison",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - OverlayInspectorPanel — Launchers Tab

    func testInspectorLaunchersTab() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .launchers,
            isSettingsShelfActive: false
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "action-uri-inspector-toolbar",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    func testInspectorActivationMode() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .launchers,
            isSettingsShelfActive: false
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "action-uri-activation-mode",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - OverlayInspectorPanel — Settings Shelf (Keymaps)

    func testInspectorSettingsToolbar() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .keycaps,
            isSettingsShelfActive: true,
            hasCustomRules: false
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "alt-layouts-settings-toolbar",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    func testInspectorKeymapPicker() {
        let view = MockFactories.inspectorPanel(
            selectedSection: .keyboard,
            isSettingsShelfActive: true,
            hasCustomRules: false
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "alt-layouts-keymap-picker",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    // MARK: - LiveKeyboardOverlayView

    func testLiveKeyboardOverlayBase() {
        let viewModel = MockFactories.keyboardVisualizationViewModel()
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
            named: "install-overlay-base",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }
}
