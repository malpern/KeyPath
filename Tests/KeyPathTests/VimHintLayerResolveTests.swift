@testable import KeyPathAppKit
import XCTest

/// Pure-data assertions on `VimHintLayer.resolveHint` — the per-key
/// lookup that maps a physical macOS keyCode to a `VimHint` given the
/// current strategy / mode / advanced flag. No view rendering.
final class VimHintLayerResolveTests: XCTestCase {
    // macOS virtual keycodes.
    private let hKeyCode: UInt16 = 4
    private let jKeyCode: UInt16 = 38
    private let kKeyCode: UInt16 = 40
    private let lKeyCode: UInt16 = 37
    private let gKeyCode: UInt16 = 5
    private let zeroKeyCode: UInt16 = 29
    private let escKeyCode: UInt16 = 53

    // MARK: - hjkl resolve to arrow hints in every supported strategy

    func testHjklAlwaysResolveInNormalMode() {
        for strategy in [KindaVimStrategy.accessibility, .keyboard, .hybrid] {
            let h = VimHintLayer.resolveHint(
                for: hKeyCode, strategy: strategy, mode: .normal, showAdvanced: false
            )
            let j = VimHintLayer.resolveHint(
                for: jKeyCode, strategy: strategy, mode: .normal, showAdvanced: false
            )
            let k = VimHintLayer.resolveHint(
                for: kKeyCode, strategy: strategy, mode: .normal, showAdvanced: false
            )
            let l = VimHintLayer.resolveHint(
                for: lKeyCode, strategy: strategy, mode: .normal, showAdvanced: false
            )
            XCTAssertEqual(h?.displayLabel, "←", "h missing for \(strategy)")
            XCTAssertEqual(j?.displayLabel, "↓", "j missing for \(strategy)")
            XCTAssertEqual(k?.displayLabel, "↑", "k missing for \(strategy)")
            XCTAssertEqual(l?.displayLabel, "→", "l missing for \(strategy)")
        }
    }

    // MARK: - Strategy filters carry through

    func testGgIsAccessibilityOnly() {
        let ax = VimHintLayer.resolveHint(
            for: gKeyCode, strategy: .accessibility, mode: .normal, showAdvanced: false
        )
        let kb = VimHintLayer.resolveHint(
            for: gKeyCode, strategy: .keyboard, mode: .normal, showAdvanced: false
        )
        XCTAssertEqual(ax?.displayLabel, "gg")
        XCTAssertNil(kb, "Keyboard strategy should drop gg")
    }

    // MARK: - Mode filters

    func testInsertModeYieldsNoHints() {
        let result = VimHintLayer.resolveHint(
            for: hKeyCode, strategy: .accessibility, mode: .insert, showAdvanced: false
        )
        XCTAssertNil(result, "Insert mode should suppress all hints")
    }

    func testIgnoredStrategyYieldsNoHints() {
        let result = VimHintLayer.resolveHint(
            for: hKeyCode, strategy: .ignored, mode: .normal, showAdvanced: false
        )
        XCTAssertNil(result, "Ignored strategy should suppress hints even for hjkl")
    }

    // MARK: - Advanced toggle gates non-core hints

    func testZeroIsCoreEvenWithAdvancedOff() {
        // 0 is a core line-motion key; should resolve regardless of toggle.
        let result = VimHintLayer.resolveHint(
            for: zeroKeyCode, strategy: .accessibility, mode: .normal, showAdvanced: false
        )
        XCTAssertEqual(result?.displayLabel, "0")
        XCTAssertEqual(result?.tier, .core)
    }

    // MARK: - Keys without a vim binding return nil

    func testEscapeHasNoHint() {
        let result = VimHintLayer.resolveHint(
            for: escKeyCode, strategy: .accessibility, mode: .normal, showAdvanced: true
        )
        XCTAssertNil(result, "Escape isn't a vim normal-mode binding")
    }

    // MARK: - Op-pending narrows the set

    func testOperatorPendingResolvesMotionsAndOperators() {
        // h is a motion → resolves
        let h = VimHintLayer.resolveHint(
            for: hKeyCode, strategy: .accessibility, mode: .operatorPending, showAdvanced: false
        )
        XCTAssertNotNil(h)

        // 'a' (enter Insert via append) is in `.enterInsert` group, which is
        // dropped in op-pending → nil
        let aKeyCode: UInt16 = 0
        let a = VimHintLayer.resolveHint(
            for: aKeyCode, strategy: .accessibility, mode: .operatorPending, showAdvanced: false
        )
        XCTAssertNil(a, "enterInsert group is dropped in operator-pending")
    }
}
