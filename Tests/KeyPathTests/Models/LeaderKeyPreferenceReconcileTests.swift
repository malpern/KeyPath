@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

/// Unit tests for the pure `LeaderKeyPreference.reconciled(from:current:)` rule (#889).
///
/// This is the single, shared statement of the reconcile logic used by both the in-process
/// load paths (`RuleCollectionsManager`) and the standalone CLI apply path (`ConfigFacade`).
/// Testing it directly (no manager, no I/O) locks the rule in one place.
final class LeaderKeyPreferenceReconcileTests: XCTestCase {
    private func leaderCollections(enabled: Bool, selectedOutput: String?) -> [RuleCollection] {
        RuleCollectionCatalog().defaultCollections().map { collection -> RuleCollection in
            var collection = collection
            if collection.id == RuleCollectionIdentifier.leaderKey {
                collection.isEnabled = enabled
                if let selectedOutput {
                    collection.configuration.updateSelectedOutput(selectedOutput)
                } else if var config = collection.configuration.singleKeyPickerConfig {
                    config.selectedOutput = nil
                    collection.configuration = .singleKeyPicker(config)
                }
            }
            return collection
        }
    }

    func testReconcilesFromExplicitSelectedOutput() {
        let current = LeaderKeyPreference.default // key "space"
        let reconciled = LeaderKeyPreference.reconciled(
            from: leaderCollections(enabled: true, selectedOutput: "tab"),
            current: current
        )
        XCTAssertEqual(reconciled?.key, "tab")
        XCTAssertEqual(reconciled?.enabled, true)
        XCTAssertEqual(reconciled?.targetLayer, current.targetLayer, "target layer is preserved")
    }

    func testNoOpWhenPreferenceAlreadyMatches() {
        let current = LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: true)
        XCTAssertNil(
            LeaderKeyPreference.reconciled(
                from: leaderCollections(enabled: true, selectedOutput: "tab"),
                current: current
            ),
            "already-matching preference should not reconcile"
        )
    }

    func testReconcilesWhenPreferenceMatchesKeyButIsDisabled() {
        let current = LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: false)
        let reconciled = LeaderKeyPreference.reconciled(
            from: leaderCollections(enabled: true, selectedOutput: "tab"),
            current: current
        )
        XCTAssertEqual(reconciled?.enabled, true, "a disabled preference with a matching key must be re-enabled")
    }

    func testNilSelectedOutputIsNoOp() {
        let current = LeaderKeyPreference(key: "caps", targetLayer: .navigation, enabled: true)
        XCTAssertNil(
            LeaderKeyPreference.reconciled(
                from: leaderCollections(enabled: true, selectedOutput: nil),
                current: current
            ),
            "nil selectedOutput means no opinion — leave the system-preference leader untouched"
        )
    }

    func testDisabledCollectionIsNoOp() {
        let current = LeaderKeyPreference(key: "caps", targetLayer: .navigation, enabled: true)
        XCTAssertNil(
            LeaderKeyPreference.reconciled(
                from: leaderCollections(enabled: false, selectedOutput: "tab"),
                current: current
            ),
            "a disabled Leader Key collection must not reconcile"
        )
    }
}
