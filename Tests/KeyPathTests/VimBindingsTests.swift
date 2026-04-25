@testable import KeyPathAppKit
import XCTest

/// Pure-data assertions on the VimBindings reference table. No async,
/// no shared singletons — just filter-by-strategy and filter-by-mode
/// behaviour on the static catalogue.
final class VimBindingsTests: XCTestCase {
    // MARK: - hjkl is core in every strategy

    func testHjklAreCoreInAllStrategies() {
        for strategy in [KindaVimStrategy.accessibility, .keyboard, .hybrid] {
            let hints = VimBindings.hints(strategy: strategy, mode: .normal, showAdvanced: false)
            for key in ["h", "j", "k", "l"] {
                let hint = hints.first { $0.key == key }
                XCTAssertNotNil(hint, "\(key) missing for strategy \(strategy)")
                XCTAssertEqual(hint?.tier, .core, "\(key) should be core, was \(String(describing: hint?.tier))")
            }
        }
    }

    // MARK: - Strategy filters

    func testKeyboardStrategyDropsAccessibilityOnlyCommands() {
        let kb = VimBindings.hints(strategy: .keyboard, mode: .normal, showAdvanced: true)
        let kbKeys = Set(kb.map(\.key))
        // Accessibility-only per kindaVim docs:
        XCTAssertFalse(kbKeys.contains("g"), "Keyboard strategy should not list gg")
        XCTAssertFalse(kbKeys.contains("G"), "Keyboard strategy should not list G")
        XCTAssertFalse(kbKeys.contains("ctrl-d"), "Keyboard strategy should not list Ctrl-D")
        XCTAssertFalse(kbKeys.contains("%"), "Keyboard strategy should not list %")
        XCTAssertFalse(kbKeys.contains("/"), "Keyboard strategy should not list /")
    }

    func testAccessibilityStrategyIsTheSuperset() {
        let ax = VimBindings.hints(strategy: .accessibility, mode: .normal, showAdvanced: true)
        let kb = VimBindings.hints(strategy: .keyboard, mode: .normal, showAdvanced: true)
        XCTAssertGreaterThan(
            ax.count, kb.count,
            "Accessibility should expose more commands than the Keyboard fallback"
        )
    }

    func testIgnoredStrategyEmitsNothing() {
        let hints = VimBindings.hints(strategy: .ignored, mode: .normal, showAdvanced: true)
        XCTAssertTrue(hints.isEmpty, "Ignored strategy should return no hints")
    }

    // MARK: - Mode filters

    func testInsertModeEmitsNothing() {
        let hints = VimBindings.hints(strategy: .accessibility, mode: .insert, showAdvanced: true)
        XCTAssertTrue(hints.isEmpty, "Insert mode is the user's escape hatch — no hints")
    }

    func testOperatorPendingShrinksToMotionsAndOperators() {
        let hints = VimBindings.hints(
            strategy: .accessibility,
            mode: .operatorPending,
            showAdvanced: false
        )
        let groups = Set(hints.map(\.group))
        XCTAssertTrue(groups.contains(.movement))
        XCTAssertTrue(groups.contains(.operators))
        // Edit and enterInsert are dropped — not valid follow-ups in op-pending.
        XCTAssertFalse(groups.contains(.edit))
        XCTAssertFalse(groups.contains(.enterInsert))
    }

    // MARK: - Advanced toggle

    func testAdvancedHiddenByDefault() {
        let off = VimBindings.hints(strategy: .accessibility, mode: .normal, showAdvanced: false)
        XCTAssertFalse(off.contains(where: { $0.tier == .advanced }))

        let on = VimBindings.hints(strategy: .accessibility, mode: .normal, showAdvanced: true)
        XCTAssertTrue(on.contains(where: { $0.tier == .advanced }))
    }

    // MARK: - Grouping

    func testGroupedDropsEmptyBuckets() {
        let groups = VimBindings.grouped(
            strategy: .keyboard,
            mode: .normal,
            showAdvanced: false
        )
        for group in groups {
            XCTAssertFalse(group.entries.isEmpty, "\(group.group) should have been omitted if empty")
        }
    }

    func testGroupedMovementIsFirst() {
        let groups = VimBindings.grouped(
            strategy: .accessibility,
            mode: .normal,
            showAdvanced: true
        )
        XCTAssertEqual(groups.first?.group, .movement, "Move group should sort first")
    }
}
