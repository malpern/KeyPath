@testable import KeyPathAppKit
import XCTest

/// Tests for Pack Detail window sizing and pack metadata.
final class PackDetailWindowTests: XCTestCase {

    func testNarrowPacksGetNarrowWindow() {
        let narrowPacks = [
            "com.keypath.pack.caps-lock-to-escape",
            "com.keypath.pack.escape-remap",
            "com.keypath.pack.delete-enhancement",
            "com.keypath.pack.backup-caps-lock",
            "com.keypath.pack.leader-key",
            "com.keypath.pack.kindavim",
        ]

        for packID in narrowPacks {
            guard let pack = PackRegistry.pack(id: packID) else {
                XCTFail("Pack \(packID) not found")
                continue
            }
            // Verify these are NOT in the wide or medium lists
            // (they should get 560px default)
            let wideIDs: Set<String> = [
                "com.keypath.pack.vim-navigation",
                "com.keypath.pack.window-snapping",
                "com.keypath.pack.mission-control",
                "com.keypath.pack.numpad-layer",
                "com.keypath.pack.symbol-layer",
                "com.keypath.pack.fun-layer",
                "com.keypath.pack.home-row-mods",
                "com.keypath.pack.quick-launcher",
            ]
            XCTAssertFalse(wideIDs.contains(pack.id),
                           "\(pack.name) should be narrow, not wide")
        }
    }

    func testAllPacksHaveDescriptions() {
        for pack in PackRegistry.starterKit {
            XCTAssertFalse(pack.shortDescription.isEmpty,
                           "\(pack.name) missing short description")
            XCTAssertFalse(pack.tagline.isEmpty,
                           "\(pack.name) missing tagline")
        }
    }

    func testAllPacksHaveIcons() {
        for pack in PackRegistry.starterKit {
            XCTAssertFalse(pack.iconSymbol.isEmpty,
                           "\(pack.name) missing icon symbol")
        }
    }

    func testPackDependenciesUseStringIDs() {
        for pack in PackRegistry.starterKit {
            for dep in pack.dependencies {
                XCTAssertTrue(dep.packID.contains("com.keypath.pack."),
                              "Dependency \(dep.packID) should use full string ID format")
            }
        }
    }
}
