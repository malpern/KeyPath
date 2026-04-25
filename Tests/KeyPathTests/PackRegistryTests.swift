@testable import KeyPathAppKit
import XCTest

final class PackRegistryTests: XCTestCase {
    func testStarterKitIsNonEmpty() {
        XCTAssertFalse(PackRegistry.starterKit.isEmpty)
    }

    func testAllPackIDsAreUnique() {
        let ids = PackRegistry.starterKit.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate pack IDs present")
    }

    func testExpectedPacksShip() {
        let ids = Set(PackRegistry.starterKit.map(\.id))
        XCTAssertTrue(ids.contains("com.keypath.pack.caps-lock-to-escape"))
        XCTAssertTrue(ids.contains("com.keypath.pack.home-row-mods"))
        XCTAssertTrue(ids.contains("com.keypath.pack.escape-remap"))
        XCTAssertTrue(ids.contains("com.keypath.pack.delete-enhancement"))
        XCTAssertTrue(ids.contains("com.keypath.pack.backup-caps-lock"))
        XCTAssertTrue(ids.contains("com.keypath.pack.vim-navigation"))
        XCTAssertTrue(ids.contains("com.keypath.pack.window-snapping"))
        XCTAssertTrue(ids.contains("com.keypath.pack.mission-control"))
        XCTAssertTrue(ids.contains("com.keypath.pack.auto-shift-symbols"))
        XCTAssertTrue(ids.contains("com.keypath.pack.numpad-layer"))
        XCTAssertTrue(ids.contains("com.keypath.pack.symbol-layer"))
        XCTAssertTrue(ids.contains("com.keypath.pack.fun-layer"))
        XCTAssertTrue(ids.contains("com.keypath.pack.quick-launcher"))
        XCTAssertTrue(ids.contains("com.keypath.pack.leader-key"))
    }

    func testCollectionBackedPacksPointAtRealCollections() {
        let catalogIDs = Set(RuleCollectionCatalog().defaultCollections().map(\.id))
        for pack in PackRegistry.starterKit {
            guard let associated = pack.associatedCollectionID else { continue }
            XCTAssertTrue(
                catalogIDs.contains(associated),
                "Pack \(pack.id) references missing collection \(associated)"
            )
        }
    }

    // MARK: - packsTargeting alias normalization

    func testPacksTargetingHandlesCapsAlias() {
        // The overlay keyboard emits "capslock"; pack manifests use "caps".
        // Both spellings should resolve to the same pack.
        let viaShortForm = PackRegistry.packsTargeting(kanataKey: "caps")
        let viaLongForm = PackRegistry.packsTargeting(kanataKey: "capslock")
        XCTAssertEqual(viaShortForm.map(\.id), viaLongForm.map(\.id))
        XCTAssertFalse(viaShortForm.isEmpty)
    }

    func testPacksTargetingHandlesModifierAliases() {
        // leftmeta ↔ lmet, leftshift ↔ lsft, etc.
        let pairs: [(String, String)] = [
            ("lmet", "leftmeta"),
            ("rmet", "rightmeta"),
            ("lsft", "leftshift"),
            ("rsft", "rightshift"),
            ("lalt", "leftalt"),
            ("ralt", "rightalt"),
            ("lctl", "leftctrl"),
            ("rctl", "rightctrl")
        ]
        for (short, long) in pairs {
            XCTAssertEqual(
                PackRegistry.packsTargeting(kanataKey: short).map(\.id),
                PackRegistry.packsTargeting(kanataKey: long).map(\.id),
                "alias mismatch for \(short) / \(long)"
            )
        }
    }

    func testPacksTargetingIgnoresCase() {
        XCTAssertEqual(
            PackRegistry.packsTargeting(kanataKey: "CAPS").map(\.id),
            PackRegistry.packsTargeting(kanataKey: "caps").map(\.id)
        )
    }

    func testPacksTargetingReturnsEmptyForEmptyOrUnknown() {
        XCTAssertTrue(PackRegistry.packsTargeting(kanataKey: "").isEmpty)
        XCTAssertTrue(PackRegistry.packsTargeting(kanataKey: "ZZZZZ").isEmpty)
    }

    // MARK: - Lookup

    func testPackLookupByID() {
        let pack = PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape")
        XCTAssertNotNil(pack)
        XCTAssertEqual(pack?.name, "Caps Lock Remap")
    }

    func testPackLookupReturnsNilForUnknown() {
        XCTAssertNil(PackRegistry.pack(id: "nope.not.real"))
    }
}
