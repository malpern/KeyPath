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
            "Caps Lock is a key almost no one uses on purpose. Escape is a key you press constantly — and it lives all the way in the corner. This pack makes Caps Lock into Escape, and nothing else.",
        longDescription: """
        Caps Lock is a vestigial key — a relic of typewriters, sitting in prime real estate on a modern keyboard. Escape, meanwhile, is one of the most-used keys on a Mac: every dialog, every mode, every moment of cancellation wants it. And Apple put it in the top-left corner, where it takes a deliberate stretch to reach.

        This is the simplest pack in KeyPath — one key, one mapping, no configuration. Install it, press Caps Lock, and nothing happens but an Escape keystroke. It's the remap most users have been told about before they found us; if you've been curious, this is the one to start with.
        """,
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
            "Keyboard shortcuts make you reach for the corners of your keyboard dozens of times a day. This pack puts Command and Shift under your strongest fingers — you can press ⌘C or ⇧-Tab without moving your hands off the home row.",
        longDescription: """
        Modifier keys — ⌘, ⇧ — live at the corners of your keyboard, forcing you to reach or curl your fingers to press them. Every time you use a shortcut, your hands move away from the home row.

        The Light variant of Home-Row Mods assigns modifiers only to the index and middle fingers on each hand: D/F on the left, J/K on the right. Tap those keys and you get the letter. Hold them briefly and you get ⇧ or ⌘. It's the gentlest onramp to home-row modding — fewer accidental triggers, shorter learning curve than the full CAGS variant, and all the everyday shortcuts (copy, paste, undo, tab) become single-hand gestures.
        """,
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
            "Many shortcuts are taken — ⌘C, ⌘V, ⌘Tab. Apps fight over them. The Hyper key is ⌃⌥⇧⌘ pressed together: nothing collides with it. This pack turns your right Command key into Hyper so you have a modifier that's yours alone.",
        longDescription: """
        Running out of keyboard shortcuts is a real problem. Every app wants ⌘K, ⌘P, ⌘/ for its own purpose, and you end up memorizing overlapping bindings or giving up on shortcuts for some apps. The Hyper key — ⌃⌥⇧⌘ all at once — solves this by giving you a modifier no app uses by default. You can bind Hyper-A, Hyper-S, Hyper-whatever to anything and never hit a conflict.

        This pack repurposes the right Command key: tap it normally and it still sends right Command (so ⌘Tab etc. work as before); hold it and it acts as Hyper. Combine it with launcher tools like Raycast or native macOS shortcuts to build a workspace no app can interrupt.
        """,
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
