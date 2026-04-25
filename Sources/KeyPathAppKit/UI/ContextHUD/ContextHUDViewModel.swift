import KeyPathCore
import Observation
import SwiftUI

/// View model for the Context HUD, transforming layer key data into grouped entries
@Observable
@MainActor
final class ContextHUDViewModel {
    /// Current layer name displayed in the HUD header
    var layerName: String = ""
    /// Content style determined by the content resolver
    var style: HUDContentStyle = .defaultList
    /// Grouped key entries for the default list view
    var groups: [HUDKeyGroup] = []
    /// Flat list of all entries (for custom views that don't use grouping)
    var allEntries: [HUDKeyEntry] = []
    /// Live KindaVim state snapshot used by mode-aware learning UI.
    var kindaVimState: KindaVimStateAdapter.StateSnapshot?
    /// Presentation mode configured in Rules for leader-hold KindaVim content.
    var kindaVimLeaderHUDMode: KindaVimLeaderHUDMode = .contextualCoach

    /// Key codes currently pressed (for live highlighting)
    var pressedKeyCodes: Set<UInt16> = []
    /// Hold labels keyed by keyCode (for active modifier badge)
    var activeHoldLabels: [UInt16: String] = [:]
    /// Unique hold labels for header badges
    var holdBadges: [String] {
        Array(Set(activeHoldLabels.values)).sorted()
    }

    /// Transform raw layer key data into grouped HUD entries
    /// - Parameters:
    ///   - layerName: The current layer name
    ///   - keyMap: Key code to LayerKeyInfo mapping from LayerKeyMapper
    ///   - collections: All enabled rule collections (for name/color lookup)
    ///   - style: The content style to use
    ///   - launcherKeyMap: Optional launcher layer keyMap to show alongside the main layer
    func update(
        layerName: String,
        keyMap: [UInt16: LayerKeyInfo],
        collections: [RuleCollection],
        style: HUDContentStyle,
        holdLabels: [UInt16: String] = [:],
        launcherKeyMap: [UInt16: LayerKeyInfo]? = nil,
        kindaVimState: KindaVimStateAdapter.StateSnapshot? = nil,
        kindaVimLeaderHUDMode: KindaVimLeaderHUDMode = .contextualCoach
    ) {
        self.layerName = layerName
        self.style = style

        // Build collection lookup by UUID
        let collectionLookup = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })

        // Filter out transparent keys, identity mappings, and raw HID codes
        let entries: [HUDKeyEntry] = keyMap.compactMap { keyCode, info in
            guard !info.isTransparent else { return nil }

            // Skip raw HID codes (e.g., "k464") — these are unmapped system keys
            if let output = info.outputKey,
               output.lowercased().hasPrefix("k"),
               Int(output.dropFirst()) != nil
            {
                return nil
            }

            // Skip identity mappings the transparent detector missed
            // (e.g., fn→fn where simulator outputs a different code)
            // Only apply to keys without a collection — collection-assigned keys are intentional
            if info.collectionId == nil,
               let output = info.outputKey
            {
                let inputName = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
                if LayerKeyMapper.normalizeKeyName(inputName) == LayerKeyMapper.normalizeKeyName(output) {
                    return nil
                }
            }

            var keycap = keycapLabel(for: keyCode)
            let color = collectionColor(for: info.collectionId)
            let sfSymbol = info.systemActionIdentifier.flatMap {
                IconResolverService.shared.systemActionSymbol(for: $0)
            }

            // Look up hold label; filter out cases where hold == tap (not a real tap-hold key)
            let holdLabel: String? = {
                guard let label = holdLabels[keyCode], label != info.displayLabel else { return nil }
                return label
            }()

            // For VIM entries: use lowercase keycap (vim is case-sensitive),
            // override with vim notation, use English description
            let action: String
            if let vimLabel = info.vimLabel {
                keycap = keycap.lowercased()
                if let override = Self.vimKeycapOverrides[keycap] {
                    keycap = override
                }
                action = Self.vimHUDDescriptions[vimLabel] ?? vimLabel
            } else {
                action = info.displayLabel
            }

            return HUDKeyEntry(
                keycap: keycap,
                action: action,
                sfSymbol: sfSymbol,
                appIdentifier: info.appLaunchIdentifier,
                urlIdentifier: info.urlIdentifier,
                holdAction: holdLabel,
                color: color,
                keyCode: keyCode
            )
        }.sorted { $0.keyCode < $1.keyCode }

        // Build launcher entries as a separate list (all app/URL shortcuts)
        let launcherEntries: [HUDKeyEntry] = launcherKeyMap?.compactMap { keyCode, info in
            guard info.appLaunchIdentifier != nil || info.urlIdentifier != nil else { return nil }
            let keycap = keycapLabel(for: keyCode)
            let color = collectionColor(for: info.collectionId)
            return HUDKeyEntry(
                keycap: keycap,
                action: info.displayLabel,
                sfSymbol: nil,
                appIdentifier: info.appLaunchIdentifier,
                urlIdentifier: info.urlIdentifier,
                holdAction: nil,
                color: color,
                keyCode: keyCode
            )
        }.sorted { $0.keyCode < $1.keyCode } ?? []

        allEntries = entries + launcherEntries

        // Group by collection
        var groupMap: [UUID: (name: String, color: Color, entries: [HUDKeyEntry])] = [:]
        let defaultGroupId = UUID()

        for entry in entries {
            // Find the collection ID for this entry's key
            let collectionId = keyMap[entry.keyCode]?.collectionId ?? defaultGroupId
            if groupMap[collectionId] == nil {
                let collection = collectionLookup[collectionId]
                let name = collection?.name ?? "Keys"
                let color = collectionColor(for: collectionId == defaultGroupId ? nil : collectionId)
                groupMap[collectionId] = (name: name, color: color, entries: [])
            }
            groupMap[collectionId]?.entries.append(entry)
        }

        // Add launcher entries as their own group
        for entry in launcherEntries {
            let collectionId = launcherKeyMap?[entry.keyCode]?.collectionId ?? defaultGroupId
            if groupMap[collectionId] == nil {
                let collection = collectionLookup[collectionId]
                let name = collection?.name ?? "Quick Launch"
                let color = collectionColor(for: collectionId == defaultGroupId ? nil : collectionId)
                groupMap[collectionId] = (name: name, color: color, entries: [])
            }
            groupMap[collectionId]?.entries.append(entry)
        }

        // Split vim entries into semantic sub-groups (Movement, Editing, Search)
        var vimSubGroups: [HUDKeyGroup] = []
        if let vimGroup = groupMap[RuleCollectionIdentifier.vimNavigation] {
            groupMap.removeValue(forKey: RuleCollectionIdentifier.vimNavigation)
            var subGroupEntries: [String: (order: Int, entries: [HUDKeyEntry])] = [:]
            for entry in vimGroup.entries {
                let vimLabel = keyMap[entry.keyCode]?.vimLabel
                let sub = vimLabel.flatMap { Self.vimSubcategories[$0] }
                    ?? (name: "Other", order: 99)
                subGroupEntries[sub.name, default: (order: sub.order, entries: [])].entries.append(entry)
            }
            for (name, group) in subGroupEntries {
                vimSubGroups.append(HUDKeyGroup(
                    name: name, color: vimGroup.color,
                    entries: group.entries, sortOrder: group.order
                ))
            }
        }

        // KindaVim used to ship as a rule collection whose entries were split
        // into sub-groups here. The collection is retired (KindaVim is now a
        // visual-only pack); the .kindaVimLearning style is its own view and
        // doesn't read `groups[]`. Nothing to do for KindaVim in this pass.

// Split Neovim Terminal entries into semantic sub-groups
        if let neovimGroup = groupMap[RuleCollectionIdentifier.neovimTerminal] {
            groupMap.removeValue(forKey: RuleCollectionIdentifier.neovimTerminal)
            var subGroupEntries: [String: (order: Int, entries: [HUDKeyEntry])] = [:]
            for entry in neovimGroup.entries {
                let vimLabel = keyMap[entry.keyCode]?.vimLabel
                let sub = vimLabel.flatMap { Self.neovimSubcategories[$0] }
                    ?? (name: "Other", order: 99)
                subGroupEntries[sub.name, default: (order: sub.order, entries: [])].entries.append(entry)
            }
            for (name, group) in subGroupEntries {
                vimSubGroups.append(HUDKeyGroup(
                    name: name, color: neovimGroup.color,
                    entries: group.entries, sortOrder: group.order
                ))
            }
        }

        groups = (groupMap.values
            .map { HUDKeyGroup(name: $0.name, color: $0.color, entries: $0.entries) }
            + vimSubGroups)
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }

        if style == .kindaVimLearning {
            self.kindaVimState = kindaVimState
            self.kindaVimLeaderHUDMode = kindaVimLeaderHUDMode
        } else {
            self.kindaVimState = nil
            self.kindaVimLeaderHUDMode = .contextualCoach
        }
    }

    /// Clear all HUD data
    func clear() {
        layerName = ""
        style = .defaultList
        groups = []
        allEntries = []
        kindaVimState = nil
        kindaVimLeaderHUDMode = .contextualCoach
        pressedKeyCodes = []
        activeHoldLabels = [:]
    }

    // MARK: - Private Helpers

    /// Punctuation key names → display symbols
    private static let keycapSymbols: [String: String] = [
        "SLASH": "/",
        "DOT": ".",
        "COMMA": ",",
        "SEMICOLON": ";",
        "APOSTROPHE": "'",
        "BACKSLASH": "\\",
        "LBRACKET": "[",
        "RBRACKET": "]",
        "EQUAL": "=",
        "MINUS": "-",
        "GRAVE": "`",
    ]

    /// VIM keycap overrides — show vim motion instead of physical key
    private static let vimKeycapOverrides: [String: String] = [
        "4": "$",
    ]

    /// VIM subcategory mapping: vimLabel → (subcategory name, sort order)
    /// Used to split the single "Vim Navigation" group into semantic sub-groups
    static let vimSubcategories: [String: (name: String, order: Int)] = [
        // Movement
        "←": ("Movement", 0), "↓": ("Movement", 0),
        "↑": ("Movement", 0), "→": ("Movement", 0),
        "0": ("Movement", 0), "$": ("Movement", 0),
        "gg": ("Movement", 0),
        // Editing
        "a": ("Editing", 1), "yank": ("Editing", 1),
        "put": ("Editing", 1), "del": ("Editing", 1),
        "d": ("Editing", 1), "undo": ("Editing", 1),
        "redo": ("Editing", 1), "o": ("Editing", 1),
        // Search
        "find": ("Search", 2), "next": ("Search", 2),
    ]

/// Neovim Terminal subcategory mapping: vimLabel → (subcategory name, sort order)
    static let neovimSubcategories: [String: (name: String, order: Int)] = [
        // Movement
        "←": ("Movement", 0), "↓": ("Movement", 0),
        "↑": ("Movement", 0), "→": ("Movement", 0),
        "0": ("Movement", 0), "$": ("Movement", 0),
        "gg": ("Movement", 0),
        // Word Motion
        "w": ("Word Motion", 1), "b": ("Word Motion", 1), "e": ("Word Motion", 1),
        // Editing
        "a": ("Editing", 2), "del": ("Editing", 2),
        "d": ("Editing", 2), "undo": ("Editing", 2),
        "redo": ("Editing", 2), "o": ("Editing", 2),
        // Search
        "find": ("Search", 3), "next": ("Search", 3),
        // Clipboard
        "yank": ("Clipboard", 4), "put": ("Clipboard", 4),
    ]

    /// VIM English descriptions for the HUD action column
    private static let vimHUDDescriptions: [String: String] = [
        "←": "← left",
        "↓": "↓ down",
        "↑": "↑ up",
        "→": "→ right",
        "0": "line start",
        "$": "line end",
        "a": "append",
        "gg": "doc top / bottom",
        "find": "find",
        "next": "next / prev match",
        "yank": "copy",
        "put": "paste",
        "del": "fwd delete",
        "redo": "redo",
        "d": "delete previous word",
        "undo": "undo",
        "o": "open line below/above",
        // KindaVim word motion extras
        "w": "word →",
        "b": "← word",
        "e": "end word",
    ]

    /// Convert key code to a display label for the keycap
    private func keycapLabel(for keyCode: UInt16) -> String {
        let name = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        let upper = name.uppercased()
        // Show symbol for punctuation keys
        if let symbol = Self.keycapSymbols[upper] {
            return symbol
        }
        return upper
    }

    /// Get collection color matching the overlay's color scheme
    private func collectionColor(for collectionId: UUID?) -> Color {
        guard let id = collectionId else {
            return Color(red: 0.85, green: 0.45, blue: 0.15) // default orange
        }

        switch id {
        case RuleCollectionIdentifier.vimNavigation:
            return Color(red: 0.85, green: 0.45, blue: 0.15) // orange
        case RuleCollectionIdentifier.kindaVim:
            return Color(red: 0.2, green: 0.7, blue: 0.4) // green
        case RuleCollectionIdentifier.neovimTerminal:
            return Color(red: 0.3, green: 0.6, blue: 0.9) // steel blue
        case RuleCollectionIdentifier.windowSnapping:
            return .purple
        case RuleCollectionIdentifier.symbolLayer:
            return .blue
        case RuleCollectionIdentifier.launcher:
            return .cyan
        default:
            return Color(red: 0.85, green: 0.45, blue: 0.15) // default orange
        }
    }
}
