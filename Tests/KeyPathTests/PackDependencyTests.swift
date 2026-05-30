@testable import KeyPathAppKit
import XCTest

final class PackDependencyTests: XCTestCase {
    func testNoCyclicDependencies() {
        // Verify no pack A requires B which requires A
        var visited = Set<String>()
        var stack = Set<String>()

        func hasCycle(from packID: String) -> Bool {
            if stack.contains(packID) { return true }
            if visited.contains(packID) { return false }
            visited.insert(packID)
            stack.insert(packID)

            if let pack = PackRegistry.pack(id: packID) {
                for dep in pack.dependencies where dep.kind == .requires {
                    if hasCycle(from: dep.packID) { return true }
                }
            }

            stack.remove(packID)
            return false
        }

        for pack in PackRegistry.starterKit {
            XCTAssertFalse(hasCycle(from: pack.id), "Circular dependency detected involving \(pack.name)")
        }
    }

    func testAllDependencyTargetsExist() {
        for pack in PackRegistry.starterKit {
            for dep in pack.dependencies {
                XCTAssertNotNil(
                    PackRegistry.pack(id: dep.packID),
                    "Pack '\(pack.name)' depends on '\(dep.packID)' which doesn't exist"
                )
            }
        }
    }

    func testPacksWithNoDependencies() {
        let noDeps = PackRegistry.starterKit.filter(\.dependencies.isEmpty)
        XCTAssertTrue(noDeps.contains { $0.id == "com.keypath.pack.caps-lock-to-escape" })
        XCTAssertTrue(noDeps.contains { $0.id == "com.keypath.pack.vim-navigation" })
        XCTAssertTrue(noDeps.contains { $0.id == "com.keypath.pack.home-row-mods" })
    }

    func testLayerPacksEnhancedByVimNavigation() {
        let layerPacks = ["com.keypath.pack.window-snapping", "com.keypath.pack.numpad-layer",
                          "com.keypath.pack.symbol-layer", "com.keypath.pack.fun-layer",
                          "com.keypath.pack.mission-control", "com.keypath.pack.delete-enhancement"]

        for packID in layerPacks {
            guard let pack = PackRegistry.pack(id: packID) else {
                XCTFail("Pack \(packID) not found")
                continue
            }
            let enhancedByVim = pack.dependencies.contains {
                $0.packID == "com.keypath.pack.vim-navigation" && $0.kind == .enhancedBy
            }
            XCTAssertTrue(enhancedByVim, "\(pack.name) should be enhanced by Vim Navigation")
        }
    }

    @MainActor
    func testNoRequiredDeps_UnmetRequirementsEmpty() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices {
            collections[i].isEnabled = false
        }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.windowSnapping }) {
            collections[idx].isEnabled = true
        }

        let unmet = PackDependencyChecker.unmetRequirements(
            for: "com.keypath.pack.window-snapping",
            enabledCollections: collections,
            installedPackIDs: []
        )

        XCTAssertTrue(unmet.isEmpty, "Window Snapping has no required deps — only enhancedBy")
    }

    @MainActor
    func testEnhancedByDeps_NotReportedAsUnmet() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices {
            collections[i].isEnabled = false
        }

        // Window Snapping is enhancedBy Vim Nav, not requires
        let unmet = PackDependencyChecker.unmetRequirements(
            for: "com.keypath.pack.window-snapping",
            enabledCollections: collections,
            installedPackIDs: []
        )

        XCTAssertTrue(unmet.isEmpty, "enhancedBy deps should not appear as unmet requirements")
    }
}
