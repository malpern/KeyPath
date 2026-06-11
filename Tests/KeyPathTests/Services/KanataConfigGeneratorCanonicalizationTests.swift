@testable import KeyPathAppKit
import XCTest

/// Pins the defcfg canonicalization for AI-generated configs (#860): whatever
/// header the model emits is stripped and replaced with the KeyPath-owned
/// `KanataDefcfg.aiGenerated` header, which carries the user's
/// `KanataCommandActionsPolicy`. Pure static functions — no `RuntimeCoordinator`
/// is constructed (see TestSeamLintTests).
final class KanataConfigGeneratorCanonicalizationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: KanataCommandActionsPolicy.defaultsKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: KanataCommandActionsPolicy.defaultsKey)
        try super.tearDownWithError()
    }

    // MARK: - Stripping

    func testStripsModelSuppliedDefcfgBlock() {
        let modelOutput = """
        ;; mapping
        (defcfg
          process-unmapped-keys no
          danger-enable-cmd yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        let stripped = KanataConfigGenerator.removingDefcfgBlocks(from: modelOutput)
        XCTAssertFalse(stripped.contains("defcfg"))
        XCTAssertFalse(stripped.contains("danger-enable-cmd"))
        XCTAssertTrue(stripped.contains("(defsrc caps)"))
        XCTAssertTrue(stripped.contains("(deflayer base esc)"))
    }

    func testStripsDefcfgWithNestedLists() {
        let modelOutput = """
        (defcfg
          process-unmapped-keys yes
          macos-dev-names-include (
            "Apple Internal Keyboard"
          )
        )
        (defsrc a)
        (deflayer base b)
        """
        let stripped = KanataConfigGenerator.removingDefcfgBlocks(from: modelOutput)
        XCTAssertFalse(stripped.contains("defcfg"))
        XCTAssertFalse(stripped.contains("macos-dev-names-include"))
        XCTAssertTrue(stripped.contains("(defsrc a)"))
    }

    func testStripsMultipleDefcfgBlocks() {
        let modelOutput = "(defcfg a b)\n(defsrc caps)\n(defcfg c d)\n(deflayer base esc)"
        let stripped = KanataConfigGenerator.removingDefcfgBlocks(from: modelOutput)
        XCTAssertFalse(stripped.contains("defcfg"))
        XCTAssertTrue(stripped.contains("(defsrc caps)"))
        XCTAssertTrue(stripped.contains("(deflayer base esc)"))
    }

    func testLeavesConfigWithoutDefcfgUntouched() {
        let body = "(defsrc caps)\n(deflayer base esc)"
        XCTAssertEqual(KanataConfigGenerator.removingDefcfgBlocks(from: body), body)
    }

    func testUnbalancedDefcfgDropsTailRatherThanHalfStripping() {
        let garbage = "(defsrc caps)\n(defcfg process-unmapped-keys yes"
        let stripped = KanataConfigGenerator.removingDefcfgBlocks(from: garbage)
        XCTAssertTrue(stripped.contains("(defsrc caps)"))
        XCTAssertFalse(stripped.contains("defcfg"))
    }

    // MARK: - Canonical header

    func testCanonicalHeaderPrependedAndPolicyOffByDefault() {
        let modelOutput = """
        (defcfg
          process-unmapped-keys no
          danger-enable-cmd yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        let canonical = KanataConfigGenerator.withCanonicalDefcfg(modelOutput)
        XCTAssertTrue(
            canonical.hasPrefix("(defcfg\n  process-unmapped-keys yes\n)"),
            "Canonical header must lead the config; got: \(canonical.prefix(60))"
        )
        XCTAssertFalse(
            canonical.contains("danger-enable-cmd"),
            "Model-supplied cmd grant must not survive canonicalization when the policy is OFF"
        )
        XCTAssertFalse(canonical.contains("process-unmapped-keys no"))
    }

    func testCanonicalHeaderFollowsPolicyWhenOptedIn() {
        KanataCommandActionsPolicy.setEnabled(true)
        defer { UserDefaults.standard.removeObject(forKey: KanataCommandActionsPolicy.defaultsKey) }

        let canonical = KanataConfigGenerator.withCanonicalDefcfg("(defsrc caps)\n(deflayer base esc)")
        XCTAssertTrue(canonical.contains("danger-enable-cmd yes"))
    }
}
