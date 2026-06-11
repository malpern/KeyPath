@testable import KeyPathAppKit
import XCTest

/// Tests for the `danger-enable-cmd` default-OFF policy (M1.1): default state,
/// opt-in, and the one-time grandfathering migration for hand-written `(cmd ...)`
/// configs. Uses an isolated UserDefaults suite so test-runner state never leaks.
final class KanataCommandActionsPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.keypath.tests.command-actions-policy"

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Default posture

    func testDefaultsToDisabledWithNoRecordedDecision() {
        XCTAssertFalse(KanataCommandActionsPolicy.isEnabled(defaults: defaults))
        XCTAssertFalse(KanataCommandActionsPolicy.hasRecordedDecision(defaults: defaults))
    }

    func testSetEnabledRecordsDecision() {
        KanataCommandActionsPolicy.setEnabled(true, defaults: defaults)
        XCTAssertTrue(KanataCommandActionsPolicy.isEnabled(defaults: defaults))
        XCTAssertTrue(KanataCommandActionsPolicy.hasRecordedDecision(defaults: defaults))

        KanataCommandActionsPolicy.setEnabled(false, defaults: defaults)
        XCTAssertFalse(KanataCommandActionsPolicy.isEnabled(defaults: defaults))
        XCTAssertTrue(KanataCommandActionsPolicy.hasRecordedDecision(defaults: defaults))
    }

    // MARK: - Usage detection

    func testDetectsCmdActionUsage() {
        XCTAssertTrue(KanataCommandActionsPolicy.configUsesCommandActions(
            #"(defalias launch-obsidian (cmd open -a Obsidian))"#
        ))
        XCTAssertTrue(KanataCommandActionsPolicy.configUsesCommandActions(
            #"(defalias log-it (cmd-log debug error echo hi))"#
        ))
    }

    func testDefcfgHeaderLineAloneIsNotUsage() {
        // Every legacy generated config carries this line without using (cmd ...);
        // it must NOT grandfather the policy on.
        let legacyGenerated = """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        XCTAssertFalse(KanataCommandActionsPolicy.configUsesCommandActions(legacyGenerated))
    }

    func testPushMsgActionsAreNotUsage() {
        // push-msg is not gated by danger-enable-cmd — KeyPath's launchers,
        // system actions, and layer signals must not trip the detector.
        let generated = """
        (defalias
          act_f3 (push-msg "system:mission-control")
          act_c (push-msg "launch:com.apple.iCal")
          kp-layer-nav-enter (push-msg "layer:nav")
        )
        """
        XCTAssertFalse(KanataCommandActionsPolicy.configUsesCommandActions(generated))
    }

    func testCmdPrefixedAliasNamesAreNotUsage() {
        // `cmd` as an output key name (lmet alias) or inside words must not match.
        XCTAssertFalse(KanataCommandActionsPolicy.configUsesCommandActions(
            "(deflayer base cmd a (macro cmdish))"
        ))
    }

    // MARK: - Grandfathering

    func testGrandfatherEnablesWhenConfigUsesCmd() {
        let config = """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
        )
        (defalias open-notes (cmd open -a Notes))
        """
        KanataCommandActionsPolicy.grandfatherIfNeeded(configContent: config, defaults: defaults)
        XCTAssertTrue(KanataCommandActionsPolicy.isEnabled(defaults: defaults))
        XCTAssertTrue(KanataCommandActionsPolicy.hasRecordedDecision(defaults: defaults))
    }

    func testGrandfatherRecordsDisabledForLegacyHeaderOnlyConfig() {
        let config = """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
        )
        (defsrc caps)
        (deflayer base (push-msg "layer:base"))
        """
        KanataCommandActionsPolicy.grandfatherIfNeeded(configContent: config, defaults: defaults)
        XCTAssertFalse(KanataCommandActionsPolicy.isEnabled(defaults: defaults))
        XCTAssertTrue(
            KanataCommandActionsPolicy.hasRecordedDecision(defaults: defaults),
            "Migration must record its decision so it runs exactly once"
        )
    }

    func testGrandfatherNeverOverridesRecordedDecision() {
        // User explicitly disabled; a later load of a (cmd ...) config must not flip it back.
        KanataCommandActionsPolicy.setEnabled(false, defaults: defaults)
        KanataCommandActionsPolicy.grandfatherIfNeeded(
            configContent: "(defalias x (cmd rm -rf /))",
            defaults: defaults
        )
        XCTAssertFalse(KanataCommandActionsPolicy.isEnabled(defaults: defaults))
    }

    // MARK: - Policy enforcement on external content

    func testEnforcingPolicyStripsGrantWhenDisabled() {
        let repaired = """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
          managed-repeat yes
        )
        (defsrc caps)
        """
        let enforced = KanataCommandActionsPolicy.enforcingPolicy(on: repaired, defaults: defaults)
        XCTAssertFalse(enforced.contains("danger-enable-cmd"))
        XCTAssertTrue(
            enforced.contains("managed-repeat yes"),
            "Enforcement is line-surgical — other header options must survive"
        )
        XCTAssertTrue(enforced.contains("(defsrc caps)"))
    }

    func testEnforcingPolicyStripsExplicitNoWhenDisabled() {
        // The strip is line-surgical and value-blind: an explicit (redundant)
        // `danger-enable-cmd no` from the model doesn't survive either.
        let repaired = "(defcfg\n  danger-enable-cmd no\n  process-unmapped-keys yes\n)"
        let enforced = KanataCommandActionsPolicy.enforcingPolicy(on: repaired, defaults: defaults)
        XCTAssertFalse(enforced.contains("danger-enable-cmd"))
        XCTAssertTrue(enforced.contains("process-unmapped-keys yes"))
    }

    func testEnforcingPolicyPassesThroughWhenEnabled() {
        KanataCommandActionsPolicy.setEnabled(true, defaults: defaults)
        let repaired = "(defcfg\n  danger-enable-cmd yes\n)"
        XCTAssertEqual(
            KanataCommandActionsPolicy.enforcingPolicy(on: repaired, defaults: defaults),
            repaired
        )
    }

    // MARK: - Generator integration

    @MainActor
    func testGeneratedConfigOmitsDangerEnableCmdByDefault() {
        let config = KanataConfiguration.generateFromCollections(
            RuleCollectionCatalog().defaultCollections(),
            allowCommandActions: false
        )
        XCTAssertFalse(config.contains("danger-enable-cmd"))
        XCTAssertTrue(config.contains("process-unmapped-keys yes"))
    }

    @MainActor
    func testGeneratedConfigIncludesDangerEnableCmdWhenOptedIn() {
        let config = KanataConfiguration.generateFromCollections(
            RuleCollectionCatalog().defaultCollections(),
            allowCommandActions: true
        )
        XCTAssertTrue(config.contains("danger-enable-cmd yes"))
    }
}
