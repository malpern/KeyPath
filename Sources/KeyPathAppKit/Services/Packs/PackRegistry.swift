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
        homeRowModsLight,
        rightCommandAsHyper
    ]

    /// Look up a pack by id. Returns nil if unknown.
    public static func pack(id: String) -> Pack? {
        starterKit.first(where: { $0.id == id })
    }

    // MARK: - Pack 1: Caps Lock → Escape

    public static let capsLockToEscape = Pack(
        id: "com.keypath.pack.caps-lock-to-escape",
        version: "1.0.0",
        name: "Caps Lock → Escape",
        tagline: "A useful key where Caps Lock used to be.",
        shortDescription:
            "Caps Lock almost no one uses. Escape you press constantly — and it lives in the corner. This pack swaps them.",
        longDescription: """
        One key, one mapping, no configuration. Flip the switch and Caps Lock becomes Escape — that's it. The remap most Mac users have heard about; if you've been curious, this is the one to start with.
        """,
        category: "Remap",
        iconSymbol: "capslock",
        iconSecondarySymbol: "escape",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(
                input: "caps",
                output: "esc",
                title: "Caps Lock → Escape"
            )
        ]
    )

    // MARK: - Pack 2: Home-Row Mods — Light

    public static let homeRowModsLight = Pack(
        id: "com.keypath.pack.home-row-mods-light",
        version: "1.0.0",
        name: "Home-Row Mods — Light",
        tagline: "Shortcuts without leaving the home row (starter set).",
        shortDescription:
            "Puts ⌘ and ⇧ under your strongest fingers so shortcuts happen without leaving the home row.",
        longDescription: """
        Modifier keys live at the corners of your keyboard. This Light variant puts ⇧ on D/K and ⌘ on F/J: tap for the letter, hold for the modifier. The gentlest onramp to home-row modding — fewer accidental triggers than the full CAGS variant.
        """,
        category: "Home row",
        iconSymbol: "hand.point.up.left.fill",
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
            // Left hand
            PackBindingTemplate(input: "d", output: "d", holdOutput: "lsft",
                                title: "D · tap / Shift · hold"),
            PackBindingTemplate(input: "f", output: "f", holdOutput: "lmet",
                                title: "F · tap / Command · hold"),
            // Right hand
            PackBindingTemplate(input: "j", output: "j", holdOutput: "rmet",
                                title: "J · tap / Command · hold"),
            PackBindingTemplate(input: "k", output: "k", holdOutput: "rsft",
                                title: "K · tap / Shift · hold")
        ]
    )

    // MARK: - Pack 3: Right Command as Hyper

    public static let rightCommandAsHyper = Pack(
        id: "com.keypath.pack.right-command-as-hyper",
        version: "1.0.0",
        name: "Right Command as Hyper",
        tagline: "One extra modifier that doesn't collide with anything.",
        shortDescription:
            "Hyper is ⌃⌥⇧⌘ pressed together — a modifier no app uses. This pack turns your right Command key into Hyper.",
        longDescription: """
        Tap right Command and it still sends right Command, so ⌘Tab keeps working. Hold it and you get Hyper: ⌃⌥⇧⌘ all at once. Pair it with Raycast or native shortcuts to build bindings no app will ever collide with.
        """,
        category: "Power user",
        iconSymbol: "sparkles",
        iconSecondarySymbol: "command",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(
                input: "rmet",
                output: "rmet",
                holdOutput: "(multi lctl lalt lsft lmet)",
                title: "Right Command · tap / Hyper · hold",
                notes: "Tapping sends right Command; holding sends ⌃⌥⇧⌘ together."
            )
        ]
    )
}
