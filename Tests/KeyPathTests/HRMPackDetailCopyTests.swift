@testable import KeyPathAppKit
import XCTest

/// Regression tests for GitHub issue #805: HRM Pack Detail copy stayed
/// modifier-centric ("no reaching for modifier keys", "Hold them for
/// ⌘ ⇧ ⌥ ⌃", "Home Row Mods assigns F to Command") even after the user
/// switched Hold Behavior to Layers. `PackDetailView`'s mode-aware copy
/// helpers are pure static functions (pack + holdMode in, String out) so
/// they can be tested directly without spinning up a live SwiftUI view /
/// `@State` hierarchy.
final class HRMPackDetailCopyTests: XCTestCase {
    private var homeRowMods: Pack {
        PackRegistry.homeRowMods
    }

    private var homeRowArrows: Pack {
        PackRegistry.homeRowArrows
    }

    func testTaglineIsModifierCentricByDefault() {
        let tagline = PackDetailView.displayTagline(for: homeRowMods, holdMode: .modifiers)
        XCTAssertEqual(tagline, homeRowMods.tagline)
        XCTAssertTrue(tagline.contains("modifier keys"))
    }

    func testTaglineSwitchesAwayFromModifierCopyInLayerMode() {
        let tagline = PackDetailView.displayTagline(for: homeRowMods, holdMode: .layers)
        XCTAssertNotEqual(tagline, homeRowMods.tagline)
        XCTAssertFalse(tagline.contains("modifier keys") && tagline.contains("no reaching"),
                       "Layer-mode tagline should not claim there's 'no reaching for modifier keys'")
    }

    func testShortDescriptionIsModifierCentricByDefault() {
        let desc = PackDetailView.displayShortDescription(for: homeRowMods, holdMode: .modifiers)
        XCTAssertEqual(desc, homeRowMods.shortDescription)
        XCTAssertTrue(desc.contains("⌘"))
    }

    func testShortDescriptionDropsModifierSymbolsInLayerMode() {
        let desc = PackDetailView.displayShortDescription(for: homeRowMods, holdMode: .layers)
        XCTAssertNotEqual(desc, homeRowMods.shortDescription)
        XCTAssertFalse(desc.contains("⌘ ⇧ ⌥ ⌃"),
                       "Layer-mode description should not claim modifier keys are produced")
        XCTAssertTrue(desc.lowercased().contains("layer"))
    }

    func testDependencyDescriptionStaysModifierCentricByDefault() {
        let homeRowArrowsDep = homeRowArrows.dependencies.first { $0.packID == homeRowMods.id }
        XCTAssertNotNil(homeRowArrowsDep)
        let desc = PackDetailView.displayDependencyDescription(homeRowArrowsDep, forPack: homeRowMods, holdMode: .modifiers)
        XCTAssertTrue(desc.contains("Home Row Mods assigns F to Command"))
    }

    func testDependencyDescriptionUpdatesInLayerMode() {
        let homeRowArrowsDep = homeRowArrows.dependencies.first { $0.packID == homeRowMods.id }
        XCTAssertNotNil(homeRowArrowsDep)
        let desc = PackDetailView.displayDependencyDescription(homeRowArrowsDep, forPack: homeRowMods, holdMode: .layers)
        XCTAssertFalse(desc.contains("Home Row Mods assigns F to Command"),
                       "Dependency copy should not claim HRM assigns F to Command once layer mode is active")
        XCTAssertTrue(desc.contains("layer"))
    }

    func testNonHomeRowModsPackCopyIsNeverRewritten() {
        // Guard against the mode-aware rewrite leaking into unrelated packs.
        XCTAssertEqual(PackDetailView.displayTagline(for: homeRowArrows, holdMode: .layers), homeRowArrows.tagline)
        XCTAssertEqual(
            PackDetailView.displayShortDescription(for: homeRowArrows, holdMode: .layers),
            homeRowArrows.shortDescription
        )
    }
}
