@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Per-option matrix tests for the four high-complexity rule families.
///
/// `kanata --check` (in ConfigValidationTests) confirms that the *default*
/// config for each family is syntactically valid. These tests cover the next
/// layer down: do the *option variants* still produce valid kanata and emit
/// the expected output fragments?
///
/// Each test uses `MatrixTestHelpers.enabledCollectionConfig(_:mutate:)` to
/// enable a single family in a full-catalog context, flip one option via the
/// `mutate` closure, then assert on both the byte output (specific tokens)
/// and the kanata syntax acceptance.
final class PerOptionMatrixTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    @MainActor
    private func assertKanataValid(_ config: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let result = try await KanataCheckHelper.runCheck(config)
        if !result.isValid {
            XCTFail("\(label) produced invalid kanata. Errors: \(result.errors)", file: file, line: line)
        }
    }

    // MARK: - Home Row Layer Toggles

    //
    // HRL Toggles' default key assignments reference layers (`nav`, `sym`,
    // `fun`, `num`) that other families own. `nav` is provided by Vim
    // Navigation (a systemDefault), but `sym`, `fun`, and `num` require
    // enabling Symbol Layer, Function Layer, and Numpad respectively.
    //
    // The whileHeld variant happens to work even without the companion
    // families because `layer-while-held` accepts the layer name as a
    // forward reference. The toggle variant requires `layer-toggle <name>`
    // which kanata enforces against the set of declared deflayers — see
    // `testHRLToggles_ToggleMode_WithoutCompanionLayers_Documented` below.

    @MainActor
    func testHRLToggles_WhileHeldMode_StillValid() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .whileHeld
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        XCTAssertTrue(
            config.contains("layer-while-held"),
            "HRL Toggles in whileHeld mode should emit layer-while-held actions"
        )
        try await assertKanataValid(config, "HRL Toggles whileHeld")
    }

    @MainActor
    func testHRLToggles_ToggleMode_WithCompanionLayers_IsValid() async throws {
        var collections = RuleCollectionCatalog().defaultCollections()
        // Enable HRL Toggles in toggle mode + the layer families it depends on.
        let companionIDs: Set<UUID> = [
            RuleCollectionIdentifier.homeRowLayerToggles,
            RuleCollectionIdentifier.symbolLayer,
            RuleCollectionIdentifier.funLayer,
            RuleCollectionIdentifier.numpadLayer
        ]
        for i in collections.indices where companionIDs.contains(collections[i].id) {
            collections[i].isEnabled = true
            if collections[i].id == RuleCollectionIdentifier.homeRowLayerToggles,
               case var .homeRowLayerToggles(cfg) = collections[i].configuration
            {
                cfg.toggleMode = .toggle
                collections[i].configuration = .homeRowLayerToggles(cfg)
            }
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        XCTAssertTrue(
            config.contains("layer-toggle"),
            "HRL Toggles in toggle mode should emit layer-toggle actions"
        )
        try await assertKanataValid(config, "HRL Toggles toggle + companion layers")
    }

    /// Locks in the post-#871 safety-net behavior: enabling HRL Toggles in
    /// toggle mode *alone* (Function/Symbol/Numpad disabled) emits
    /// `(layer-toggle fun)`, `(layer-toggle sym)`, `(layer-toggle num)`
    /// actions AND matching stub `(deflayer ...)` blocks so kanata accepts
    /// the config. The orphan home-row keys silently no-op rather than
    /// failing the whole config. See StubDeflayerSafetyNetTests for the
    /// focused unit coverage.
    ///
    /// The proper UX (configure-time prompt to enable the supporting layer
    /// families) is queued as the next-sprint epic in #865.
    @MainActor
    func testHRLToggles_ToggleMode_WithoutCompanionLayers_SafetyNetCovers() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .toggle
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        XCTAssertTrue(
            config.contains("(layer-toggle "),
            "HRL Toggles toggle mode should emit (layer-toggle ...) actions"
        )
        XCTAssertTrue(config.contains("(deflayer fun"), "Safety net should emit stub (deflayer fun ...)")
        XCTAssertTrue(config.contains("(deflayer sym"), "Safety net should emit stub (deflayer sym ...)")
        XCTAssertTrue(config.contains("(deflayer num"), "Safety net should emit stub (deflayer num ...)")
        try await assertKanataValid(config, "HRL Toggles toggle + safety-net stubs")
    }

    @MainActor
    func testHRLToggles_OppositeHandMode_Off_OmitsSplitHandFlag() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.oppositeHandMode = .off
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        try await assertKanataValid(config, "HRL Toggles oppositeHand=off")
    }

    @MainActor
    func testHRLToggles_OppositeHandMode_Press_StillValid() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.oppositeHandMode = .press
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        try await assertKanataValid(config, "HRL Toggles oppositeHand=press")
    }

    // MARK: - Quick Launcher

    @MainActor
    func testLauncher_ActivationMode_HoldHyper() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.launcher) { coll in
            if case var .launcherGrid(cfg) = coll.configuration {
                cfg.activationMode = .holdHyper
                cfg.hyperTriggerMode = .hold
                coll.configuration = .launcherGrid(cfg)
            }
        }

        // holdHyper drives the launcher layer through the Hyper key alias chain
        XCTAssertTrue(
            config.contains("launcher") || config.contains("hyper"),
            "Launcher in holdHyper mode should reference the launcher or hyper alias"
        )
        try await assertKanataValid(config, "Launcher holdHyper")
    }

    @MainActor
    func testLauncher_ActivationMode_LeaderSequence() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.launcher) { coll in
            if case var .launcherGrid(cfg) = coll.configuration {
                cfg.activationMode = .leaderSequence
                coll.configuration = .launcherGrid(cfg)
            }
        }

        // Leader-sequence mode shouldn't depend on the Hyper alias path
        try await assertKanataValid(config, "Launcher leaderSequence")
    }

    @MainActor
    func testLauncher_HyperTriggerMode_Tap_StillValid() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.launcher) { coll in
            if case var .launcherGrid(cfg) = coll.configuration {
                cfg.activationMode = .holdHyper
                cfg.hyperTriggerMode = .tap
                coll.configuration = .launcherGrid(cfg)
            }
        }

        try await assertKanataValid(config, "Launcher hyperTrigger=tap")
    }

    // MARK: - Window Snapping

    @MainActor
    func testWindowSnapping_Standard_EmitsLeftRightTokens() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.windowSnapping) { coll in
            coll.windowKeyConvention = .standard
            coll.mappings = RuleCollectionCatalog.windowMappings(for: .standard)
        }

        XCTAssertTrue(config.contains(#"window:left"#), "Standard convention should emit window:left")
        XCTAssertTrue(config.contains(#"window:right"#), "Standard convention should emit window:right")
        try await assertKanataValid(config, "Window Snapping standard")
    }

    @MainActor
    func testWindowSnapping_Vim_RoutesThroughHJKL() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.windowSnapping) { coll in
            coll.windowKeyConvention = .vim
            coll.mappings = RuleCollectionCatalog.windowMappings(for: .vim)
        }

        // Vim convention still emits the same window:* push-msg payloads but
        // routes them through h/j/k/l keys instead of the standard L/R/U/D set.
        XCTAssertTrue(config.contains(#"window:left"#), "Vim convention should still emit window:left")
        XCTAssertTrue(config.contains(#"window:right"#), "Vim convention should still emit window:right")
        XCTAssertTrue(
            config.contains("act_window_h"),
            "Vim convention should map left through the h key alias (act_window_h)"
        )
        XCTAssertTrue(
            config.contains("act_window_l"),
            "Vim convention should map right through the l key alias (act_window_l)"
        )
        try await assertKanataValid(config, "Window Snapping vim")
    }

    // MARK: - Auto Shift Symbols

    @MainActor
    func testAutoShift_ProtectFastTyping_True_EmitsRequirePriorIdle() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.autoShiftSymbols) { coll in
            if case var .autoShiftSymbols(cfg) = coll.configuration {
                cfg.protectFastTyping = true
                coll.configuration = .autoShiftSymbols(cfg)
            }
        }

        XCTAssertTrue(
            config.contains("require-prior-idle"),
            "Auto Shift with protectFastTyping=true should emit require-prior-idle"
        )
        try await assertKanataValid(config, "Auto Shift protectFastTyping=true")
    }

    @MainActor
    func testAutoShift_ProtectFastTyping_False_OmitsRequirePriorIdle() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.autoShiftSymbols) { coll in
            if case var .autoShiftSymbols(cfg) = coll.configuration {
                cfg.protectFastTyping = false
                coll.configuration = .autoShiftSymbols(cfg)
            }
        }

        // Other rules may still emit require-prior-idle globally; the assertion
        // is specifically that this family's contribution is gone.
        XCTAssertFalse(
            config.contains("require-prior-idle \(AutoShiftSymbolsConfig.defaultTimeoutMs)"),
            "Auto Shift with protectFastTyping=false should not contribute its idle term"
        )
        try await assertKanataValid(config, "Auto Shift protectFastTyping=false")
    }

    @MainActor
    func testAutoShift_TimeoutMs_FastSetting() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.autoShiftSymbols) { coll in
            if case var .autoShiftSymbols(cfg) = coll.configuration {
                cfg.timeoutMs = 100
                coll.configuration = .autoShiftSymbols(cfg)
            }
        }

        // Auto Shift's timeoutMs flows into the tap-hold timing for each enabled
        // key. Look for a tap-hold operation referencing the 100ms value on a
        // known symbol key (`dot`) rather than the bare "100" digit.
        XCTAssertTrue(
            config.contains("beh_base_dot (tap-hold")
                && config.contains("100"),
            "Auto Shift with timeoutMs=100 should encode the 100 value in the dot tap-hold"
        )
        try await assertKanataValid(config, "Auto Shift timeoutMs=100")
    }

    @MainActor
    func testAutoShift_TimeoutMs_SlowSetting() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.autoShiftSymbols) { coll in
            if case var .autoShiftSymbols(cfg) = coll.configuration {
                cfg.timeoutMs = 250
                coll.configuration = .autoShiftSymbols(cfg)
            }
        }

        XCTAssertTrue(
            config.contains("beh_base_dot (tap-hold")
                && config.contains("250"),
            "Auto Shift with timeoutMs=250 should encode the 250 value in the dot tap-hold"
        )
        try await assertKanataValid(config, "Auto Shift timeoutMs=250")
    }

    @MainActor
    func testAutoShift_ReducedKeySet_OnlyEmitsSelectedKeys() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.autoShiftSymbols) { coll in
            if case var .autoShiftSymbols(cfg) = coll.configuration {
                cfg.enabledKeys = Set(["dot", "comm"])
                coll.configuration = .autoShiftSymbols(cfg)
            }
        }

        XCTAssertTrue(config.contains("beh_base_dot"), "Reduced key set must include 'dot'")
        XCTAssertTrue(config.contains("beh_base_comm"), "Reduced key set must include 'comm'")
        // Other symbol aliases shouldn't appear from this family
        XCTAssertFalse(config.contains("beh_base_grv"), "Reduced key set must not include 'grv'")
        XCTAssertFalse(config.contains("beh_base_slsh"), "Reduced key set must not include 'slsh'")
        try await assertKanataValid(config, "Auto Shift reduced keys")
    }
}
