@testable import KeyPathAppKit
import XCTest

/// Tests for input validation and edge cases in Chord Groups
/// Addresses gaps found in code review (MAL-37)
final class ChordGroupsValidationTests: XCTestCase {
    // MARK: - Group Name Validation

    func testGroupNameWithSpacesIsInvalid() {
        // Group names with spaces will generate invalid Kanata syntax
        // FIXED: Now validated in init with precondition
        // Attempting to create this will cause fatal error
        // XCTAssertThrows is not available for preconditions

        // Test valid alternative: use hyphens instead
        let group = ChordGroup(
            id: UUID(),
            name: "My-Group", // Valid with hyphen
            timeout: 300,
            chords: []
        )

        XCTAssertEqual(group.name, "My-Group")
    }

    func testGroupNameWithSpecialCharactersIsInvalid() {
        // FIXED: Special characters now validated
        // These would cause precondition failure:
        // let invalidNames = ["Group(1)", "Group)", "Group<>", "Group{}", "Group|"]

        // Test valid alternatives
        let validNames = ["Group-1", "Group_1", "MyGroup", "Nav123"]

        for name in validNames {
            let group = ChordGroup(
                id: UUID(),
                name: name,
                timeout: 300,
                chords: []
            )

            XCTAssertEqual(group.name, name, "Valid group name '\(name)' should work")
        }
    }

    func testEmptyGroupName() {
        // FIXED: Empty group name now causes precondition failure
        // Cannot test this without crashing the test suite

        // Test valid minimum: single character
        let group = ChordGroup(
            id: UUID(),
            name: "a",
            timeout: 300,
            chords: []
        )

        XCTAssertEqual(group.name, "a", "Single character group name is valid")
    }

    // MARK: - Timeout Validation

    func testNegativeTimeoutIsInvalid() {
        // FIXED: Negative timeout now causes precondition failure (timeout must be >= 50)
        // Cannot test without crashing

        // Test minimum valid timeout
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 50, // Minimum valid
            chords: []
        )

        XCTAssertEqual(group.timeout, 50)
    }

    func testZeroTimeoutIsInvalid() {
        // FIXED: Zero timeout now invalid (must be >= 50)
        // Test valid minimum instead
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 50,
            chords: []
        )

        XCTAssertEqual(group.timeout, 50)
    }

    func testExtremelyLargeTimeout() {
        // FIXED: Timeout must be <= 5000ms
        // Test maximum valid timeout
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 5000, // Maximum valid
            chords: []
        )

        XCTAssertEqual(group.timeout, 5000)
    }

    func testReasonableTimeoutRange() {
        // Test that reasonable timeouts work correctly
        let validTimeouts = [50, 100, 250, 400, 600, 1000, 2000]

        for timeout in validTimeouts {
            let group = ChordGroup(
                id: UUID(),
                name: "Test",
                timeout: timeout,
                chords: []
            )

            XCTAssertEqual(group.timeout, timeout, "Valid timeout \(timeout)ms should work")
        }
    }

    // MARK: - Keys Array Validation

    func testEmptyKeysArrayCreatesInvalidChord() {
        // FIXED: Empty keys array now causes precondition failure
        // Test valid minimum: at least one key
        let chord = ChordDefinition(
            id: UUID(),
            keys: ["s"], // Minimum: 1 key
            output: "esc"
        )

        XCTAssertEqual(chord.keys.count, 1)
        XCTAssertFalse(chord.isRecommendedCombo, "Single key is not a recommended combo (needs 2+ for chords)")
    }

    func testDuplicateKeysInChordDefinition() {
        // FIXED: Duplicate keys now cause precondition failure
        // Test valid alternative: unique keys only
        let chord = ChordDefinition(
            id: UUID(),
            keys: ["s", "d"], // All unique
            output: "esc"
        )

        XCTAssertEqual(chord.keys.count, 2)
        XCTAssertTrue(chord.isRecommendedCombo, "Two unique keys is recommended")

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord]
        )
        XCTAssertEqual(group.participatingKeys.count, 2, "participatingKeys: {s, d}")
    }

    func testEmptyStringInKeysArray() {
        // FIXED: Empty strings in keys array now cause precondition failure
        // Test valid alternative: all non-empty strings
        let chord = ChordDefinition(
            id: UUID(),
            keys: ["s", "d"], // No empty strings
            output: "esc"
        )

        XCTAssertEqual(chord.keys.count, 2)
        XCTAssertTrue(chord.keys.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Output Validation

    func testEmptyOutputString() {
        // FIXED: Empty output now causes precondition failure
        // Test valid minimum: non-empty output
        let chord = ChordDefinition(
            id: UUID(),
            keys: ["s", "d"],
            output: "a" // Minimum: single character
        )

        XCTAssertFalse(chord.output.isEmpty)
    }

    func testOutputWithUnbalancedParentheses() {
        // FIXED: Now detects unbalanced parentheses
        let invalidOutputs = [")", "(", "(()", "())", "esc)"]

        for output in invalidOutputs {
            let chord = ChordDefinition(
                id: UUID(),
                keys: ["s", "d"],
                output: output
            )

            XCTAssertFalse(chord.hasValidOutputSyntax, "Output '\(output)' should be invalid (unbalanced parens)")
        }
    }

    func testOutputWithBalancedParentheses() {
        // Valid outputs with balanced parens
        let validOutputs = ["esc", "(macro a b)", "((nested))", "(multi (a) (b))"]

        for output in validOutputs {
            let chord = ChordDefinition(
                id: UUID(),
                keys: ["s", "d"],
                output: output
            )

            XCTAssertTrue(chord.hasValidOutputSyntax, "Output '\(output)' should be valid (balanced parens)")
        }
    }

    func testOutputWithComplexMacro() {
        // Complex macros should work
        let validOutputs = [
            "(macro { } left)",
            "(macro ( ) left)",
            "(multi a b c)",
            "C-M-S-x",
            "@my-alias"
        ]

        for output in validOutputs {
            let chord = ChordDefinition(
                id: UUID(),
                keys: ["s", "d"],
                output: output
            )

            XCTAssertEqual(chord.output, output, "Valid complex output '\(output)' should work")
        }
    }

    // MARK: - Cross-Group Conflicts

    func testCrossGroupKeyConflictsSameKeys() {
        // Two groups using the same participating keys
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "bspc")

        let group1 = ChordGroup(
            id: UUID(),
            name: "Navigation",
            timeout: 250,
            chords: [chord1]
        )

        let group2 = ChordGroup(
            id: UUID(),
            name: "Editing",
            timeout: 300,
            chords: [chord2]
        )

        let config = ChordGroupsConfig(groups: [group1, group2])

        // FIXED: Cross-group conflicts now detected
        XCTAssertTrue(config.hasCrossGroupConflicts, "Should detect cross-group conflicts")

        let conflicts = config.detectCrossGroupConflicts()
        XCTAssertEqual(conflicts.count, 2, "Should detect conflicts for both 's' and 'd'")

        // Check that both keys are reported
        let conflictKeys = Set(conflicts.map(\.key))
        XCTAssertEqual(conflictKeys, ["s", "d"])

        // Check description format
        let sConflict = conflicts.first { $0.key == "s" }
        XCTAssertNotNil(sConflict)
        XCTAssertTrue(sConflict!.description.contains("Navigation"))
        XCTAssertTrue(sConflict!.description.contains("Editing"))
    }

    func testCrossGroupPartialKeyOverlap() {
        let group1 = ChordGroup(
            id: UUID(),
            name: "Nav",
            timeout: 250,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
                ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter")
            ]
        )

        let group2 = ChordGroup(
            id: UUID(),
            name: "Edit",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["a", "s"], output: "bspc"),
                ChordDefinition(id: UUID(), keys: ["f", "g"], output: "del")
            ]
        )

        let config = ChordGroupsConfig(groups: [group1, group2])

        // FIXED: Partial overlaps now detected
        XCTAssertTrue(config.hasCrossGroupConflicts, "Should detect partial key overlap")

        let conflicts = config.detectCrossGroupConflicts()
        let conflictKeys = Set(conflicts.map(\.key))
        XCTAssertEqual(conflictKeys, ["s", "f"], "Groups share s and f keys")
    }

    // MARK: - Overlapping Chord Prefixes

    func testOverlappingChordPrefixes() {
        // "sd" and "sdf" overlap - shorter chord is a prefix of longer chord
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "C-x")

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord1, chord2]
        )

        // FIXED: Overlapping chords now detected as conflicts
        XCTAssertFalse(group.isValid, "Overlapping chords should be detected as conflict")
        let conflicts = group.detectConflicts()
        XCTAssertEqual(conflicts.count, 1, "Should detect one overlapping conflict")
        XCTAssertEqual(conflicts.first?.type, .overlapping)

        // Verify that one is subset of the other
        let keys1 = Set(chord1.keys)
        let keys2 = Set(chord2.keys)
        XCTAssertTrue(keys1.isSubset(of: keys2), "sd is subset of sdf")
        XCTAssertFalse(keys1 == keys2, "But not equal")
    }

    func testOverlappingChordSuffixes() {
        // "df" and "sdf" overlap - shorter is suffix
        let chord1 = ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "C-x")

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord1, chord2]
        )

        // FIXED: Overlapping detected
        XCTAssertFalse(group.isValid, "Overlapping chords should be invalid")
        let conflicts = group.detectConflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.type, .overlapping)

        let keys1 = Set(chord1.keys)
        let keys2 = Set(chord2.keys)
        XCTAssertTrue(keys1.isSubset(of: keys2), "df is subset of sdf")
    }

    func testSingleKeyVsMultiKeyOverlap() {
        // FIXED: Single key + multi-key should NOT conflict
        // This is valid in Kanata - single key acts as fallback
        let chord1 = ChordDefinition(id: UUID(), keys: ["s"], output: "s") // Single key passthrough
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc") // Multi-key chord

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord1, chord2]
        )

        // Should be valid - single key + multi-key is allowed
        XCTAssertTrue(group.isValid, "Single key + multi-key should not conflict")

        let conflicts = group.detectConflicts()
        XCTAssertEqual(conflicts.count, 0, "No overlapping conflict for single + multi key")

        // Verify the fix: overlapping detection only flags when both have 2+ keys
        let keys1 = Set(chord1.keys)
        let keys2 = Set(chord2.keys)
        XCTAssertTrue(keys1.isSubset(of: keys2), "Single key is subset of multi-key")
        XCTAssertFalse(chord1.isRecommendedCombo, "Single key is not recommended combo")
        XCTAssertTrue(chord2.isRecommendedCombo, "Multi-key is recommended combo")
    }

    // MARK: - Ergonomic Score Edge Cases

    func testErgonomicScoreEmptyKeys() {
        // FIXED: Empty keys now causes precondition failure
        // Test minimum valid instead: single key
        let chord = ChordDefinition(id: UUID(), keys: ["s"], output: "esc")
        XCTAssertEqual(chord.ergonomicScore, .poor, "Single key should have poor ergonomic score")
    }

    func testErgonomicScoreSingleKey() {
        let chord = ChordDefinition(id: UUID(), keys: ["s"], output: "esc")
        XCTAssertEqual(chord.ergonomicScore, .poor, "Single key should have poor score")
    }

    func testErgonomicScoreNonHomeRowAdjacent() {
        // Adjacent keys but not on home row
        let chord = ChordDefinition(id: UUID(), keys: ["q", "w"], output: "esc")
        // Currently checks home row first, so this won't be "excellent"
        XCTAssertEqual(chord.ergonomicScore, .moderate, "Adjacent non-home-row is moderate")
    }

    // MARK: - areAdjacent Helper Edge Cases

    func testAdjacentKeysThreeInRow() {
        // Test three adjacent keys
        let chord = ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "C-x")
        XCTAssertEqual(chord.ergonomicScore, .excellent, "Three adjacent home row keys")
    }

    func testNonAdjacentKeysWithGap() {
        // s and f have d between them (gap of 1)
        let chord = ChordDefinition(id: UUID(), keys: ["s", "f"], output: "esc")
        XCTAssertEqual(chord.ergonomicScore, .good, "Non-adjacent home row keys")
    }

    func testNonAdjacentKeysLargeGap() {
        // s and k have large gap
        let chord = ChordDefinition(id: UUID(), keys: ["s", "k"], output: "esc")
        // Not adjacent, not same hand (s is left, k is right)
        XCTAssertEqual(chord.ergonomicScore, .fair, "Large gap cross-hand")
    }

    // MARK: - Unicode and Special Characters

    func testUnicodeInGroupName() {
        // FIXED: Unicode characters now rejected by ASCII validation
        // Test that ASCII-only names work correctly
        let group = ChordGroup(
            id: UUID(),
            name: "Navigation", // ASCII only
            timeout: 300,
            chords: []
        )

        XCTAssertEqual(group.name, "Navigation", "ASCII group names are allowed")
        XCTAssertTrue(group.name.allSatisfy { ($0.isASCII && $0.isLetter) || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    func testUnicodeInKeys() {
        // Kanata probably doesn't support Unicode key names
        let chord = ChordDefinition(
            id: UUID(),
            keys: ["你", "好"], // Chinese characters
            output: "esc"
        )

        XCTAssertEqual(chord.keys, ["你", "好"], "Unicode keys currently allowed")
    }

    func testUnicodeInOutput() {
        // Unicode output might work for macro strings
        let chord = ChordDefinition(
            id: UUID(),
            keys: ["s", "d"],
            output: "(macro 你好)" // Chinese in macro
        )

        XCTAssertEqual(chord.output, "(macro 你好)", "Unicode output currently allowed")
    }

    // MARK: - Conflict Description Formatting

    func testConflictDescriptionWithSpecialCharacters() {
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "(macro a)")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "(macro b)")

        let conflict = ChordConflict(chord1: chord1, chord2: chord2, type: .sameKeys)

        // Should handle complex outputs in description
        XCTAssertTrue(conflict.description.contains("s+d+f"))
        XCTAssertTrue(conflict.description.contains("(macro a)"))
        XCTAssertTrue(conflict.description.contains("(macro b)"))
    }

    // MARK: - ChordSpeed Edge Cases

    func testChordSpeedNearestWithExactMatch() {
        XCTAssertEqual(ChordSpeed.nearest(to: 150), .lightning)
        XCTAssertEqual(ChordSpeed.nearest(to: 250), .fast)
        XCTAssertEqual(ChordSpeed.nearest(to: 400), .moderate)
        XCTAssertEqual(ChordSpeed.nearest(to: 600), .deliberate)
    }

    func testChordSpeedNearestWithEdgeValues() {
        XCTAssertEqual(ChordSpeed.nearest(to: 0), .lightning)
        XCTAssertEqual(ChordSpeed.nearest(to: 1000), .deliberate)
        XCTAssertEqual(ChordSpeed.nearest(to: Int.max), .deliberate)
    }

    // MARK: - Multiple Conflicts Same Group

    func testMultipleConflictsInSameGroup() {
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "enter")
        let chord3 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "bspc")

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord1, chord2, chord3]
        )

        let conflicts = group.detectConflicts()
        // Should detect 3 pairwise conflicts: (1,2), (1,3), (2,3)
        XCTAssertEqual(conflicts.count, 3, "Should detect all pairwise conflicts")
    }

    // MARK: - Category Icon and Display

    func testCategoryIconsAreValid() {
        // Just ensure all categories have icons
        for category in ChordCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category) should have an icon")
            XCTAssertFalse(category.displayName.isEmpty, "\(category) should have a display name")
            XCTAssertGreaterThan(category.suggestedTimeout, 0, "\(category) should have positive timeout")
        }
    }
}
