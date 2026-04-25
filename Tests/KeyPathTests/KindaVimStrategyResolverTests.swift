@testable import KeyPathAppKit
import XCTest

/// Pure-data assertions on the kindaVim plist parser + bundle-ID
/// resolver. No file I/O — everything goes through `parsePreferenceLists`
/// with synthetic plist data.
final class KindaVimStrategyResolverTests: XCTestCase {
    private let resolver = KindaVimStrategyResolver()

    // MARK: - Parsing

    func testParseExtractsAllThreeLists() throws {
        let plist: [String: Any] = [
            "appsToIgnore": ["net.kovidgoyal.kitty", "com.mitchellh.ghostty"],
            "appsForWhichToEnforceKeyboardStrategy": ["com.tinyspeck.slackmacgap"],
            "appsForWhichToUseHybridMode": ["com.example.hybrid"],
            "unrelatedKey": 42,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )

        let lists = KindaVimStrategyResolver.parsePreferenceLists(from: data)

        XCTAssertEqual(lists.ignored, ["net.kovidgoyal.kitty", "com.mitchellh.ghostty"])
        XCTAssertEqual(lists.keyboardEnforced, ["com.tinyspeck.slackmacgap"])
        XCTAssertEqual(lists.hybrid, ["com.example.hybrid"])
    }

    func testParseEmptyPlistGivesEmptyLists() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [String: Any](),
            format: .binary,
            options: 0
        )
        let lists = KindaVimStrategyResolver.parsePreferenceLists(from: data)
        XCTAssertEqual(lists, .empty)
    }

    func testParseGarbageReturnsEmpty() {
        let data = Data([0x00, 0x01, 0x02])
        let lists = KindaVimStrategyResolver.parsePreferenceLists(from: data)
        XCTAssertEqual(lists, .empty)
    }

    // MARK: - Resolution priority

    func testIgnoredBeatsKeyboardBeatsHybrid() {
        // Same bundle-ID in all three lists should resolve to the strictest
        // one (.ignored). This is defensive — kindaVim shouldn't normally
        // produce overlapping lists, but a hand-edited plist could.
        let lists = KindaVimStrategyResolver.PreferenceLists(
            ignored: ["com.example.app"],
            keyboardEnforced: ["com.example.app"],
            hybrid: ["com.example.app"]
        )
        XCTAssertEqual(resolver.strategy(for: "com.example.app", lists: lists), .ignored)
    }

    func testHybridBeatsKeyboardWhenIgnoredIsAbsent() {
        let lists = KindaVimStrategyResolver.PreferenceLists(
            ignored: [],
            keyboardEnforced: ["com.example.app"],
            hybrid: ["com.example.app"]
        )
        XCTAssertEqual(resolver.strategy(for: "com.example.app", lists: lists), .hybrid)
    }

    func testKeyboardForExplicitlyEnforcedBundle() {
        let lists = KindaVimStrategyResolver.PreferenceLists(
            ignored: [],
            keyboardEnforced: ["com.tinyspeck.slackmacgap"],
            hybrid: []
        )
        XCTAssertEqual(
            resolver.strategy(for: "com.tinyspeck.slackmacgap", lists: lists),
            .keyboard
        )
    }

    func testAccessibilityIsTheDefault() {
        let lists = KindaVimStrategyResolver.PreferenceLists(
            ignored: ["net.kovidgoyal.kitty"],
            keyboardEnforced: [],
            hybrid: []
        )
        XCTAssertEqual(
            resolver.strategy(for: "com.apple.Safari", lists: lists),
            .accessibility
        )
    }

    func testNilOrEmptyBundleIDFallsBackToAccessibility() {
        let lists = KindaVimStrategyResolver.PreferenceLists.empty
        XCTAssertEqual(resolver.strategy(for: nil, lists: lists), .accessibility)
        XCTAssertEqual(resolver.strategy(for: "", lists: lists), .accessibility)
    }
}
