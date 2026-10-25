@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Phase 2 of docs/architecture/rules-admission-review.md: environment needs are
/// inferred from what each rule generates; only non-inferable ones are declared.
@MainActor
final class RuleEnvironmentNeedsTests: XCTestCase {
    override func tearDown() async throws {
        BackendCapabilityProfile.testOverride = nil
        try await super.tearDown()
    }

    private func sessionProfile() throws -> BackendCapabilityProfile {
        try SessionBridgeTestFixture.requireAvailable()
        let host = SessionBridgeTestFixture.runtimeHost
        return BackendCapabilityProfile(backend: .session) { key in
            KanataHostBridge.sessionOutputKeySupported(
                runtimeHost: host, keyName: key, supportedUsages: SessionKeyMap.sessionOutputUsages
            )
        }
    }

    /// Over the whole catalog, as profiles receive it: only the Function layer
    /// has an unmet need on the session backend, and it is media output.
    func testWholeCatalogInferenceOnTheSessionBackend() throws {
        let profile = try sessionProfile()
        var unmetByCollection: [UUID: [RuleEnvironmentNeed]] = [:]
        for collection in RuleCollectionCatalog().defaultCollections() {
            let needs = RuleCollectionNeedsExtractor.needs(for: collection)
            XCTAssertFalse(needs.contains(.deviceTargeting), "\(collection.name) unexpectedly targets devices")
            let unmet = RuleCollectionNeedsExtractor.unmet(needs, profile: profile)
            if !unmet.isEmpty { unmetByCollection[collection.id] = unmet }
        }
        // Phase 6: the Function layer's media keys are outputs the worker posts.
        XCTAssertEqual(Set(unmetByCollection.keys), [])
    }

    func testCapsLockInputIsInferredAndMetByManagedCaps() throws {
        let caps = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.capsLockRemap })
        let needs = RuleCollectionNeedsExtractor.needs(for: caps)
        XCTAssertTrue(needs.contains(.capsLockInput))
        XCTAssertFalse(try RuleCollectionNeedsExtractor.unmet(needs, profile: sessionProfile()).contains(.capsLockInput))
    }

    func testSystemActionsAndTapHoldOutputsAreInferred() {
        let mappings = [
            KeyMapping(input: "f5", action: .systemAction(id: "volume-up")),
            KeyMapping(input: "j", action: .keystroke(key: "j"),
                       behavior: .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "j"), holdAction: .keystroke(key: "mute"))))
        ]
        let needs = RuleCollectionNeedsExtractor.needs(for: mappings)
        XCTAssertTrue(needs.contains(.emits(key: "volu")))
        XCTAssertTrue(needs.contains(.emits(key: "mute")))
        XCTAssertTrue(needs.contains(.emits(key: "j")))
    }

    func testDeviceTargetingIsInferredAndUnmetOnSession() {
        let mapping = KeyMapping(input: "a", action: .keystroke(key: "b"),
                                 deviceOverrides: [DeviceKeyOverride(deviceHash: "cl80", output: .keystroke(key: "c"))])
        let needs = RuleCollectionNeedsExtractor.needs(for: [mapping])
        XCTAssertTrue(needs.contains(.deviceTargeting))
        let session = BackendCapabilityProfile(backend: .session) { _ in true }
        XCTAssertEqual(RuleCollectionNeedsExtractor.unmet(needs, profile: session), [.deviceTargeting])
        let driver = BackendCapabilityProfile(backend: .driverKit) { _ in true }
        XCTAssertEqual(RuleCollectionNeedsExtractor.unmet(needs, profile: driver), [])
    }

    func testOnlyNonInferableNeedsAreDeclaredOnPacks() {
        XCTAssertEqual(PackRegistry.kindaVim.requires, [.externalApp(name: "KindaVim", path: "/Applications/kindaVim.app")])
        let unmet = RuleCollectionNeedsExtractor.unmet(Set(PackRegistry.kindaVim.requires), fileExists: { _ in false })
        XCTAssertEqual(unmet.count, 1)
        // Inferable needs must never be declared by hand.
        for pack in PackRegistry.starterKit {
            for need in pack.requires {
                guard case .externalApp = need else { return XCTFail("\(pack.name) declares inferable need \(need)") }
            }
        }
    }

    func testConflictsWithIsReadInBothDirections() {
        let arrows = "com.keypath.pack.home-row-arrows", mods = "com.keypath.pack.home-row-mods"
        XCTAssertEqual(PackDependencyChecker.conflicts(for: arrows, installedPackIDs: [mods]).map(\.packID), [mods])
        XCTAssertEqual(PackDependencyChecker.conflicts(for: mods, installedPackIDs: [arrows]).map(\.packID), [arrows])
        XCTAssertTrue(PackDependencyChecker.conflicts(for: arrows, installedPackIDs: []).isEmpty)
    }
}
