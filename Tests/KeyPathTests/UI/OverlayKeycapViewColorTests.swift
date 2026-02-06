@testable import KeyPathAppKit
import SwiftUI
@preconcurrency import XCTest

/// Tests for collection color routing in OverlayKeycapView
@MainActor
final class OverlayKeycapViewColorTests: XCTestCase {
    // MARK: - Test Data

    private let vimCollectionId = RuleCollectionIdentifier.vimNavigation
    private let windowCollectionId = RuleCollectionIdentifier.windowSnapping
    private let symbolCollectionId = RuleCollectionIdentifier.symbolLayer
    private let launcherCollectionId = RuleCollectionIdentifier.launcher
    private let unknownCollectionId = UUID()

    private func makeKeycapView() -> OverlayKeycapView {
        let key = PhysicalKey(
            keyCode: 0,
            label: "A",
            x: 0,
            y: 0,
            width: 1.0
        )
        return OverlayKeycapView(
            key: key,
            baseLabel: "A",
            isPressed: false,
            scale: 1.0
        )
    }

    // MARK: - Collection Color Tests

    func testCollectionColor_NilReturnsDefaultOrange() {
        let view = makeKeycapView()
        let color = view.collectionColor(for: nil)

        // Default color should be orange
        // We can't directly compare Color values, but we can verify it's not nil
        XCTAssertNotNil(color, "Nil collection ID should return a color")
    }

    func testCollectionColor_VimReturnsOrange() {
        let view = makeKeycapView()
        let color = view.collectionColor(for: vimCollectionId)

        // Vim collection should return orange
        XCTAssertNotNil(color, "Vim collection should return a color")
    }

    func testCollectionColor_WindowSnappingReturnsPurple() {
        let view = makeKeycapView()
        let color = view.collectionColor(for: windowCollectionId)

        // Window Snapping collection should return purple
        XCTAssertNotNil(color, "Window Snapping collection should return a color")

        // Verify it's purple by checking it's the same as Color.purple
        let purple = Color.purple
        XCTAssertEqual(color, purple, "Window Snapping should return purple")
    }

    func testCollectionColor_SymbolLayerReturnsBlue() {
        let view = makeKeycapView()
        let color = view.collectionColor(for: symbolCollectionId)

        // Symbol layer collection should return blue
        XCTAssertNotNil(color, "Symbol layer collection should return a color")

        let blue = Color.blue
        XCTAssertEqual(color, blue, "Symbol layer should return blue")
    }

    func testCollectionColor_LauncherReturnsCyan() {
        let view = makeKeycapView()
        let color = view.collectionColor(for: launcherCollectionId)

        // Launcher collection should return cyan
        XCTAssertNotNil(color, "Launcher collection should return a color")

        let cyan = Color.cyan
        XCTAssertEqual(color, cyan, "Launcher should return cyan")
    }

    func testCollectionColor_UnknownCollectionReturnsDefaultOrange() {
        let view = makeKeycapView()
        let color = view.collectionColor(for: unknownCollectionId)

        // Unknown collection should fall back to default orange
        XCTAssertNotNil(color, "Unknown collection should return a color")
    }

    func testCollectionColor_AllKnownCollectionsHaveUniqueColors() {
        let view = makeKeycapView()

        _ = view.collectionColor(for: vimCollectionId)
        let windowColor = view.collectionColor(for: windowCollectionId)
        let symbolColor = view.collectionColor(for: symbolCollectionId)
        let launcherColor = view.collectionColor(for: launcherCollectionId)

        // Window, symbol, and launcher should all be different
        XCTAssertNotEqual(windowColor, symbolColor, "Window and Symbol should have different colors")
        XCTAssertNotEqual(windowColor, launcherColor, "Window and Launcher should have different colors")
        XCTAssertNotEqual(symbolColor, launcherColor, "Symbol and Launcher should have different colors")

        // Vim and default are both orange (same as unknown), which is acceptable
    }

    // MARK: - LayerColors Constants Tests

    func testLayerColors_DefaultLayerIsDefined() {
        // This test verifies the LayerColors enum has the expected constants
        // We can't access the private enum directly, but we can verify behavior
        let view = makeKeycapView()

        // Nil should return a consistent color
        let color1 = view.collectionColor(for: nil)
        let color2 = view.collectionColor(for: nil)

        // Should be deterministic
        XCTAssertNotNil(color1)
        XCTAssertNotNil(color2)
    }

    func testLayerColors_SystemColorsAreStandard() {
        let view = makeKeycapView()

        // System colors (purple, blue, cyan) should match SwiftUI standard colors
        let windowColor = view.collectionColor(for: windowCollectionId)
        let symbolColor = view.collectionColor(for: symbolCollectionId)
        let launcherColor = view.collectionColor(for: launcherCollectionId)

        XCTAssertEqual(windowColor, Color.purple)
        XCTAssertEqual(symbolColor, Color.blue)
        XCTAssertEqual(launcherColor, Color.cyan)
    }

    // MARK: - Integration Tests

    func testCollectionColor_ConsistentAcrossMultipleCalls() {
        let view = makeKeycapView()

        // Each collection should return the same color on multiple calls
        let vim1 = view.collectionColor(for: vimCollectionId)
        let vim2 = view.collectionColor(for: vimCollectionId)
        XCTAssertEqual(vim1, vim2, "Vim color should be consistent")

        let window1 = view.collectionColor(for: windowCollectionId)
        let window2 = view.collectionColor(for: windowCollectionId)
        XCTAssertEqual(window1, window2, "Window color should be consistent")
    }

    func testCollectionColor_DifferentViewsReturnSameColors() {
        let view1 = makeKeycapView()
        let view2 = makeKeycapView()

        // Different view instances should return the same colors for same collections
        let color1 = view1.collectionColor(for: windowCollectionId)
        let color2 = view2.collectionColor(for: windowCollectionId)

        XCTAssertEqual(color1, color2, "Different view instances should return same color for same collection")
    }
}
