// M1 Gallery MVP — Pack data model.
// See docs/design/sprint-1/starter-kit.md and docs/design/m1-implementation-plan.md

import Foundation

/// A collection a pack manages atomically on install/uninstall.
/// The installer snapshots the collection's state before applying defaults
/// and offers to restore it when the pack is removed.
public struct ManagedCollectionDefault: Equatable, Sendable {
    /// The collection to manage
    public let collectionID: UUID
    /// Whether to enable this collection on install
    public let enableOnInstall: Bool
    /// Whether to disable this collection on install because it conflicts with
    /// the managed pack. Its previous state is still snapshotted for uninstall.
    public let disableOnInstall: Bool
    /// Configuration to apply on install (nil = just toggle, don't change config)
    public let defaultConfiguration: RuleCollectionConfiguration?
    /// Human-readable name for override/restore dialogs
    public let displayName: String

    public init(
        collectionID: UUID,
        enableOnInstall: Bool = true,
        disableOnInstall: Bool = false,
        defaultConfiguration: RuleCollectionConfiguration? = nil,
        displayName: String
    ) {
        self.collectionID = collectionID
        self.enableOnInstall = enableOnInstall
        self.disableOnInstall = disableOnInstall
        self.defaultConfiguration = defaultConfiguration
        self.displayName = displayName
    }
}

/// A **Pack** is a named, versioned collection of mappings distributed as a
/// unit. Users install packs from the Gallery; each installed pack contributes
/// one or more `CustomRule`s tagged with the pack's id so uninstall can
/// identify and remove them.
///
/// Packs in M1 are declared in Swift (hardcoded in `PackRegistry`), not loaded
/// from JSON. Serialization and distribution come in later milestones.
public struct Pack: Identifiable, Equatable, Sendable {
    /// Stable identifier used to tag `CustomRule.packSource` and persist
    /// install state in `InstalledPackTracker`. Must be unique across all
    /// packs and must not change between app versions (once released, it's a
    /// compatibility boundary).
    public let id: String
    /// Monotonic version. Bumped when any binding, description, or default
    /// changes in a way users should be notified about.
    public let version: String
    /// Short display name. User-facing. Max ~30 characters.
    public let name: String
    /// Card one-liner (≤ 60 characters). Per editorial-voice.md, this is
    /// value-framed, not mechanism-framed.
    public let tagline: String
    /// Elevator pitch (≤ 160 characters). Leads with the pain, names the
    /// transformation. No mechanism detail yet.
    public let shortDescription: String
    /// Full description (1-2 short paragraphs). Introduces mechanics and
    /// trade-offs. Displayed on Pack Detail.
    public let longDescription: String
    /// Author attribution. "KeyPath Team" for all M1 Starter Kit packs.
    public let author: String
    /// Short category label shown as a chip on the pack card. Used to give
    /// each pack a distinct visual identity ("Remap", "Home row", "Hyper").
    public let category: String
    /// Primary SF Symbol name displayed as the pack's hero icon on the card
    /// and in Pack Detail. Each pack should pick a distinctive symbol so
    /// cards don't look identical at a glance.
    public let iconSymbol: String
    /// Optional secondary symbol composed with the primary (e.g. "arrow.right"
    /// for a "this → that" transform). When nil, the primary stands alone.
    public let iconSecondarySymbol: String?
    /// Quick settings the user can adjust before or after install. Surfaced
    /// inline on Pack Detail. M1 supports at most one quick setting per pack;
    /// complex config is deferred to Customize UI in M2+.
    public let quickSettings: [PackQuickSetting]
    /// Template bindings this pack installs. Rendered into concrete
    /// `CustomRule`s by `PackInstaller` using the current quick-setting
    /// values at install time.
    public let bindings: [PackBindingTemplate]

    /// Optional pointer at an existing built-in `RuleCollection` this pack
    /// wraps. When set, install/uninstall *toggle the collection* rather
    /// than creating `CustomRule`s — and Pack Detail edits flow through the
    /// same persistence path Rules uses (e.g. `updateHomeRowModsConfig`).
    /// Used for packs whose underlying functionality is already modeled as
    /// a rule collection (Home Row Mods, future layers, etc).
    public let associatedCollectionID: UUID?

    /// True for "visual-only" packs — install/uninstall just toggles the
    /// installed-pack tracker record, with no kanata config side effects.
    /// Used for packs whose value is metadata + companion-app integration
    /// rather than remapping (e.g. KindaVim, where the kindaVim.app itself
    /// handles all key behavior and our pack only drives mode visualization).
    public let visualOnly: Bool

    /// Dependencies on other packs (requires + suggests).
    public let dependencies: [PackDependency]

    /// Collections this pack manages atomically on install/uninstall.
    /// Non-empty → system pack: the installer snapshots, applies defaults,
    /// and offers restore on uninstall. Empty → standard pack behavior.
    public let managedDefaults: [ManagedCollectionDefault]

    /// Keys that should trigger this pack's merchandising card when selected,
    /// independent of bindings. Used for packs like Leader Key whose input
    /// key is configurable rather than hardcoded in bindings.
    public let suggestedForKeys: [String]

    public init(
        id: String,
        version: String,
        name: String,
        tagline: String,
        shortDescription: String,
        longDescription: String,
        author: String = "KeyPath Team",
        category: String,
        iconSymbol: String,
        iconSecondarySymbol: String? = nil,
        quickSettings: [PackQuickSetting] = [],
        bindings: [PackBindingTemplate],
        associatedCollectionID: UUID? = nil,
        visualOnly: Bool = false,
        suggestedForKeys: [String] = [],
        dependencies: [PackDependency] = [],
        managedDefaults: [ManagedCollectionDefault] = []
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.tagline = tagline
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.author = author
        self.category = category
        self.iconSymbol = iconSymbol
        self.iconSecondarySymbol = iconSecondarySymbol
        self.quickSettings = quickSettings
        self.bindings = bindings
        self.associatedCollectionID = associatedCollectionID
        self.visualOnly = visualOnly
        self.dependencies = dependencies
        self.managedDefaults = managedDefaults
        self.suggestedForKeys = suggestedForKeys
    }

    /// The physical keys this pack affects. Drives Pack Detail's keyboard
    /// highlight and the install cascade animation.
    public var affectedKeys: [String] {
        Array(Set(bindings.map(\.input)))
    }

    /// True if this pack manages collections atomically via `managedDefaults`.
    public var isSystemPack: Bool {
        !managedDefaults.isEmpty
    }

    /// All rule collection UUIDs this pack manages when installed.
    /// System packs list their managed defaults; other packs list their
    /// single `associatedCollectionID`. Visual-only packs manage none.
    public var managedCollectionIDs: [UUID] {
        if visualOnly { return [] }
        if !managedDefaults.isEmpty {
            var ids = managedDefaults.map(\.collectionID)
            if let associated = associatedCollectionID, !ids.contains(associated) {
                ids.insert(associated, at: 0)
            }
            return ids
        }
        return [associatedCollectionID].compactMap { $0 }
    }

    /// Preferred width for Pack Detail presentation (window or sheet).
    public var preferredDetailWidth: CGFloat {
        let widePacks: Set = [
            "com.keypath.pack.vim-navigation",
            "com.keypath.pack.window-snapping",
            "com.keypath.pack.mission-control",
            "com.keypath.pack.numpad-layer",
            "com.keypath.pack.symbol-layer",
            "com.keypath.pack.fun-layer",
            "com.keypath.pack.caps-lock-to-escape",
        ]
        if widePacks.contains(id) { return 760 }
        if id == "com.keypath.pack.home-row-mods" { return 860 }
        if id == "com.keypath.pack.quick-launcher" { return 960 }
        if id == "com.keypath.pack.auto-shift-symbols" { return 640 }
        if id == "com.keypath.pack.key-repeat-control" { return 640 }
        return 560
    }
}

/// A quick setting a user can adjust on Pack Detail without opening a full
/// Customize UI. M1 supports sliders only; M2+ will add toggles and pickers.
public struct PackQuickSetting: Identifiable, Equatable, Sendable {
    public let id: String
    /// Short label shown next to the control.
    public let label: String
    /// Kind of control to render. M1: slider only.
    public let kind: Kind

    public init(id: String, label: String, kind: Kind) {
        self.id = id
        self.label = label
        self.kind = kind
    }

    public enum Kind: Equatable, Sendable {
        /// Integer slider. `defaultValue` is the initial position;
        /// `min` and `max` bound the slider; `step` is the increment.
        /// `unitSuffix` (e.g. "ms") is appended to the displayed value.
        case slider(defaultValue: Int, min: Int, max: Int, step: Int, unitSuffix: String)
    }

    /// Convenience for reading a slider's default value regardless of kind.
    public var defaultSliderValue: Int? {
        if case let .slider(defaultValue, _, _, _, _) = kind { return defaultValue }
        return nil
    }
}

/// A template for a single binding a pack will contribute. The template can
/// reference quick-setting values, which `PackInstaller` substitutes at
/// install time.
///
/// M1 templates are "literal" — the resolved binding is always a plain
/// `CustomRule`. Hold-behavior templates (for Home-Row Mods) carry a
/// `behavior` payload that gets attached to the resulting rule.
public struct PackBindingTemplate: Equatable, Sendable {
    /// Input key (kanata syntax, e.g. "caps", "a", "f").
    public let input: String
    /// Tap output. For simple remaps this is the whole behavior.
    public let output: String
    /// Optional hold output — if present, the resulting rule gets a
    /// `.tapHold` behavior. The hold output is a kanata action string
    /// (e.g. "lctl", "(one-shot-press 500 lshift)").
    public let holdOutput: String?
    /// Optional title to put on the resulting rule. Defaults to the pack
    /// name with an index suffix if omitted.
    public let title: String?
    /// Optional note to put on the resulting rule.
    public let notes: String?

    public init(
        input: String,
        output: String,
        holdOutput: String? = nil,
        title: String? = nil,
        notes: String? = nil
    ) {
        self.input = input
        self.output = output
        self.holdOutput = holdOutput
        self.title = title
        self.notes = notes
    }
}
