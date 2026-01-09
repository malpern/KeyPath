import XCTest
@testable import KeyPathAppKit

final class ChordGroupsConfigTests: XCTestCase {
    // MARK: - Default Initialization

    func testDefaultInit() {
        let config = ChordGroupsConfig()
        XCTAssertEqual(config.groups.count, 0)
        XCTAssertNil(config.activeGroupID)
        XCTAssertFalse(config.showAdvanced)
    }

    // MARK: - Ben Vallack Preset

    func testBenVallackPreset() {
        let config = ChordGroupsConfig.benVallackPreset

        // Should have at least navigation and editing groups
        XCTAssertGreaterThan(config.groups.count, 0)

        let navGroup = config.groups.first { $0.name == "Navigation" }
        XCTAssertNotNil(navGroup, "Navigation group should exist")
        XCTAssertEqual(navGroup?.timeout, 250, "Navigation should use fast timeout")
        XCTAssertEqual(navGroup?.category, .navigation)

        // Check that SD→Esc chord exists
        let sdChord = navGroup?.chords.first { Set($0.keys) == Set(["s", "d"]) }
        XCTAssertNotNil(sdChord, "SD→Esc chord should exist")
        XCTAssertEqual(sdChord?.output, "esc")

        // Check that DF→Enter chord exists
        let dfChord = navGroup?.chords.first { Set($0.keys) == Set(["d", "f"]) }
        XCTAssertNotNil(dfChord, "DF→Enter chord should exist")
        XCTAssertEqual(dfChord?.output, "enter")

        // Check editing group
        let editGroup = config.groups.first { $0.name == "Editing" }
        XCTAssertNotNil(editGroup, "Editing group should exist")
        XCTAssertEqual(editGroup?.timeout, 400, "Editing should use moderate timeout (400ms)")

        // Active group should be set to navigation
        XCTAssertEqual(config.activeGroupID, navGroup?.id)
    }

    func testBenVallackPresetStableIDs() {
        // Issue #2: Preset should use stable UUIDs for equality checks
        let preset1 = ChordGroupsConfig.benVallackPreset
        let preset2 = ChordGroupsConfig.benVallackPreset

        // Group IDs should be stable across calls
        XCTAssertEqual(preset1.groups.count, preset2.groups.count)
        for (group1, group2) in zip(preset1.groups, preset2.groups) {
            XCTAssertEqual(group1.id, group2.id, "Group '\(group1.name)' should have stable ID")

            // Chord IDs should also be stable
            XCTAssertEqual(group1.chords.count, group2.chords.count)
            for (chord1, chord2) in zip(group1.chords, group2.chords) {
                XCTAssertEqual(chord1.id, chord2.id, "Chord in group '\(group1.name)' should have stable ID")
            }
        }

        // Entire config should be equal
        XCTAssertEqual(preset1, preset2, "Ben Vallack preset should be equal across calls")
    }

    // MARK: - Chord Group

    func testChordGroupParticipatingKeys() {
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
                ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter"),
                ChordDefinition(id: UUID(), keys: ["j", "k"], output: "up")
            ]
        )

        let expected: Set<String> = ["s", "d", "f", "j", "k"]
        XCTAssertEqual(group.participatingKeys, expected)
    }

    func testChordGroupValidWithNoConflicts() {
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
                ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter")
            ]
        )

        XCTAssertTrue(group.isValid, "Group with no conflicts should be valid")
    }

    func testChordGroupInvalidWithConflicts() {
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "enter") // Same keys!
            ]
        )

        XCTAssertFalse(group.isValid, "Group with conflicts should be invalid")
    }

    // MARK: - Conflict Detection

    func testDetectConflictSameKeys() {
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "enter")

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord1, chord2]
        )

        let conflicts = group.detectConflicts()
        XCTAssertEqual(conflicts.count, 1, "Should detect one conflict")
        XCTAssertEqual(conflicts[0].type, .sameKeys)
    }

    func testDetectConflictDifferentKeyOrder() {
        // ["s", "d"] and ["d", "s"] should be treated as the same keys
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["d", "s"], output: "enter")

        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [chord1, chord2]
        )

        let conflicts = group.detectConflicts()
        XCTAssertEqual(conflicts.count, 1, "Should detect conflict regardless of key order")
    }

    func testNoConflictDifferentKeys() {
        let group = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc"),
                ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter"),
                ChordDefinition(id: UUID(), keys: ["j", "k"], output: "up")
            ]
        )

        let conflicts = group.detectConflicts()
        XCTAssertEqual(conflicts.count, 0, "Should not detect conflicts for different key combinations")
    }

    // MARK: - Chord Definition

    func testChordDefinitionRecommendedCombo() {
        let twoKeys = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        XCTAssertTrue(twoKeys.isRecommendedCombo, "2 keys is recommended")

        let threeKeys = ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "C-x")
        XCTAssertTrue(threeKeys.isRecommendedCombo, "3 keys is recommended")

        let fourKeys = ChordDefinition(id: UUID(), keys: ["a", "s", "d", "f"], output: "C-c")
        XCTAssertTrue(fourKeys.isRecommendedCombo, "4 keys is recommended")
    }

    func testChordDefinitionNotRecommendedCombo() {
        let oneKey = ChordDefinition(id: UUID(), keys: ["s"], output: "esc")
        XCTAssertFalse(oneKey.isRecommendedCombo, "1 key is not recommended (defeats purpose)")

        let fiveKeys = ChordDefinition(id: UUID(), keys: ["a", "s", "d", "f", "g"], output: "C-c")
        XCTAssertFalse(fiveKeys.isRecommendedCombo, "5 keys is not recommended (too difficult)")
    }

    func testChordDefinitionErgonomicScore() {
        // Excellent: Adjacent home row keys
        let adjacentHomeRow = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        XCTAssertEqual(adjacentHomeRow.ergonomicScore, .excellent)

        // Good: Same hand, home row, but not adjacent
        let sameHandHomeRow = ChordDefinition(id: UUID(), keys: ["s", "f"], output: "esc")
        XCTAssertEqual(sameHandHomeRow.ergonomicScore, .good)

        // Moderate: Same hand, not home row
        let sameHandNotHomeRow = ChordDefinition(id: UUID(), keys: ["q", "w"], output: "esc")
        XCTAssertEqual(sameHandNotHomeRow.ergonomicScore, .moderate)

        // Fair: Cross-hand
        let crossHand = ChordDefinition(id: UUID(), keys: ["a", "j"], output: "esc")
        XCTAssertEqual(crossHand.ergonomicScore, .fair)

        // Poor: Single key
        let singleKey = ChordDefinition(id: UUID(), keys: ["s"], output: "esc")
        XCTAssertEqual(singleKey.ergonomicScore, .poor)
    }

    // MARK: - Chord Category

    func testChordCategorySuggestedTimeouts() {
        XCTAssertEqual(ChordCategory.navigation.suggestedTimeout, 250)  // Fast
        XCTAssertEqual(ChordCategory.editing.suggestedTimeout, 400)     // Moderate
        XCTAssertEqual(ChordCategory.symbols.suggestedTimeout, 150)     // Lightning
        XCTAssertEqual(ChordCategory.modifiers.suggestedTimeout, 600)   // Deliberate
        XCTAssertEqual(ChordCategory.custom.suggestedTimeout, 400)      // Moderate
    }

    func testChordCategoryDisplayNames() {
        XCTAssertEqual(ChordCategory.navigation.displayName, "Navigation")
        XCTAssertEqual(ChordCategory.editing.displayName, "Editing")
        XCTAssertEqual(ChordCategory.symbols.displayName, "Symbols")
        XCTAssertEqual(ChordCategory.modifiers.displayName, "Modifiers")
        XCTAssertEqual(ChordCategory.custom.displayName, "Custom")
    }

    // MARK: - Chord Speed

    func testChordSpeedMilliseconds() {
        XCTAssertEqual(ChordSpeed.lightning.milliseconds, 150)
        XCTAssertEqual(ChordSpeed.fast.milliseconds, 250)
        XCTAssertEqual(ChordSpeed.moderate.milliseconds, 400)
        XCTAssertEqual(ChordSpeed.deliberate.milliseconds, 600)
    }

    func testChordSpeedNearest() {
        XCTAssertEqual(ChordSpeed.nearest(to: 140), .lightning)
        XCTAssertEqual(ChordSpeed.nearest(to: 200), .lightning) // Tie, picks first (lightning)
        XCTAssertEqual(ChordSpeed.nearest(to: 250), .fast)
        XCTAssertEqual(ChordSpeed.nearest(to: 325), .fast) // Tie, picks first (fast)
        XCTAssertEqual(ChordSpeed.nearest(to: 500), .moderate) // Tie, picks first (moderate)
        XCTAssertEqual(ChordSpeed.nearest(to: 600), .deliberate)
        XCTAssertEqual(ChordSpeed.nearest(to: 700), .deliberate)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = ChordGroupsConfig.benVallackPreset
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChordGroupsConfig.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testChordGroupCodable() throws {
        let original = ChordGroup(
            id: UUID(),
            name: "Test",
            timeout: 300,
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc", description: "Quick escape")
            ],
            description: "Test group",
            category: .navigation
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChordGroup.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testChordDefinitionCodable() throws {
        let original = ChordDefinition(
            id: UUID(),
            keys: ["s", "d"],
            output: "esc",
            description: "Quick escape"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChordDefinition.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Ergonomic Score

    func testErgonomicScoreColor() {
        XCTAssertEqual(ErgonomicScore.excellent.color, "green")
        XCTAssertEqual(ErgonomicScore.good.color, "blue")
        XCTAssertEqual(ErgonomicScore.moderate.color, "yellow")
        XCTAssertEqual(ErgonomicScore.fair.color, "orange")
        XCTAssertEqual(ErgonomicScore.poor.color, "red")
    }

    func testErgonomicScoreIcon() {
        XCTAssertEqual(ErgonomicScore.excellent.icon, "hand.thumbsup.fill")
        XCTAssertEqual(ErgonomicScore.good.icon, "hand.thumbsup")
        XCTAssertEqual(ErgonomicScore.moderate.icon, "hand.raised")
        XCTAssertEqual(ErgonomicScore.fair.icon, "exclamationmark.triangle")
        XCTAssertEqual(ErgonomicScore.poor.icon, "xmark.circle")
    }

    // MARK: - Chord Conflict

    func testChordConflictDescription() {
        let chord1 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc")
        let chord2 = ChordDefinition(id: UUID(), keys: ["s", "d"], output: "enter")

        let conflict = ChordConflict(chord1: chord1, chord2: chord2, type: .sameKeys)

        XCTAssertTrue(conflict.description.contains("s+d"))
        XCTAssertTrue(conflict.description.contains("esc"))
        XCTAssertTrue(conflict.description.contains("enter"))
    }
}
