@testable import KeyPathAppKit
import XCTest

/// Byte-exact pins for the single-source-of-truth `defcfg` renderer.
///
/// These assert the literal rendered strings so any drift in `KanataDefcfg.render()`
/// or its named profiles fails CI. `danger-enable-cmd` is intentionally not
/// representable (the bundled engine is compiled without kanata's `cmd` feature,
/// #879) — a pin below guards that no profile ever renders it.
final class KanataDefcfgTests: XCTestCase {
    // MARK: - standard()

    func testStandardDefaultMatchesGeneratedHeader() {
        // Mirrors GoldenConfigs/default.kbd (key-repeat enabled, no prior-idle, no chords).
        let defcfg = KanataDefcfg.standard(
            managedRepeatTiming: (delayMs: 500, intervalMs: 30),
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: ""
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
          managed-repeat yes
          managed-repeat-unlisted no
          managed-repeat-delay 500
          managed-repeat-interval 30
        )
        """)
    }

    func testStandardWithPriorIdleAndChords() {
        // Mirrors GoldenConfigs/home-row-mods.kbd plus a chord-triggered concurrent-tap-hold.
        let defcfg = KanataDefcfg.standard(
            managedRepeatTiming: (delayMs: 500, intervalMs: 30),
            requirePriorIdleMs: 150,
            hasChords: true,
            deviceTargeting: ""
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
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
            managedRepeatTiming: nil,
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: ""
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
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
            managedRepeatTiming: nil,
            requirePriorIdleMs: nil,
            hasChords: false,
            deviceTargeting: trailer
        )
        XCTAssertEqual(defcfg.render(), """
        (defcfg
          process-unmapped-keys yes
          managed-repeat yes
          managed-repeat-unlisted no
          macos-dev-names-exclude (
            "vhid"
          )
        )
        """)
    }

    func testNoProfileEverRendersDangerEnableCmd() {
        // The engine is built without the cmd feature (#879); the header must never
        // grant what the binary can't do. If this fails, someone reintroduced the
        // option — that requires the engine build and this type to change together.
        let profiles: [KanataDefcfg] = [
            .standard(
                managedRepeatTiming: (delayMs: 500, intervalMs: 30),
                requirePriorIdleMs: 150,
                hasChords: true,
                deviceTargeting: ""
            ),
            .minimalSafe,
            .validationWrapper,
            .repairFallback
        ]
        for profile in profiles {
            XCTAssertFalse(profile.render().contains("danger-enable-cmd"))
        }
    }

    // MARK: - Named profiles

    func testMinimalSafeProfile() {
        // SaveCoordinator crash-loop recovery: process-unmapped-keys only.
        XCTAssertEqual(KanataDefcfg.minimalSafe.render(), """
        (defcfg
          process-unmapped-keys yes
        )
        """)
    }

    func testValidationWrapperProfile() {
        // AppConfigGenerator include-file validation wrapper.
        XCTAssertEqual(KanataDefcfg.validationWrapper.render(), """
        (defcfg
          process-unmapped-keys yes
        )
        """)
    }

    func testMinimalProfilesShareOutputByDesign() {
        // Identical today by design. If one diverges (e.g. repairFallback gains an
        // option), this assertion should be updated deliberately — it guards against
        // accidental convergence/divergence in either direction.
        XCTAssertEqual(KanataDefcfg.minimalSafe, KanataDefcfg.validationWrapper)
        XCTAssertEqual(KanataDefcfg.minimalSafe, KanataDefcfg.repairFallback)
    }

    // MARK: - Call-site splice equivalence

    func testRepairFallbackSpliceShape() {
        // ConfigurationService injects the block followed by a blank line.
        let spliced = KanataDefcfg.repairFallback.render() + "\n\n"
        XCTAssertEqual(spliced, "(defcfg\n  process-unmapped-keys yes\n)\n\n")
    }
}
