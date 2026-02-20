@testable import KeyPathAppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Snapshot tests for views requiring environment setup (UserDefaults, store seeding, large param lists).
final class MediumViewSnapshotTests: ScreenshotTestCase {
    // MARK: - KeyboardSelectionGridView

    func testKeyboardSelectionGrid() {
        let view = KeyboardSelectionGridView(
            selectedLayoutId: .constant("ansi-100"),
            isDark: false
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.grid,
            named: "kb-layouts-layout-picker"
        )
    }

    // MARK: - OverlayLaunchersSection

    func testLaunchersSectionPopulated() {
        let mappings = [
            MockFactories.quickLaunchMapping(key: "s", targetName: "Safari", bundleId: "com.apple.Safari"),
            MockFactories.quickLaunchMapping(key: "t", targetName: "Terminal", bundleId: "com.apple.Terminal"),
            MockFactories.quickLaunchMapping(key: "m", targetName: "Messages", bundleId: "com.apple.MobileSMS"),
            MockFactories.quickLaunchMapping(key: "f", targetName: "Finder", bundleId: "com.apple.finder"),
            MockFactories.quickLaunchMapping(key: "g", targetType: .website, targetName: "github.com", bundleId: nil),
        ]
        let view = OverlayLaunchersSection(
            isDark: false,
            testMappings: mappings
        )
        // App icon resolution varies slightly between runs
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "action-uri-launchers-tab",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    func testLaunchersSectionCompact() {
        let mappings = [
            MockFactories.quickLaunchMapping(key: "s", targetName: "Safari", bundleId: "com.apple.Safari"),
            MockFactories.quickLaunchMapping(key: "t", targetName: "Terminal", bundleId: "com.apple.Terminal"),
            MockFactories.quickLaunchMapping(key: "g", targetType: .website, targetName: "github.com", bundleId: nil),
        ]
        let view = OverlayLaunchersSection(
            isDark: false,
            testMappings: mappings
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 500, height: 400),
            named: "use-cases-launchers-tab",
            precision: 0.98,
            perceptualPrecision: 0.98
        )
    }

    func testLaunchersSectionEmpty() {
        let view = OverlayLaunchersSection(
            isDark: false,
            testMappings: []
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.inspector,
            named: "launchers-empty-state"
        )
    }

    // MARK: - OverlayDragHeader

    func testOverlayDragHeaderHealthy() {
        let view = OverlayDragHeader(
            isDark: false,
            fadeAmount: 0,
            height: 32,
            inspectorWidth: 0,
            reduceTransparency: false,
            isInspectorOpen: false,
            isDragging: .constant(false),
            isHoveringButton: .constant(false),
            inputModeIndicator: nil,
            currentLayerName: "base",
            isLauncherMode: false,
            isKanataConnected: true,
            healthIndicatorState: .healthy,
            drawerButtonHighlighted: false,
            onClose: {},
            onToggleInspector: {},
            onHealthTap: {},
            onLayerSelected: { _ in }
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.header,
            named: "install-overlay-health-green"
        )
    }

    func testOverlayDragHeaderDisconnected() {
        let view = OverlayDragHeader(
            isDark: false,
            fadeAmount: 0,
            height: 32,
            inspectorWidth: 0,
            reduceTransparency: false,
            isInspectorOpen: false,
            isDragging: .constant(false),
            isHoveringButton: .constant(false),
            inputModeIndicator: nil,
            currentLayerName: "base",
            isLauncherMode: false,
            isKanataConnected: false,
            healthIndicatorState: .unhealthy(issueCount: 2),
            drawerButtonHighlighted: false,
            onClose: {},
            onToggleInspector: {},
            onHealthTap: {},
            onLayerSelected: { _ in }
        )
        assertScreenshot(
            of: view,
            size: SnapshotSize.header,
            named: "overlay-header-unhealthy"
        )
    }

    func testOverlayDragHeaderCollapsed() {
        let view = OverlayDragHeader(
            isDark: false,
            fadeAmount: 0,
            height: 32,
            inspectorWidth: 0,
            reduceTransparency: false,
            isInspectorOpen: false,
            isDragging: .constant(false),
            isHoveringButton: .constant(false),
            inputModeIndicator: nil,
            currentLayerName: "base",
            isLauncherMode: false,
            isKanataConnected: true,
            healthIndicatorState: .healthy,
            drawerButtonHighlighted: false,
            onClose: {},
            onToggleInspector: {},
            onHealthTap: {},
            onLayerSelected: { _ in }
        )
        assertScreenshot(
            of: view,
            size: CGSize(width: 600, height: 32),
            named: "action-uri-overlay-header"
        )
    }
}
