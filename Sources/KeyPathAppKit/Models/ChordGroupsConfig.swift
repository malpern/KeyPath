import Foundation

/// Configuration for Kanata chord groups (defchords).
/// Enables Ben Vallack-style multi-key combinations for efficient keyboard shortcuts.
public struct ChordGroupsConfig: Codable, Equatable, Sendable {
    public var groups: [ChordGroup]
    public var activeGroupID: UUID?
    public var showAdvanced: Bool

    public init(
        groups: [ChordGroup] = [],
        activeGroupID: UUID? = nil,
        showAdvanced: Bool = false
    ) {
        self.groups = groups
        self.activeGroupID = activeGroupID
        self.showAdvanced = showAdvanced
    }

    /// Detect conflicts across multiple chord groups.
    ///
    /// A conflict occurs when two or more groups use the same key in their chords.
    /// In generated Kanata config, the first group will control that key.
    ///
    /// - Returns: Array of conflicts, one per conflicting key
    ///
    /// Example:
    /// ```swift
    /// let conflicts = config.detectCrossGroupConflicts()
    /// for conflict in conflicts {
    ///     print("Key '\(conflict.key)' used by: \(conflict.groups.map(\.name))")
    ///     // Resolve by using different keys or merging groups
    /// }
    /// ```
    public func detectCrossGroupConflicts() -> [CrossGroupConflict] {
        var conflicts: [CrossGroupConflict] = []

        // Build map of key → groups using that key
        var keyToGroups: [String: [ChordGroup]] = [:]
        for group in groups {
            for key in group.participatingKeys {
                keyToGroups[key, default: []].append(group)
            }
        }

        // Find keys used by multiple groups
        for (key, groupsUsingKey) in keyToGroups where groupsUsingKey.count > 1 {
            conflicts.append(CrossGroupConflict(
                key: key,
                groups: groupsUsingKey
            ))
        }

        return conflicts
    }

    /// Whether this config has any cross-group conflicts.
    /// Note: Recomputes on every call (O(n×m) where n=groups, m=keys).
    /// Cache the result if calling frequently in UI render loops.
    public var hasCrossGroupConflicts: Bool {
        !detectCrossGroupConflicts().isEmpty
    }

    /// Get groups that conflict with a specific group.
    /// Returns groups that share keys with the specified group.
    public func conflictingGroups(for groupID: UUID) -> [ChordGroup] {
        guard let targetGroup = groups.first(where: { $0.id == groupID }) else { return [] }
        let targetKeys = targetGroup.participatingKeys

        return groups.filter { group in
            group.id != groupID && !group.participatingKeys.isDisjoint(with: targetKeys)
        }
    }

    /// Get keys that cause conflicts for a specific group.
    /// Returns keys that are shared with other groups.
    public func conflictingKeys(for groupID: UUID) -> Set<String> {
        guard groups.contains(where: { $0.id == groupID }) else { return [] }
        let conflicts = detectCrossGroupConflicts()

        return Set(conflicts.compactMap { conflict -> String? in
            if conflict.groups.contains(where: { $0.id == groupID }) {
                return conflict.key
            }
            return nil
        })
    }

    /// Check if adding a chord to a group would create cross-group conflicts.
    /// Returns true if the chord's keys are already used by other groups.
    public func wouldCreateConflict(chord: ChordDefinition, in groupID: UUID) -> Bool {
        let chordKeys = Set(chord.keys)

        for group in groups where group.id != groupID {
            if !group.participatingKeys.isDisjoint(with: chordKeys) {
                return true
            }
        }

        return false
    }

    /// Ben Vallack's navigation chord preset.
    /// Home row centric chords for efficient text navigation.
    /// Uses stable UUIDs for equality checks across instances.
    public static var benVallackPreset: ChordGroupsConfig {
        // Stable UUIDs for groups
        let navGroupID = UUID(uuidString: "BA000000-0000-0000-0000-000000000001")!
        let editGroupID = UUID(uuidString: "BA000000-0000-0000-0000-000000000002")!

        let navigationGroup = ChordGroup(
            id: navGroupID,
            name: "Navigation",
            timeout: 250, // Fast - for experienced users
            chords: [
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0001-000000000001")!, keys: ["s", "d"], output: "esc", description: "Quick escape from modes"),
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0001-000000000002")!, keys: ["d", "f"], output: "enter", description: "Submit/confirm action"),
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0001-000000000003")!, keys: ["j", "k"], output: "up", description: "Move up one line"),
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0001-000000000004")!, keys: ["k", "l"], output: "down", description: "Move down one line")
            ],
            description: "Ben Vallack's home row navigation chords",
            category: .navigation
        )

        let editingGroup = ChordGroup(
            id: editGroupID,
            name: "Editing",
            timeout: 400, // Moderate - aligns with editing category
            chords: [
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0002-000000000001")!, keys: ["a", "s"], output: "bspc", description: "Backspace - delete previous character"),
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0002-000000000002")!, keys: ["s", "d", "f"], output: "C-x", description: "Cut selection"),
                ChordDefinition(id: UUID(uuidString: "BA000000-0000-0000-0002-000000000003")!, keys: ["e", "r"], output: "C-z", description: "Undo last action")
            ],
            description: "Common editing operations",
            category: .editing
        )

        return ChordGroupsConfig(
            groups: [navigationGroup, editingGroup],
            activeGroupID: navGroupID,
            showAdvanced: false
        )
    }
}

/// A single chord group with a shared timeout.
public struct ChordGroup: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var timeout: Int // milliseconds
    public var chords: [ChordDefinition]
    public var description: String?
    public var category: ChordCategory

    public init(
        id: UUID,
        name: String,
        timeout: Int,
        chords: [ChordDefinition] = [],
        description: String? = nil,
        category: ChordCategory = .custom
    ) {
        // Validation for group name (Kanata syntax requirements)
        precondition(!name.isEmpty, "ChordGroup name cannot be empty")
        precondition(!name.contains(" "), "ChordGroup name cannot contain spaces (use hyphens or underscores)")
        precondition(
            name.allSatisfy { ($0.isASCII && $0.isLetter) || $0.isNumber || $0 == "-" || $0 == "_" },
            "ChordGroup name must be ASCII alphanumeric with optional hyphens or underscores"
        )

        // Validation for timeout (reasonable range)
        // Upper bound prevents unreasonably long timeouts that defeat the purpose of chords
        precondition(timeout >= 50 && timeout <= 5000, "Timeout must be between 50-5000ms (reasonable range for chord detection)")

        self.id = id
        self.name = name
        self.timeout = timeout
        self.chords = chords
        self.description = description
        self.category = category
    }

    /// All keys that participate in this chord group.
    public var participatingKeys: Set<String> {
        Set(chords.flatMap(\.keys))
    }

    /// Whether this group has no conflicts.
    public var isValid: Bool {
        detectConflicts().isEmpty
    }

    /// Detect any conflicting chord definitions within this group.
    /// Complexity: O(n²) where n = number of chords. Acceptable for typical groups (< 50 chords).
    /// Optimize with HashMap if group exceeds 100 chords.
    public func detectConflicts() -> [ChordConflict] {
        var conflicts: [ChordConflict] = []

        for i in 0 ..< chords.count {
            for j in (i + 1) ..< chords.count {
                let chord1 = chords[i]
                let chord2 = chords[j]

                let keys1Set = Set(chord1.keys)
                let keys2Set = Set(chord2.keys)

                // Exact same keys with different outputs = conflict
                if keys1Set == keys2Set {
                    conflicts.append(ChordConflict(
                        chord1: chord1,
                        chord2: chord2,
                        type: .sameKeys
                    ))
                }
                // Overlapping keys (subset/superset) = potential conflict
                // Only flag if both are actual chords (2+ keys), not single-key fallbacks
                else if keys1Set.isSubset(of: keys2Set) || keys2Set.isSubset(of: keys1Set) {
                    if chord1.isRecommendedCombo, chord2.isRecommendedCombo {
                        conflicts.append(ChordConflict(
                            chord1: chord1,
                            chord2: chord2,
                            type: .overlapping
                        ))
                    }
                }
            }
        }

        return conflicts
    }
}

/// A single chord definition (key combination → output).
public struct ChordDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var keys: [String]
    public var output: String
    public var description: String?

    public init(
        id: UUID,
        keys: [String],
        output: String,
        description: String? = nil
    ) {
        // Validation for keys
        precondition(!keys.isEmpty, "ChordDefinition must have at least one key")
        precondition(keys.allSatisfy { !$0.isEmpty }, "ChordDefinition keys cannot be empty strings")
        precondition(Set(keys).count == keys.count, "ChordDefinition keys must be unique")

        // Validation for output
        precondition(!output.isEmpty, "ChordDefinition output cannot be empty")

        self.id = id
        self.keys = keys
        self.output = output
        self.description = description
    }

    /// Whether this is a recommended chord combo (2-4 keys).
    /// Single keys are valid but defeat the purpose of chords.
    /// More than 4 keys becomes difficult to press simultaneously.
    public var isRecommendedCombo: Bool {
        keys.count >= 2 && keys.count <= 4
    }

    /// Check if output has basic syntax issues (unbalanced parentheses).
    ///
    /// Validates that the output string has balanced parentheses, catching common
    /// Kanata syntax errors like `"(macro a"` or `")esc"`.
    ///
    /// Note: This only checks parenthesis balance, not full Kanata syntax validity.
    /// Invalid Kanata keywords will still pass this check.
    ///
    /// - Returns: true if parentheses are balanced, false otherwise
    ///
    /// Examples:
    /// ```swift
    /// ChordDefinition(output: "esc").hasValidOutputSyntax // true
    /// ChordDefinition(output: "(macro a b)").hasValidOutputSyntax // true
    /// ChordDefinition(output: "(macro a").hasValidOutputSyntax // false (unbalanced)
    /// ChordDefinition(output: "esc)").hasValidOutputSyntax // false (extra closing)
    /// ```
    public var hasValidOutputSyntax: Bool {
        hasBalancedParentheses(output)
    }

    private func hasBalancedParentheses(_ string: String) -> Bool {
        var depth = 0
        for char in string {
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth < 0 {
                    return false // More closing than opening
                }
            }
        }
        return depth == 0 // Should end balanced
    }

    /// Ergonomic assessment of key combination (assumes QWERTY layout).
    /// Evaluates how easy the chord is to press based on hand position and key adjacency.
    public var ergonomicScore: ErgonomicScore {
        guard keys.count >= 2 else { return .poor }

        let homeRow = Set(["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"])
        let leftHand = Set(["q", "w", "e", "r", "t", "a", "s", "d", "f", "g", "z", "x", "c", "v", "b"])
        let rightHand = Set(["y", "u", "i", "o", "p", "h", "j", "k", "l", ";", "n", "m"])

        let keySet = Set(keys)
        let allHomeRow = keySet.isSubset(of: homeRow)
        let sameHand = keySet.isSubset(of: leftHand) || keySet.isSubset(of: rightHand)

        // Adjacent keys on home row = best
        if allHomeRow, areAdjacent(keys) {
            return .excellent
        }

        // Same hand, home row = good
        if allHomeRow, sameHand {
            return .good
        }

        // Same hand but not home row = moderate
        if sameHand {
            return .moderate
        }

        // Cross-hand = less ergonomic but still valid
        return .fair
    }

    private func areAdjacent(_ keys: [String]) -> Bool {
        // Guard against edge cases
        guard !keys.isEmpty else { return false }
        guard keys.count >= 2 else { return false }

        let homeRowOrder = ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
        let positions = keys.compactMap { homeRowOrder.firstIndex(of: $0) }
        guard positions.count == keys.count else { return false }

        let sorted = positions.sorted()
        for i in 0 ..< (sorted.count - 1) where sorted[i + 1] - sorted[i] > 1 {
            return false
        }
        return true
    }
}

/// Ergonomic assessment of a chord combination.
public enum ErgonomicScore: String, Codable, Sendable {
    case excellent = "Excellent" // Adjacent home row keys
    case good = "Good" // Same hand, home row
    case moderate = "Moderate" // Same hand, not home row
    case fair = "Fair" // Cross-hand
    case poor = "Poor" // Single key or awkward combo

    public var color: String {
        switch self {
        case .excellent: "green"
        case .good: "blue"
        case .moderate: "yellow"
        case .fair: "orange"
        case .poor: "red"
        }
    }

    public var icon: String {
        switch self {
        case .excellent: "hand.thumbsup.fill"
        case .good: "hand.thumbsup"
        case .moderate: "hand.raised"
        case .fair: "exclamationmark.triangle"
        case .poor: "xmark.circle"
        }
    }
}

/// Category of chord group for organization and defaults.
public enum ChordCategory: String, Codable, Sendable, CaseIterable {
    case navigation
    case editing
    case symbols
    case modifiers
    case custom

    public var displayName: String {
        switch self {
        case .navigation: "Navigation"
        case .editing: "Editing"
        case .symbols: "Symbols"
        case .modifiers: "Modifiers"
        case .custom: "Custom"
        }
    }

    public var icon: String {
        switch self {
        case .navigation: "arrow.up.arrow.down"
        case .editing: "scissors"
        case .symbols: "textformat.abc"
        case .modifiers: "command"
        case .custom: "star"
        }
    }

    /// Suggested timeout for this category (in milliseconds).
    /// Aligned with ChordSpeed presets for consistent UI experience.
    public var suggestedTimeout: Int {
        switch self {
        case .navigation: 250 // Fast navigation (ChordSpeed.fast)
        case .editing: 400 // Moderate editing (ChordSpeed.moderate)
        case .symbols: 150 // Quick symbols (ChordSpeed.lightning)
        case .modifiers: 600 // Deliberate modifiers (ChordSpeed.deliberate)
        case .custom: 400 // Default moderate (ChordSpeed.moderate)
        }
    }
}

/// Preset timeout speeds with descriptions.
public enum ChordSpeed: String, CaseIterable, Codable, Sendable {
    case lightning = "Lightning Fast"
    case fast = "Fast"
    case moderate = "Moderate"
    case deliberate = "Deliberate"

    public var milliseconds: Int {
        switch self {
        case .lightning: 150
        case .fast: 250
        case .moderate: 400
        case .deliberate: 600
        }
    }

    public var description: String {
        switch self {
        case .lightning:
            "For experts (150ms) - requires precise timing"
        case .fast:
            "For experienced users (250ms) - Ben Vallack's preferred speed"
        case .moderate:
            "Balanced (400ms) - good for learning"
        case .deliberate:
            "Relaxed (600ms) - easiest to trigger reliably"
        }
    }

    /// Find the speed preset closest to a given timeout value.
    /// In case of ties (equidistant from two presets), returns the first matching preset (faster one).
    /// For example: nearest(to: 200) returns .lightning (150ms) rather than .fast (250ms).
    public static func nearest(to timeout: Int) -> ChordSpeed {
        ChordSpeed.allCases.min(by: { abs($0.milliseconds - timeout) < abs($1.milliseconds - timeout) }) ?? .moderate
    }
}

/// Conflict between two chord definitions within a single group.
public struct ChordConflict: Identifiable, Sendable {
    public let id = UUID()
    public let chord1: ChordDefinition
    public let chord2: ChordDefinition
    public let type: ConflictType

    public init(chord1: ChordDefinition, chord2: ChordDefinition, type: ConflictType) {
        self.chord1 = chord1
        self.chord2 = chord2
        self.type = type
    }

    public enum ConflictType: Sendable {
        case sameKeys // Exact same keys, different outputs
        case overlapping // Overlapping key sets
        case timeout // Same keys, timing conflict (future enhancement)
    }

    public var description: String {
        let keys1 = chord1.keys.joined(separator: "+")
        let keys2 = chord2.keys.joined(separator: "+")

        switch type {
        case .sameKeys:
            return "\(keys1) maps to both '\(chord1.output)' and '\(chord2.output)'"
        case .overlapping:
            return "\(keys1) overlaps with \(keys2)"
        case .timeout:
            return "Timing conflict between \(keys1) and \(keys2)"
        }
    }
}

/// Conflict across multiple chord groups (key used by multiple groups).
public struct CrossGroupConflict: Identifiable, Sendable {
    public let id = UUID()
    public let key: String
    public let groups: [ChordGroup]

    public init(key: String, groups: [ChordGroup]) {
        self.key = key
        self.groups = groups
    }

    public var description: String {
        let groupNames = groups.map(\.name).joined(separator: ", ")
        return "Key '\(key)' is used by multiple groups: \(groupNames). First group in list will win."
    }

    /// Suggested resolution: which group should own this key?
    public var suggestion: String {
        "Consider using different keys for each group, or merge groups if they serve similar purposes."
    }
}
