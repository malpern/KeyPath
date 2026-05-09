@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Extended dependency system tests covering allUnmetRequirements,
/// dependents, config predicates, and suggestions.
final class PackDependencyExtendedTests: XCTestCase {

    // MARK: - allUnmetRequirements

    @MainActor
    func testAllUnmetRequirements_MultipleBrokenDeps() {
        var collections = RuleCollectionCatalog().defaultCollections()
        // Disable everything, then enable layer packs WITHOUT Vim Nav
        for i in collections.indices { collections[i].isEnabled = false }
        // Enable Window Snapping and Mission Control (both need Vim Nav)
        for i in collections.indices {
            if collections[i].id == RuleCollectionIdentifier.windowSnapping
                || collections[i].id == RuleCollectionIdentifier.missionControl
            {
                collections[i].isEnabled = true
            }
        }

        let unmetMap = PackDependencyChecker.allUnmetRequirements(
            enabledCollections: collections,
            installedPackIDs: []
        )

        XCTAssertTrue(unmetMap.keys.contains("com.keypath.pack.window-snapping"))
        XCTAssertTrue(unmetMap.keys.contains("com.keypath.pack.mission-control"))
    }

    @MainActor
    func testAllUnmetRequirements_EmptyWhenDepsAreMet() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        // Enable Vim Nav AND Window Snapping
        for i in collections.indices {
            if collections[i].id == RuleCollectionIdentifier.vimNavigation
                || collections[i].id == RuleCollectionIdentifier.windowSnapping
            {
                collections[i].isEnabled = true
            }
        }

        let unmetMap = PackDependencyChecker.allUnmetRequirements(
            enabledCollections: collections,
            installedPackIDs: []
        )

        XCTAssertNil(unmetMap["com.keypath.pack.window-snapping"],
                     "Window Snapping should have no unmet deps when Vim Nav is on")
    }

    // MARK: - dependents(of:)

    @MainActor
    func testDependents_FindsAllVimNavDependents() {
        var collections = RuleCollectionCatalog().defaultCollections()
        // Enable everything
        for i in collections.indices { collections[i].isEnabled = true }

        let dependents = PackDependencyChecker.dependents(
            of: "com.keypath.pack.vim-navigation",
            enabledCollections: collections,
            installedPackIDs: []
        )

        let names = Set(dependents.map(\.id))
        XCTAssertTrue(names.contains("com.keypath.pack.window-snapping"))
        XCTAssertTrue(names.contains("com.keypath.pack.mission-control"))
        XCTAssertTrue(names.contains("com.keypath.pack.numpad-layer"))
        XCTAssertTrue(names.contains("com.keypath.pack.symbol-layer"))
        XCTAssertTrue(names.contains("com.keypath.pack.fun-layer"))
        XCTAssertTrue(names.contains("com.keypath.pack.delete-enhancement"))
        XCTAssertFalse(names.contains("com.keypath.pack.vim-navigation"),
                       "Should not include self")
    }

    @MainActor
    func testDependents_OnlyReturnsEnabledPacks() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = false }
        // Only Vim Nav enabled, nothing depends on it that's also enabled
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.vimNavigation }) {
            collections[idx].isEnabled = true
        }

        let dependents = PackDependencyChecker.dependents(
            of: "com.keypath.pack.vim-navigation",
            enabledCollections: collections,
            installedPackIDs: []
        )

        XCTAssertTrue(dependents.isEmpty, "No enabled packs depend on Vim Nav when they're all off")
    }

    // MARK: - Config Predicate Evaluation

    @MainActor
    func testConfigPredicate_HoldOutputMatch() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices { collections[i].isEnabled = true }
        // Caps Lock Remap defaults to hold=Hyper (C-S-M-A-)

        let unmet = PackDependencyChecker.unmetRequirements(
            for: "com.keypath.pack.quick-launcher",
            enabledCollections: collections,
            installedPackIDs: []
        )

        // Quick Launcher's Caps Lock dependency is .suggests, not .requires
        // so unmetRequirements only checks .requires — should be empty
        XCTAssertTrue(unmet.isEmpty, "No required deps should be unmet for Launcher")
    }

    // MARK: - Suggestions

    @MainActor
    func testSuggestions_ReturnsDisabledSuggestedPacks() {
        let suggestions = PackDependencyChecker.suggestions(
            for: "com.keypath.pack.backup-caps-lock",
            installedPackIDs: []
        )

        XCTAssertFalse(suggestions.isEmpty, "Backup Caps Lock should suggest Caps Lock Remap")
        XCTAssertEqual(suggestions.first?.packID, "com.keypath.pack.caps-lock-to-escape")
    }

    @MainActor
    func testSuggestions_ExcludesAlreadyInstalled() {
        let suggestions = PackDependencyChecker.suggestions(
            for: "com.keypath.pack.backup-caps-lock",
            installedPackIDs: ["com.keypath.pack.caps-lock-to-escape"]
        )

        XCTAssertTrue(suggestions.isEmpty, "Should not suggest already-installed pack")
    }
}
