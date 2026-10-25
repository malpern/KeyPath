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
        for key in ["a", "f1", "f12", "home", "del", "kp5", "caps", "C-S-n", "M-spc",
                    // Phase 6: the media keys the worker posts as system-defined events.
                    "volu", "vold", "voldwn", "mute", "pp", "next", "prev", "brup", "brdn", "brdown"]
        {
            XCTAssertTrue(profile.canEmit(kanataKey: key), key)
        }
        // Consumer page, but not a key the worker posts.
        XCTAssertFalse(profile.canEmit(kanataKey: "calc"))
        XCTAssertFalse(profile.supportsDeviceTargeting)
    }

    func testFormerHardCodedListsGiveTheSameAnswersThroughTheBridge() throws {
        BackendCapabilityProfile.testOverride = try bridgeProfile()

        // SystemActionInfo: every offered action, media included (phase 6).
        let unsupported = Set(SystemActionInfo.allActions.filter { !$0.isSupportedInDriverlessSession }.map(\.id))
        XCTAssertEqual(unsupported, [])
        // FunctionKeyMode: both modes emit what the worker can post.
        XCTAssertTrue(FunctionKeyMode.media.isSupportedInDriverlessSession)
        XCTAssertTrue(FunctionKeyMode.function.isSupportedInDriverlessSession)
        // Catalog: nothing built in is unavailable any more.
        let unavailable = RuleCollectionCatalog().originalCollections()
            .filter { RuleCollectionCatalog.driverlessUnavailableReason(for: $0.id) != nil }.map(\.id)
        XCTAssertEqual(unavailable, [])
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
