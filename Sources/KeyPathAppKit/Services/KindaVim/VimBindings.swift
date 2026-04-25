// Static reference table for the Vim commands kindaVim implements,
// classified by tier (core / secondary / advanced), grouped by purpose,
// and tagged with the strategies that actually support them. Single
// source of truth for both the live keyboard overlay hints and the
// ContextHUD list popup — the two surfaces share the data and apply
// their own visual treatment on top.
//
// Sources:
// - https://docs.kindavim.app/implementation/accessibility-strategy
// - https://docs.kindavim.app/implementation/keyboard-strategy
// - kindaVim app docs and changelog

import Foundation

/// One Vim command, with enough metadata to render it in either the
/// overlay (per-key) or the HUD list (grouped).
struct VimHint: Identifiable, Equatable, Sendable {
    var id: String { key + "|" + displayLabel }

    /// Physical key, lowercase, in kanata convention (e.g. "h", "0", "/").
    /// Multi-key sequences like `gg` use the leading key (the second is
    /// inferred from the sequence observer).
    let key: String

    /// Short label shown on the keycap or in the cheat-sheet column
    /// ("←", "w", "gg", etc.).
    let displayLabel: String

    /// Longer description for the action column in list view ("left",
    /// "word forward", "doc top").
    let actionLabel: String

    /// Visual emphasis tier — drives opacity/size in both surfaces.
    let tier: Tier

    /// Grouping for the HUD list. The overlay ignores groups and sorts
    /// by physical position.
    let group: Group

    /// Strategies that wire this command up. The Accessibility strategy
    /// is a superset; Keyboard fallback omits gg/G/visual/text-objects.
    let strategies: Set<KindaVimStrategy>

    /// Modes in which this hint should be surfaced.
    let modes: Set<KindaVimStateAdapter.Mode>

    enum Tier: Int, Comparable, Sendable {
        case core = 0
        case secondary = 1
        case advanced = 2

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Group: Int, CaseIterable, Sendable {
        case movement
        case wordMotion
        case lineMotion
        case enterInsert
        case edit
        case operators
        case findChar
        case doc
        case page
        case match
        case search

        var displayName: String {
            switch self {
            case .movement: "Move"
            case .wordMotion: "Jump words"
            case .lineMotion: "Jump line"
            case .enterInsert: "Enter Insert"
            case .edit: "Edit"
            case .operators: "Operators"
            case .findChar: "Find char"
            case .doc: "Top / Bottom"
            case .page: "Page"
            case .match: "Match"
            case .search: "Search"
            }
        }

        var sortOrder: Int { rawValue }
    }
}

struct VimHintGroup: Equatable, Sendable {
    let group: VimHint.Group
    let entries: [VimHint]

    var displayName: String { group.displayName }
}

enum VimBindings {
    /// All commands kindaVim is documented to support. Accessibility
    /// strategy unless otherwise noted on individual entries. Order
    /// within each group is the order we want them to appear in lists.
    static let all: [VimHint] = [
        // MARK: Movement (core, hjkl)
        .init(key: "h", displayLabel: "←", actionLabel: "left",
              tier: .core, group: .movement,
              strategies: allStrategies, modes: motionModes),
        .init(key: "j", displayLabel: "↓", actionLabel: "down",
              tier: .core, group: .movement,
              strategies: allStrategies, modes: motionModes),
        .init(key: "k", displayLabel: "↑", actionLabel: "up",
              tier: .core, group: .movement,
              strategies: allStrategies, modes: motionModes),
        .init(key: "l", displayLabel: "→", actionLabel: "right",
              tier: .core, group: .movement,
              strategies: allStrategies, modes: motionModes),

        // MARK: Word motion (core)
        .init(key: "w", displayLabel: "w", actionLabel: "word forward",
              tier: .core, group: .wordMotion,
              strategies: allStrategies, modes: motionModes),
        .init(key: "b", displayLabel: "b", actionLabel: "word back",
              tier: .core, group: .wordMotion,
              strategies: allStrategies, modes: motionModes),
        .init(key: "e", displayLabel: "e", actionLabel: "end of word",
              tier: .core, group: .wordMotion,
              strategies: allStrategies, modes: motionModes),

        // MARK: Line motion (core)
        .init(key: "0", displayLabel: "0", actionLabel: "line start",
              tier: .core, group: .lineMotion,
              strategies: allStrategies, modes: motionModes),
        .init(key: "$", displayLabel: "$", actionLabel: "line end",
              tier: .core, group: .lineMotion,
              strategies: allStrategies, modes: motionModes),

        // MARK: Enter Insert (core: i/a/o; secondary: capitals)
        .init(key: "i", displayLabel: "i", actionLabel: "insert before cursor",
              tier: .core, group: .enterInsert,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "a", displayLabel: "a", actionLabel: "append after cursor",
              tier: .core, group: .enterInsert,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "o", displayLabel: "o", actionLabel: "open line below",
              tier: .core, group: .enterInsert,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "I", displayLabel: "I", actionLabel: "insert at line start",
              tier: .secondary, group: .enterInsert,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "A", displayLabel: "A", actionLabel: "append at line end",
              tier: .secondary, group: .enterInsert,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "O", displayLabel: "O", actionLabel: "open line above",
              tier: .secondary, group: .enterInsert,
              strategies: allStrategies, modes: [.normal, .visual]),

        // MARK: Edit (core: x; secondary: r/u/redo)
        .init(key: "x", displayLabel: "x", actionLabel: "delete char",
              tier: .core, group: .edit,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "r", displayLabel: "r", actionLabel: "replace char",
              tier: .secondary, group: .edit,
              strategies: allStrategies, modes: [.normal]),
        .init(key: "u", displayLabel: "u", actionLabel: "undo",
              tier: .secondary, group: .edit,
              strategies: allStrategies, modes: [.normal]),
        .init(key: "ctrl-r", displayLabel: "⌃R", actionLabel: "redo",
              tier: .secondary, group: .edit,
              strategies: allStrategies, modes: [.normal]),

        // MARK: Operators (secondary). In op-pending we still surface
        // these so the user can see "press the same one twice = whole line".
        .init(key: "d", displayLabel: "d", actionLabel: "delete (motion / dd line)",
              tier: .secondary, group: .operators,
              strategies: allStrategies, modes: [.normal, .visual, .operatorPending]),
        .init(key: "c", displayLabel: "c", actionLabel: "change (motion / cc line)",
              tier: .secondary, group: .operators,
              strategies: allStrategies, modes: [.normal, .visual, .operatorPending]),
        .init(key: "y", displayLabel: "y", actionLabel: "yank (motion / yy line)",
              tier: .secondary, group: .operators,
              strategies: allStrategies, modes: [.normal, .visual, .operatorPending]),

        // MARK: Find char (secondary)
        .init(key: "f", displayLabel: "f", actionLabel: "find char forward",
              tier: .secondary, group: .findChar,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "F", displayLabel: "F", actionLabel: "find char backward",
              tier: .secondary, group: .findChar,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "t", displayLabel: "t", actionLabel: "to char forward",
              tier: .secondary, group: .findChar,
              strategies: allStrategies, modes: [.normal, .visual]),
        .init(key: "T", displayLabel: "T", actionLabel: "to char backward",
              tier: .secondary, group: .findChar,
              strategies: allStrategies, modes: [.normal, .visual]),

        // MARK: Top / Bottom (secondary; Accessibility-only)
        .init(key: "g", displayLabel: "gg", actionLabel: "doc top",
              tier: .secondary, group: .doc,
              strategies: [.accessibility, .hybrid], modes: motionModes),
        .init(key: "G", displayLabel: "G", actionLabel: "doc bottom",
              tier: .secondary, group: .doc,
              strategies: [.accessibility, .hybrid], modes: motionModes),

        // MARK: Page (advanced — only shown with "Show all" toggle)
        .init(key: "ctrl-d", displayLabel: "⌃D", actionLabel: "half page down",
              tier: .advanced, group: .page,
              strategies: [.accessibility, .hybrid], modes: motionModes),
        .init(key: "ctrl-u", displayLabel: "⌃U", actionLabel: "half page up",
              tier: .advanced, group: .page,
              strategies: [.accessibility, .hybrid], modes: motionModes),
        .init(key: "ctrl-f", displayLabel: "⌃F", actionLabel: "page down",
              tier: .advanced, group: .page,
              strategies: [.accessibility, .hybrid], modes: motionModes),
        .init(key: "ctrl-b", displayLabel: "⌃B", actionLabel: "page up",
              tier: .advanced, group: .page,
              strategies: [.accessibility, .hybrid], modes: motionModes),

        // MARK: Match (advanced, Accessibility-only)
        .init(key: "%", displayLabel: "%", actionLabel: "match bracket",
              tier: .advanced, group: .match,
              strategies: [.accessibility, .hybrid], modes: motionModes),

        // MARK: Search (advanced)
        .init(key: "/", displayLabel: "/", actionLabel: "search forward",
              tier: .advanced, group: .search,
              strategies: [.accessibility, .hybrid], modes: [.normal, .visual]),
        .init(key: "?", displayLabel: "?", actionLabel: "search backward",
              tier: .advanced, group: .search,
              strategies: [.accessibility, .hybrid], modes: [.normal, .visual]),
        .init(key: "n", displayLabel: "n", actionLabel: "next match",
              tier: .advanced, group: .search,
              strategies: [.accessibility, .hybrid], modes: motionModes),
        .init(key: "N", displayLabel: "N", actionLabel: "previous match",
              tier: .advanced, group: .search,
              strategies: [.accessibility, .hybrid], modes: motionModes),
    ]

    /// Filter the table for the current strategy / mode / advanced flag.
    /// Operator-pending mode shrinks the result to motion + operators (so
    /// the same-operator "× 2 = line" hint can render).
    static func hints(
        strategy: KindaVimStrategy,
        mode: KindaVimStateAdapter.Mode,
        showAdvanced: Bool
    ) -> [VimHint] {
        guard strategy != .ignored, mode != .insert, mode != .unknown else { return [] }

        return all.filter { hint in
            guard hint.strategies.contains(strategy) else { return false }
            guard hint.modes.contains(mode) else { return false }
            if hint.tier == .advanced, !showAdvanced { return false }

            if mode == .operatorPending {
                // In op-pending we only want motion targets and the
                // operator-doubled-up hint. Drop everything else.
                let keepGroups: Set<VimHint.Group> = [
                    .movement, .wordMotion, .lineMotion, .findChar, .doc, .operators,
                ]
                return keepGroups.contains(hint.group)
            }
            return true
        }
    }

    /// Same data as `hints(...)` but bucketed for the HUD list. Empty
    /// groups are omitted so the popup doesn't render dead headers.
    static func grouped(
        strategy: KindaVimStrategy,
        mode: KindaVimStateAdapter.Mode,
        showAdvanced: Bool
    ) -> [VimHintGroup] {
        let filtered = hints(strategy: strategy, mode: mode, showAdvanced: showAdvanced)
        let bucketed = Dictionary(grouping: filtered, by: \.group)
        return VimHint.Group.allCases.compactMap { group in
            guard let entries = bucketed[group], !entries.isEmpty else { return nil }
            return VimHintGroup(group: group, entries: entries)
        }
    }

    // MARK: - Convenience constants

    private static let allStrategies: Set<KindaVimStrategy> = [.accessibility, .keyboard, .hybrid]
    private static let motionModes: Set<KindaVimStateAdapter.Mode> = [.normal, .visual, .operatorPending]
}
