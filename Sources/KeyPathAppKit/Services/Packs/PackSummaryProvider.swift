import Foundation

/// Derives the blue "Tap: X · Hold: Y" summary line shown under the pack
/// name in Pack Detail. Pulled out of `PackDetailView` so the logic is
/// pure and trivially unit-testable — no SwiftUI, no singletons.
///
/// Rules for the result:
/// * `.tapHoldPicker` collections → "Tap: <tap> · Hold: <hold>" (live
///   selections win over collection defaults win over pack template).
/// * `.singleKeyPicker` collections → "Remap: <input> → <output>" using
///   the selected preset's label when it's in the preset list.
/// * `.homeRowMods` and other multi-binding collections → nil (the
///   embedded editor shows the per-key state; a single line would be
///   misleading).
/// * No associated collection → fall back to the pack's first binding
///   template (legacy rule-based packs).
struct PackSummaryProvider {
    /// A minimal view of what the Pack Detail caller knows: the pack
    /// itself, the live-looked-up rule collection (if any), and the
    /// user's in-flight picker overrides (if any).
    struct Input {
        let pack: Pack
        let collection: RuleCollection?
        let tapOverride: String?
        let holdOverride: String?
        let singleKeyOverride: String?
    }

    static func summary(for input: Input) -> String? {
        if let collection = input.collection {
            switch collection.configuration {
            case .tapHoldPicker:
                return tapHoldSummary(for: input, collection: collection)
            case .singleKeyPicker:
                return singleKeySummary(for: input, collection: collection)
            case .homeRowMods, .homeRowLayerToggles, .chordGroups, .sequences,
                 .launcherGrid, .layerPresetPicker, .autoShiftSymbols,
                 .table, .list:
                // Multi-binding or complex configs — the embedded editor
                // shows everything; a one-liner would misrepresent state.
                return nil
            }
        }
        // No collection: rule-based pack. Use its template.
        guard let template = input.pack.bindings.first else { return nil }
        return templateSummary(template)
    }

    // MARK: - Builders per configuration type

    private static func tapHoldSummary(for input: Input, collection: RuleCollection) -> String? {
        let config = collection.configuration.tapHoldPickerConfig
        // Resolve tap: override > collection's stored selection > collection's
        // default mapping > pack template > "—".
        let defaultTap = collection.mappings.first.flatMap { mapping -> String? in
            if case let .dualRole(dr) = mapping.behavior { return dr.tapAction }
            return mapping.output
        }
        let defaultHold = collection.mappings.first.flatMap { mapping -> String? in
            if case let .dualRole(dr) = mapping.behavior { return dr.holdAction }
            return nil
        }
        let tap = input.tapOverride
            ?? config?.selectedTapOutput
            ?? defaultTap
            ?? input.pack.bindings.first?.output
        let hold = input.holdOverride
            ?? config?.selectedHoldOutput
            ?? defaultHold
            ?? input.pack.bindings.first?.holdOutput

        let tapLabel = tap.map(formatKey) ?? "—"
        if let hold, !hold.isEmpty {
            return "Tap: \(tapLabel)  ·  Hold: \(formatKey(hold))"
        }
        return "Tap: \(tapLabel)"
    }

    private static func singleKeySummary(for input: Input, collection: RuleCollection) -> String? {
        let config = collection.configuration.singleKeyPickerConfig
        let inputKey = config?.inputKey ?? input.pack.bindings.first?.input ?? ""
        let output = input.singleKeyOverride
            ?? config?.selectedOutput
            ?? input.pack.bindings.first?.output
        guard let output else { return nil }
        // Prefer the preset's label (e.g. "⎋ Escape") over a raw token.
        let presetLabel = config?.presetOptions.first { $0.output == output }?.label
        let outputLabel = presetLabel ?? formatKey(output)
        let inputLabel = formatKey(inputKey)
        return "\(inputLabel) → \(outputLabel)"
    }

    private static func templateSummary(_ template: PackBindingTemplate) -> String {
        let tap = formatKey(template.output)
        if let hold = template.holdOutput, !hold.isEmpty {
            return "Tap: \(tap)  ·  Hold: \(formatKey(hold))"
        }
        return "Tap: \(tap)"
    }

    // MARK: - Key formatting

    /// Inline copy of `RuleBehaviorSummaryView.formatKeyForBehavior` so
    /// this file stays in the non-UI layer. Any change here should be
    /// mirrored in RuleBehaviorSummaryView (both render the same tokens).
    static func formatKey(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "spc": "␣ Space", "space": "␣ Space",
            "caps": "⇪ Caps", "tab": "⇥ Tab",
            "ret": "↩ Return", "bspc": "⌫ Delete",
            "del": "⌦ Fwd Del", "esc": "⎋ Escape",
            "lmet": "⌘ Cmd", "rmet": "⌘ Cmd",
            "lalt": "⌥ Opt", "ralt": "⌥ Opt",
            "lctl": "⌃ Ctrl", "rctl": "⌃ Ctrl",
            "lsft": "⇧ Shift", "rsft": "⇧ Shift",
            "hyper": "✦ Hyper", "meh": "◇ Meh"
        ]
        if let symbol = keySymbols[key.lowercased()] {
            return symbol
        }
        return key
    }
}
