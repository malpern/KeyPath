@testable import KeyPathAppKit
import XCTest

/// Byte-exact pins for the single-source-of-truth `defcfg` renderer.
///
/// These assert the literal rendered strings so any drift in `KanataDefcfg.render()`
/// or its named profiles fails CI. The expected strings here match the historical
/// hand-built headers the four config emitters used before consolidation.
final class KanataDefcfgTests: XCTestCase {
    // MARK: - standard()

    func testStandardDefaultMatchesGeneratedHeader() {
        // Opted-in variant of GoldenConfigs/default.kbd (key-repeat enabled, no prior-idle,
        // no chords). The golden itself renders with allowCommandActions: false since M1.1.
        let defcfg = KanataDefcfg.standard(
            allowCommandActions: true,
            managedRepeatTiming: (delayMs: 500, intervalMs: 30),
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: ""
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
          managed-repeat yes
          managed-repeat-unlisted no
          managed-repeat-delay 500
          managed-repeat-interval 30
        )
        """)
    }

    func testStandardWithPriorIdleAndChords() {
        // Opted-in variant of GoldenConfigs/home-row-mods.kbd plus a chord-triggered
        // concurrent-tap-hold. The golden renders with allowCommandActions: false since M1.1.
        let defcfg = KanataDefcfg.standard(
            allowCommandActions: true,
            managedRepeatTiming: (delayMs: 500, intervalMs: 30),
            requirePriorIdleMs: 150,
            hasChords: true,
            deviceTargeting: ""
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
          managed-repeat yes
          managed-repeat-unlisted no
          managed-repeat-delay 500
          managed-repeat-interval 30
          tap-hold-require-prior-idle 150
          concurrent-tap-hold yes
        )
        """)
    }

    func testStandardWithoutKeyRepeatOmitsRepeatTuning() {
        let defcfg = KanataDefcfg.standard(
            allowCommandActions: true,
            managedRepeatTiming: nil,
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: ""
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
          managed-repeat yes
          managed-repeat-unlisted no
        )
        """)
    }

    func testStandardAppendsDeviceTargetingTrailerVerbatim() {
        // The trailer carries its own leading newline/indentation and lands before the
        // closing paren — exactly how renderMacOSDeviceTargetingForDefcfg() is spliced.
        let trailer = "\n  macos-dev-names-exclude (\n    \"vhid\"\n  )"
        let defcfg = KanataDefcfg.standard(
            allowCommandActions: true,
            managedRepeatTiming: nil,
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: trailer
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
          managed-repeat yes
          managed-repeat-unlisted no
          macos-dev-names-exclude (
            "vhid"
          )
        )
        """)
    }

    func testStandardCanDisableCommandActions() {
        // Forward-looking: the danger-enable-cmd gate flips this single flag.
        let defcfg = KanataDefcfg.standard(
            allowCommandActions: false,
            managedRepeatTiming: nil,
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: ""
        )
        XCTAssertFalse(defcfg.render().contains("danger-enable-cmd"))
    }

    // MARK: - Named profiles

    func testMinimalSafeProfile() {
        // SaveCoordinator crash-loop recovery: process-unmapped-keys only, no cmd.
        XCTAssertEqual(KanataDefcfg.minimalSafe.render(), """
        (defcfg
          process-unmapped-keys yes
        )
        """)
        XCTAssertFalse(KanataDefcfg.minimalSafe.render().contains("danger-enable-cmd"))
    }

    func testValidationWrapperProfile() {
        // AppConfigGenerator include-file validation wrapper.
        XCTAssertEqual(KanataDefcfg.validationWrapper.render(), """
        (defcfg
          process-unmapped-keys yes
        )
        """)
    }

    func testMinimalSafeAndValidationWrapperShareOutputByDesign() {
        // Identical today by design. If one diverges (e.g. validationWrapper gains an
        // option), this assertion should be updated deliberately — it guards against
        // accidental convergence/divergence in either direction.
        XCTAssertEqual(KanataDefcfg.minimalSafe, KanataDefcfg.validationWrapper)
    }

    func testRepairFallbackProfileFollowsPolicy() {
        // ConfigurationService rule-based repair injection mirrors the user's
        // command-actions policy instead of hardcoding danger-enable-cmd.
        XCTAssertEqual(KanataDefcfg.repairFallback(allowCommandActions: true).render(), """
        (defcfg
          process-unmapped-keys yes
          danger-enable-cmd yes
        )
        """)
        XCTAssertEqual(KanataDefcfg.repairFallback(allowCommandActions: false).render(), """
        (defcfg
          process-unmapped-keys yes
        )
        """)
    }

    // MARK: - Call-site splice equivalence

    func testRepairFallbackSpliceMatchesLegacyString() {
        // ConfigurationService injects the block followed by a blank line. The legacy
        // multiline literal rendered to exactly this byte sequence (for an opted-in user).
        let spliced = KanataDefcfg.repairFallback(allowCommandActions: true).render() + "\n\n"
        let legacy = "(defcfg\n  process-unmapped-keys yes\n  danger-enable-cmd yes\n)\n\n"
        XCTAssertEqual(spliced, legacy)
    }
}
