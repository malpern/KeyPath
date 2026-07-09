@testable import KeyPathAppKit
import KeyPathRulesCore
import SwiftUI
@preconcurrency import XCTest

/// Tests for collection color routing in OverlayKeycapView.
///
/// The taxonomy is semantic: keys are colored by *what their layer does*, grouped
/// into families (navigation = green, window/spaces = purple, symbols = blue,
/// launcher/apps = teal, editor = steel blue, modifier-producing = muted blue-gray). Anything
/// without a vibrant category falls to the calm `keycapMapped` blue-gray — NOT orange.
@MainActor
final class OverlayKeycapViewColorTests: XCTestCase {
    // MARK: - Family routing

    func testCollectionColor_NavigationFamilyIsGreen() {
        for id in [
            RuleCollectionIdentifier.vimNavigation,
            RuleCollectionIdentifier.kindaVim,
            RuleCollectionIdentifier.homeRowArrows,
            RuleCollectionIdentifier.vallackNavigation
        ] {
            XCTAssertEqual(
                KeycapSymbols.collectionColor(for: id),
                KeyPathColors.layerGreen,
                "Navigation-family collection should be green"
            )
        }
    }

    func testCollectionColor_WindowFamilyIsPurple() {
        for id in [RuleCollectionIdentifier.windowSnapping, RuleCollectionIdentifier.missionControl] {
            XCTAssertEqual(KeycapSymbols.collectionColor(for: id), KeyPathColors.layerPurple)
        }
    }

    func testCollectionColor_SymbolsFamilyIsBlue() {
        for id in [
            RuleCollectionIdentifier.symbolLayer,
            RuleCollectionIdentifier.numpadLayer,
            RuleCollectionIdentifier.autoShiftSymbols
        ] {
            XCTAssertEqual(KeycapSymbols.collectionColor(for: id), KeyPathColors.layerBlue)
        }
    }

    func testCollectionColor_LauncherFamilyIsTeal() {
        for id in [RuleCollectionIdentifier.launcher, RuleCollectionIdentifier.funLayer] {
            XCTAssertEqual(KeycapSymbols.collectionColor(for: id), KeyPathColors.layerTeal)
        }
    }

    func testCollectionColor_ModifierFamilyIsMutedModifierColor() {
        for id in [
            RuleCollectionIdentifier.homeRowMods,
            RuleCollectionIdentifier.homeRowLayerToggles,
            RuleCollectionIdentifier.capsLockHyperKey
        ] {
            XCTAssertEqual(KeycapSymbols.collectionColor(for: id), KeyPathColors.layerModifier)
            XCTAssertNotEqual(KeycapSymbols.collectionColor(for: id), KeyPathColors.layerOrange)
        }
    }

    // MARK: - Calm default (the orange-everywhere fix)

    func testCollectionColor_NilFallsToCalmMapped() {
        XCTAssertEqual(KeycapSymbols.collectionColor(for: nil), KeyPathColors.keycapMapped)
    }

    func testCollectionColor_UnknownFallsToCalmMapped() {
        XCTAssertEqual(KeycapSymbols.collectionColor(for: UUID()), KeyPathColors.keycapMapped)
    }

    func testCollectionColor_SimpleRemapsAreNotOrange() {
        // Regression: these used to fall through the switch to the orange default,
        // making unrelated remaps (and F-keys mid-transition) flash orange.
        for id in [
            RuleCollectionIdentifier.macFunctionKeys,
            RuleCollectionIdentifier.capsLockRemap,
            RuleCollectionIdentifier.escapeRemap,
            RuleCollectionIdentifier.deleteRemap,
            RuleCollectionIdentifier.leaderKey,
            RuleCollectionIdentifier.customMappings,
            RuleCollectionIdentifier.chordGroups,
            RuleCollectionIdentifier.sequences
        ] {
            let color = KeycapSymbols.collectionColor(for: id)
            XCTAssertEqual(color, KeyPathColors.keycapMapped, "Simple remap should be calm-mapped")
            XCTAssertNotEqual(color, KeyPathColors.layerOrange, "Simple remap must not be orange")
        }
    }

    // MARK: - Family distinctness & determinism

    func testCollectionColor_FamiliesAreDistinct() {
        let nav = KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.vimNavigation)
        let window = KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.windowSnapping)
        let symbols = KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.symbolLayer)
        let launcher = KeycapSymbols.collectionColor(for: RuleCollectionIdentifier.launcher)
        let colors = [nav, window, symbols, launcher]
        for (i, a) in colors.enumerated() {
            for b in colors[(i + 1)...] {
                XCTAssertNotEqual(a, b, "Distinct families must have distinct colors")
            }
        }
    }

    func testCollectionColor_IsDeterministic() {
        let id = RuleCollectionIdentifier.windowSnapping
        XCTAssertEqual(KeycapSymbols.collectionColor(for: id), KeycapSymbols.collectionColor(for: id))
    }
}
