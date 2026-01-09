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

    /// Ben Vallack's navigation chord preset.
    /// Home row centric chords for efficient text navigation.
    public static var benVallackPreset: ChordGroupsConfig {
        let navigationGroup = ChordGroup(
            id: UUID(),
            name: "Navigation",
            timeout: 250, // Fast - for experienced users
            chords: [
                ChordDefinition(id: UUID(), keys: ["s", "d"], output: "esc", description: "Quick escape from modes"),
                ChordDefinition(id: UUID(), keys: ["d", "f"], output: "enter", description: "Submit/confirm action"),
                ChordDefinition(id: UUID(), keys: ["j", "k"], output: "up", description: "Move up one line"),
                ChordDefinition(id: UUID(), keys: ["k", "l"], output: "down", description: "Move down one line")
            ],
            description: "Ben Vallack's home row navigation chords",
            category: .navigation
        )

        let editingGroup = ChordGroup(
            id: UUID(),
            name: "Editing",
            timeout: 300, // Moderate - slightly more deliberate
            chords: [
                ChordDefinition(id: UUID(), keys: ["a", "s"], output: "bspc", description: "Backspace - delete previous character"),
                ChordDefinition(id: UUID(), keys: ["s", "d", "f"], output: "C-x", description: "Cut selection"),
                ChordDefinition(id: UUID(), keys: ["e", "r"], output: "C-z", description: "Undo last action")
            ],
            description: "Common editing operations",
            category: .editing
        )

        return ChordGroupsConfig(
            groups: [navigationGroup, editingGroup],
            activeGroupID: navigationGroup.id,
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
            name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" },
            "ChordGroup name must be alphanumeric with optional hyphens or underscores"
        )

        // Validation for timeout (reasonable range)
        precondition(timeout >= 50 && timeout <= 5000, "Timeout must be between 50-5000ms")

        self.id = id
        self.name = name
        self.timeout = timeout
        self.chords = chords
        self.description = description
        self.category = category
    }

    /// All keys that participate in this chord group.
    public var participatingKeys: Set<String> {
        Set(chords.flatMap { $0.keys })
    }

    /// Whether this group has no conflicts.
    public var isValid: Bool {
        detectConflicts().isEmpty
    }

    /// Detect any conflicting chord definitions within this group.
    public func detectConflicts() -> [ChordConflict] {
        var conflicts: [ChordConflict] = []

        for i in 0..<chords.count {
            for j in (i+1)..<chords.count {
                let chord1 = chords[i]
                let chord2 = chords[j]

                // Exact same keys with different outputs = conflict
                if Set(chord1.keys) == Set(chord2.keys) {
                    conflicts.append(ChordConflict(
                        chord1: chord1,
                        chord2: chord2,
                        type: .sameKeys
                    ))
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

    /// Whether this is a valid chord combo (2-3 keys recommended).
    public var isValidCombo: Bool {
        keys.count >= 2 && keys.count <= 4
    }

    /// Ergonomic assessment of key combination.
    public var ergonomicScore: ErgonomicScore {
        guard keys.count >= 2 else { return .poor }

        let homeRow = Set(["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"])
        let leftHand = Set(["q", "w", "e", "r", "t", "a", "s", "d", "f", "g", "z", "x", "c", "v", "b"])
        let rightHand = Set(["y", "u", "i", "o", "p", "h", "j", "k", "l", ";", "n", "m"])

        let keySet = Set(keys)
        let allHomeRow = keySet.isSubset(of: homeRow)
        let sameHand = keySet.isSubset(of: leftHand) || keySet.isSubset(of: rightHand)

        // Adjacent keys on home row = best
        if allHomeRow && areAdjacent(keys) {
            return .excellent
        }

        // Same hand, home row = good
        if allHomeRow && sameHand {
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
        for i in 0..<(sorted.count - 1) {
            if sorted[i+1] - sorted[i] > 1 {
                return false
            }
        }
        return true
    }
}

/// Ergonomic assessment of a chord combination.
public enum ErgonomicScore: String, Codable, Sendable {
    case excellent = "Excellent" // Adjacent home row keys
    case good = "Good"           // Same hand, home row
    case moderate = "Moderate"   // Same hand, not home row
    case fair = "Fair"           // Cross-hand
    case poor = "Poor"           // Single key or awkward combo

    public var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .moderate: return "yellow"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }

    public var icon: String {
        switch self {
        case .excellent: return "hand.thumbsup.fill"
        case .good: return "hand.thumbsup"
        case .moderate: return "hand.raised"
        case .fair: return "exclamationmark.triangle"
        case .poor: return "xmark.circle"
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
        case .navigation: return "Navigation"
        case .editing: return "Editing"
        case .symbols: return "Symbols"
        case .modifiers: return "Modifiers"
        case .custom: return "Custom"
        }
    }

    public var icon: String {
        switch self {
        case .navigation: return "arrow.up.arrow.down"
        case .editing: return "scissors"
        case .symbols: return "textformat.abc"
        case .modifiers: return "command"
        case .custom: return "star"
        }
    }

    /// Suggested timeout for this category (in milliseconds).
    public var suggestedTimeout: Int {
        switch self {
        case .navigation: return 250 // Fast navigation
        case .editing: return 300    // Moderate editing
        case .symbols: return 200    // Quick symbols
        case .modifiers: return 400  // Deliberate modifiers
        case .custom: return 300     // Default moderate
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
        case .lightning: return 150
        case .fast: return 250
        case .moderate: return 400
        case .deliberate: return 600
        }
    }

    public var description: String {
        switch self {
        case .lightning:
            return "For experts (150ms) - requires precise timing"
        case .fast:
            return "For experienced users (250ms) - Ben Vallack's preferred speed"
        case .moderate:
            return "Balanced (400ms) - good for learning"
        case .deliberate:
            return "Relaxed (600ms) - easiest to trigger reliably"
        }
    }

    /// Find the speed preset closest to a given timeout value.
    public static func nearest(to timeout: Int) -> ChordSpeed {
        ChordSpeed.allCases.min(by: { abs($0.milliseconds - timeout) < abs($1.milliseconds - timeout) }) ?? .moderate
    }
}

/// Conflict between two chord definitions.
public struct ChordConflict: Identifiable, Sendable {
    public let id = UUID()
    public let chord1: ChordDefinition
    public let chord2: ChordDefinition
    public let type: ConflictType

    public enum ConflictType: Sendable {
        case sameKeys      // Exact same keys, different outputs
        case overlapping   // Overlapping key sets (future enhancement)
        case timeout       // Same keys, timing conflict (future enhancement)
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
