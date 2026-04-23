// M1 Gallery MVP — the hardcoded Starter Kit.
// See docs/design/sprint-1/starter-kit.md

import Foundation

/// Provides access to the M1 Starter Kit packs. Hardcoded in Swift; v2+ may
/// load from JSON or a manifest bundle.
public enum PackRegistry {
    /// All packs shipping in M1. Order matters — this is the display order in
    /// the Gallery view.
    public static let starterKit: [Pack] = [
        capsLockToEscape,
        homeRowMods,
        escapeRemap,
        deleteEnhancement,
        backupCapsLock,
        vimNavigation,
        windowSnapping,
        missionControl
    ]

    /// Look up a pack by id. Returns nil if unknown.
    public static func pack(id: String) -> Pack? {
        starterKit.first(where: { $0.id == id })
    }

    /// Packs whose bindings target the given kanata key identifier (e.g.
    /// "caps", "d", "rmet"). Used by the Mapper inspector to surface
    /// contextual pack suggestions when the user selects an input.
    ///
    /// Normalizes common aliases (e.g. the overlay sends "capslock" while
    /// pack manifests use "caps"; "leftmeta" vs "lmet"; etc) so lookups
    /// succeed regardless of which spelling flavor the caller uses.
    public static func packsTargeting(kanataKey: String) -> [Pack] {
        let normalized = normalizeKanataKey(kanataKey)
        guard !normalized.isEmpty else { return [] }
        return starterKit.filter { pack in
            pack.affectedKeys.contains(where: { normalizeKanataKey($0) == normalized })
        }
    }

    /// Collapse the handful of long-form / short-form aliases used by
    /// different layers (overlay keymap, Kanata config, pack manifests)
    /// into a single canonical token.
    private static func normalizeKanataKey(_ key: String) -> String {
        let lower = key.lowercased()
        switch lower {
        case "capslock": return "caps"
        case "leftmeta": return "lmet"
        case "rightmeta": return "rmet"
        case "leftshift": return "lsft"
        case "rightshift": return "rsft"
        case "leftalt": return "lalt"
        case "rightalt": return "ralt"
        case "leftctrl": return "lctl"
        case "rightctrl": return "rctl"
        default: return lower
        }
    }

    // MARK: - Pack 1: Caps Lock → Escape

    public static let capsLockToEscape = Pack(
        id: "com.keypath.pack.caps-lock-to-escape",
        version: "1.0.0",
        name: "Caps Lock Remap",
        tagline: "Make Caps Lock actually useful with tap and hold actions",
        shortDescription:
            "Caps Lock is prime real estate in the corner — almost nobody uses it. Put it to work: tap it for a quick action like Escape, hold it for Hyper (⌃⌥⇧⌘), a modifier no app collides with. Pick your tap and hold below.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "capslock",
        iconSecondarySymbol: "escape",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(
                input: "caps",
                output: "esc",
                title: "Caps Lock → Escape"
            )
        ],
        associatedCollectionID: RuleCollectionIdentifier.capsLockRemap
    )

    // MARK: - Pack 2: Home Row Mods

    /// Mirrors the Rules tab's "Home Row Mods" collection: name, summary,
    /// and default seed bindings. When this pack is installed, Pack Detail
    /// delegates to the Home Row Mods UX the Rules tab uses.
    public static let homeRowMods = Pack(
        id: "com.keypath.pack.home-row-mods",
        version: "1.0.0",
        name: "Home Row Mods",
        tagline: "Tap for letters, hold for modifiers or layers",
        shortDescription:
            "Put your modifier keys under your strongest fingers. Tap A/S/D/F and J/K/L/; for the letter; hold for Shift / Control / Option / Command so shortcuts happen without leaving the home row.",
        longDescription: "",
        category: "Gallery",
        iconSymbol: "keyboard",
        iconSecondarySymbol: nil,
        quickSettings: [
            PackQuickSetting(
                id: "holdTimeout",
                label: "Hold timing",
                kind: .slider(
                    defaultValue: 180,
                    min: 120,
                    max: 300,
                    step: 20,
                    unitSuffix: " ms"
                )
            )
        ],
        bindings: [
            // CAGS left: A=Ctrl, S=Opt, D=Shift, F=Cmd
            PackBindingTemplate(input: "a", output: "a", holdOutput: "lctl",
                                title: "A · tap / Control · hold"),
            PackBindingTemplate(input: "s", output: "s", holdOutput: "lalt",
                                title: "S · tap / Option · hold"),
            PackBindingTemplate(input: "d", output: "d", holdOutput: "lsft",
                                title: "D · tap / Shift · hold"),
            PackBindingTemplate(input: "f", output: "f", holdOutput: "lmet",
                                title: "F · tap / Command · hold"),
            // CAGS right mirror: J=Cmd, K=Shift, L=Opt, ;=Ctrl
            PackBindingTemplate(input: "j", output: "j", holdOutput: "rmet",
                                title: "J · tap / Command · hold"),
            PackBindingTemplate(input: "k", output: "k", holdOutput: "rsft",
                                title: "K · tap / Shift · hold"),
            PackBindingTemplate(input: "l", output: "l", holdOutput: "ralt",
                                title: "L · tap / Option · hold"),
            PackBindingTemplate(input: "scln", output: "scln", holdOutput: "rctl",
                                title: "; · tap / Control · hold")
        ],
        associatedCollectionID: RuleCollectionIdentifier.homeRowMods
    )

    // MARK: - Pack 3: Escape Remap

    /// Gallery wrapper around the Rules tab's "Escape" single-key picker
    /// collection. Install toggles the collection; edits flow through
    /// `updateCollectionOutput` to persist the user's preset selection.
    public static let escapeRemap = Pack(
        id: "com.keypath.pack.escape-remap",
        version: "1.0.0",
        name: "Escape Remap",
        tagline: "Remap the Escape key",
        shortDescription:
            "Escape sits awkwardly off in the corner. Turn it into something more useful: Caps Lock (pairs perfectly with Caps Lock → Escape), backtick, or Tab. Pick below.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "escape",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "esc", output: "caps", title: "Escape Remap")
        ],
        associatedCollectionID: RuleCollectionIdentifier.escapeRemap
    )

    // MARK: - Pack 4: Delete Enhancement

    public static let deleteEnhancement = Pack(
        id: "com.keypath.pack.delete-enhancement",
        version: "1.0.0",
        name: "Delete Enhancement",
        tagline: "Leader + Delete for enhanced delete actions",
        shortDescription:
            "Regular Delete stays as-is. Hold the Leader key and press Delete to get a different action: forward delete, delete word, or delete to line start. Pick which below.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "delete.left",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "bspc", output: "del", title: "Delete Enhancement")
        ],
        associatedCollectionID: RuleCollectionIdentifier.deleteRemap
    )

    // MARK: - Pack 5: Backup Caps Lock

    public static let backupCapsLock = Pack(
        id: "com.keypath.pack.backup-caps-lock",
        version: "1.0.0",
        name: "Backup Caps Lock",
        tagline: "Alternative way to access Caps Lock",
        shortDescription:
            "If Caps Lock Remap turns your Caps Lock into something else, you can still get Caps Lock back via a chord. Pick the one that feels natural.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "shift",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "lsft-rsft", output: "caps", title: "Backup Caps Lock")
        ],
        associatedCollectionID: RuleCollectionIdentifier.backupCapsLock
    )

    // MARK: - Pack 6: Vim Navigation

    /// Collection-backed pack over `vimNavigation`. Activated by holding Space
    /// (the collection's momentary activator) to enter the navigation layer;
    /// inside that layer, hjkl become arrows, y/p are copy/paste, u is undo,
    /// etc. The pack ships with no explicit bindings — Pack Detail reads the
    /// mapping table from the associated collection so there's a single source
    /// of truth if the collection is updated.
    public static let vimNavigation = Pack(
        id: "com.keypath.pack.vim-navigation",
        version: "1.0.0",
        name: "Vim Navigation",
        tagline: "Hold Space for hjkl arrows and Vim motions",
        shortDescription:
            "Hold Space to enter Vim mode. h/j/k/l become arrow keys, y/p are copy/paste, u is undo, / is find. Release Space to go back to normal typing.",
        longDescription: "",
        category: "Navigation",
        iconSymbol: "arrow.up.and.down.and.arrow.left.and.right",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.vimNavigation
    )

    // MARK: - Pack 7: Window Snapping

    /// Collection-backed pack over `windowSnapping`. Entered as a nested
    /// layer — Leader → w takes you to the window layer, then action keys
    /// (l/r for halves, u/i/j/k for corners, [/] for displays, ,/. for
    /// Spaces) fire Accessibility-driven window moves.
    ///
    /// **Runtime dependency:** window moves require Accessibility API
    /// access. If the user has not granted it, pressing the action keys
    /// will parse but do nothing — kanata emits a `push-msg` that KeyPath
    /// intercepts; no AX access means no window ever moves. Surfacing a
    /// permission-check UI at install time is tracked as follow-up work
    /// (see docs/gallery/pack-migration-plan.md Tier-3 notes).
    public static let windowSnapping = Pack(
        id: "com.keypath.pack.window-snapping",
        version: "1.0.0",
        name: "Window Snapping",
        tagline: "Snap, move, and tile windows with Leader → w",
        shortDescription:
            "Hold Space, press W, then: L/R for left/right halves, M to maximize, U/I/J/K for corners, [ ] for displays, , . for Spaces, Z to undo. Requires Accessibility access (macOS will prompt on first use).",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "rectangle.split.2x2",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.windowSnapping
    )

    // MARK: - Pack 8: Mission Control

    /// Collection-backed pack over `missionControl`. Three-modifier chords
    /// (lctl + lmet + lalt + {up,down,left,right,d,n}) fire the system's
    /// Mission Control, Exposé, Desktop, and Notification Center actions —
    /// without fighting the physical F3 or binding a new shortcut from
    /// scratch. Renders via the generic collection-mappings fallback in
    /// Pack Detail.
    public static let missionControl = Pack(
        id: "com.keypath.pack.mission-control",
        version: "1.0.0",
        name: "Mission Control",
        tagline: "Shortcuts for Exposé, Desktop, Notification Center",
        shortDescription:
            "Triple-chord shortcuts (Ctrl + Cmd + Option + a direction) for Mission Control, App Exposé, Desktop switching, Show Desktop, and Notification Center. Avoids the F3 muscle memory, no reach.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "rectangle.3.group",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.missionControl
    )
}
