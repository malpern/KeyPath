@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Tests the generator's orphan-layer safety net.
///
/// When a rule references a layer that no other enabled rule provides
/// (most visibly: Home Row Layer Toggles in toggle mode referencing the
/// Function/Symbol/Numpad layers when those families are disabled), the
/// generator emits a stub `(deflayer ...)` block so kanata accepts the
/// config. Keys mapped into the orphan layer then degrade to transparent
/// (`_`) instead of the whole config failing to load.
///
/// Background: pre-fix, the scanner caught `layer-while-held` and
/// `layer-switch` references but missed `layer-toggle`. HRL Toggles in
/// toggle mode produced configs that kanata rejected. The fix adds
/// `layer-toggle` to the scan pattern in `KanataConfiguration+BlockBuilders`.
final class StubDeflayerSafetyNetTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Run every assertion in this suite even if one fails — surfacing all
        // safety-net regressions in one CI run instead of stopping at the first.
        continueAfterFailure = true
    }

    @MainActor
    private func validateWithKanata(_ config: String) async throws -> (isValid: Bool, errors: [String]) {
        let result = try await KanataCheckHelper.runCheck(config)
        return (result.isValid, result.errors)
    }

    // MARK: - HRL Toggles toggle mode (the case that surfaced this fix)

    /// HRL Toggles in toggle mode references `fun`, `sym`, `num` via
    /// `(layer-toggle ...)` actions. Without the safety net these are
    /// orphan references and kanata --check rejects the config.
    @MainActor
    func testHRLTogglesToggleModeAlone_StubLayersEmitted() {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .toggle
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        // The generated config should reference the orphan layers ...
        XCTAssertTrue(config.contains("(layer-toggle fun)"), "Expected (layer-toggle fun) in output")
        XCTAssertTrue(config.contains("(layer-toggle sym)"), "Expected (layer-toggle sym) in output")
        XCTAssertTrue(config.contains("(layer-toggle num)"), "Expected (layer-toggle num) in output")

        // ... AND emit matching stub deflayer blocks so kanata accepts the config.
        XCTAssertTrue(config.contains("(deflayer fun"), "Expected stub (deflayer fun ...) block")
        XCTAssertTrue(config.contains("(deflayer sym"), "Expected stub (deflayer sym ...) block")
        XCTAssertTrue(config.contains("(deflayer num"), "Expected stub (deflayer num ...) block")
    }

    @MainActor
    func testHRLTogglesToggleModeAlone_KanataAccepts() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .toggle
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        let result = try await validateWithKanata(config)
        XCTAssertTrue(
            result.isValid,
            "Stub deflayer safety net should make this kanata-valid. Errors: \(result.errors)"
        )
    }

    // MARK: - whileHeld mode still works (regression guard for the original scanner)

    @MainActor
    func testHRLTogglesWhileHeldMode_KanataAccepts() async throws {
        let config = MatrixTestHelpers.enabledCollectionConfig(RuleCollectionIdentifier.homeRowLayerToggles) { coll in
            if case var .homeRowLayerToggles(cfg) = coll.configuration {
                cfg.toggleMode = .whileHeld
                coll.configuration = .homeRowLayerToggles(cfg)
            }
        }

        let result = try await validateWithKanata(config)
        XCTAssertTrue(
            result.isValid,
            "whileHeld mode was already covered by the original scanner — must still validate. Errors: \(result.errors)"
        )
    }
}
