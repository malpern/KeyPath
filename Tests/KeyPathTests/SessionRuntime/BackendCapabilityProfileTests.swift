@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Phase 1 of docs/architecture/rules-admission-review.md: what the backend can
/// emit comes from the bridge, and every former hard-coded list gives the same
/// answer through it.
final class BackendCapabilityProfileTests: XCTestCase {
    override func tearDown() {
        BackendCapabilityProfile.testOverride = nil
        super.tearDown()
    }

    private func bridgeProfile() throws -> BackendCapabilityProfile {
        try SessionBridgeTestFixture.requireAvailable()
        let host = SessionBridgeTestFixture.runtimeHost
        return BackendCapabilityProfile(backend: .session) { key in
            KanataHostBridge.sessionOutputKeySupported(
                runtimeHost: host, keyName: key, supportedUsages: SessionKeyMap.sessionOutputUsages
            )
        }
    }

    func testBridgeAnswersTheSessionOutputRule() throws {
        let profile = try bridgeProfile()
        for key in ["a", "f1", "f12", "home", "del", "kp5", "caps", "C-S-n", "M-spc"] {
            XCTAssertTrue(profile.canEmit(kanataKey: key), key)
        }
        for key in ["volu", "vold", "voldwn", "mute", "pp", "next", "prev", "brup", "brdn", "brdown"] {
            XCTAssertFalse(profile.canEmit(kanataKey: key), key)
        }
        XCTAssertFalse(profile.supportsDeviceTargeting)
    }

    @MainActor
    func testFormerHardCodedListsGiveTheSameAnswersThroughTheBridge() throws {
        BackendCapabilityProfile.testOverride = try bridgeProfile()

        // SystemActionInfo: only the eight consumer actions, as before.
        let unsupported = Set(SystemActionInfo.allActions.filter { !$0.isSupportedInDriverlessSession }.map(\.id))
        XCTAssertEqual(unsupported, ["play-pause", "next-track", "prev-track", "mute",
                                     "volume-up", "volume-down", "brightness-up", "brightness-down"])
        // FunctionKeyMode: media needs consumer output, function does not.
        XCTAssertFalse(FunctionKeyMode.media.isSupportedInDriverlessSession)
        XCTAssertTrue(FunctionKeyMode.function.isSupportedInDriverlessSession)
        // Catalog: the Function layer was the only unavailable collection.
        let unavailable = RuleCollectionCatalog().originalCollections()
            .filter { RuleCollectionCatalog.driverlessUnavailableReason(for: $0.id) != nil }.map(\.id)
        XCTAssertEqual(unavailable, [RuleCollectionIdentifier.funLayer])
        // The sentence is the admission engine's (phase 4d): it names the key.
        let reason = RuleCollectionCatalog.driverlessUnavailableReason(for: RuleCollectionIdentifier.funLayer) ?? ""
        XCTAssertTrue(reason.contains("which the current backend can't send"), reason)
    }

    func testModifierPrefixesAreStrippedBeforeAsking() {
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "C-S-n"), "n")
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "RA-x"), "x")
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "C-down"), "down")
        XCTAssertEqual(BackendCapabilityProfile.baseKey(of: "M-"), "m-")
    }

    func testNoBridgeAnswerKeepsPreviousBehaviour() {
        let profile = BackendCapabilityProfile(backend: .session) { _ in nil }
        XCTAssertTrue(profile.canEmit(kanataKey: "home"))
        XCTAssertFalse(profile.canEmit(kanataKey: "volu"))
        XCTAssertFalse(profile.canEmit(kanataKey: "brdn"))
    }

    func testOnlyTheSessionBackendHasLimits() {
        let profile = BackendCapabilityProfile(backend: .driverKit) { _ in false }
        XCTAssertTrue(profile.canEmit(kanataKey: "volu"))
        XCTAssertTrue(profile.supportsDeviceTargeting)
    }

    func testAnswersAreCachedPerKey() {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let profile = BackendCapabilityProfile(backend: .session) { _ in counter.calls += 1; return true }
        _ = profile.canEmit(kanataKey: "a")
        _ = profile.canEmit(kanataKey: "C-a")
        XCTAssertEqual(counter.calls, 1)
    }
}
