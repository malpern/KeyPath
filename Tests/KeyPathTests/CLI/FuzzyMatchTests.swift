@testable import KeyPathCLI
import XCTest

final class FuzzyMatchTests: XCTestCase {
    func testExactMatchReturnsZero() {
        XCTAssertEqual(FuzzyMatch.levenshtein("hello", "hello"), 0)
    }

    func testSingleCharDifference() {
        XCTAssertEqual(FuzzyMatch.levenshtein("vim", "vimm"), 1)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(FuzzyMatch.levenshtein("Vim", "vim"), 0)
    }

    func testCompletelyDifferent() {
        XCTAssertTrue(FuzzyMatch.levenshtein("abc", "xyz") > 2)
    }

    func testSuggestionsReturnsCloseMatches() {
        let candidates = ["Vim Navigation", "Home Row Mods", "Caps Lock Remap", "Chord Groups"]
        let results = FuzzyMatch.suggestions(for: "Chrod Groups", from: candidates)
        XCTAssertTrue(results.contains("Chord Groups"))
    }

    func testSuggestionsExcludesDistantMatches() {
        let candidates = ["vim-navigation", "home-row-mods"]
        let results = FuzzyMatch.suggestions(for: "zzzzz", from: candidates)
        XCTAssertTrue(results.isEmpty)
    }

    func testSuggestionsRankedByDistance() {
        let candidates = ["vim", "vimm", "vimmm"]
        let results = FuzzyMatch.suggestions(for: "vi", from: candidates)
        XCTAssertEqual(results.first, "vim")
    }

    func testSuggestionsLimited() {
        let candidates = (1 ... 10).map { "a\($0)" }
        let results = FuzzyMatch.suggestions(for: "a", from: candidates, limit: 3)
        XCTAssertEqual(results.count, 3)
    }
}
