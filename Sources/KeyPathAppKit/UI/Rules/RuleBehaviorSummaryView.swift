import KeyPathCore
import SwiftUI

/// Inline summary of a rule's custom behavior — "Hold: X", tap-dance steps,
/// chord output, etc. Extracted from `MappingRowView` so the same visual
/// treatment can be reused in the Gallery's Pack Detail view (which
/// surfaces pack bindings that may carry the same behaviors).
///
/// Pure presentation: no side effects, safe to drop anywhere a rule's
/// behavior should be shown beside its input/output chips.
struct RuleBehaviorSummaryView: View {
    let behavior: MappingBehavior

    var body: some View {
        HStack(spacing: 6) {
            switch behavior {
            case let .dualRole(dr):
                behaviorItem(icon: "hand.point.up.left", label: "Hold", key: dr.holdAction)

            case let .tapOrTapDance(tapBehavior):
                if case let .tapDance(td) = tapBehavior {
                    let behaviorItems = Self.extractTapDanceSteps(from: td)
                    if behaviorItems.isEmpty {
                        EmptyView()
                    } else {
                        ForEach(behaviorItems.indices, id: \.self) { itemIndex in
                            let item = behaviorItems[itemIndex]
                            if itemIndex > 0 {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            behaviorItem(icon: item.icon, label: item.label, key: item.key)
                        }
                    }
                }

            case .macro:
                EmptyView()

            case let .chord(ch):
                behaviorItem(
                    icon: "rectangle.on.rectangle",
                    label: "Combo",
                    key: ch.keys.joined(separator: "+") + " → " + ch.output
                )
            }
        }
        .foregroundColor(.secondary)
    }

    private func behaviorItem(icon: String, label: String, key: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
            KeyCapChip(text: Self.formatKeyForBehavior(key))
        }
    }

    // MARK: - Pure helpers (internal so MappingRowView can keep using them)

    /// Tap-dance steps from index 1 onward (index 0 is the tap action, shown
    /// separately). Returns (icon, label, key) tuples in edit order.
    static func extractTapDanceSteps(from td: TapDanceBehavior)
        -> [(icon: String, label: String, key: String)]
    {
        let tapLabels = ["Double Tap", "Triple Tap", "Quad Tap", "5× Tap", "6× Tap", "7× Tap"]
        var items: [(icon: String, label: String, key: String)] = []
        for index in 1 ..< td.steps.count {
            let step = td.steps[index]
            guard !step.action.isEmpty else { continue }
            let labelIndex = index - 1
            let label = labelIndex < tapLabels.count ? tapLabels[labelIndex] : "\(index + 1)× Tap"
            items.append((icon: "hand.tap", label: label, key: step.action))
        }
        return items
    }

    static func formatKeyForBehavior(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "spc": "␣ Space",
            "space": "␣ Space",
            "caps": "⇪ Caps",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "bspc": "⌫ Delete",
            "del": "⌦ Fwd Del",
            "esc": "⎋ Escape",
            "lmet": "⌘ Cmd",
            "rmet": "⌘ Cmd",
            "lalt": "⌥ Opt",
            "ralt": "⌥ Opt",
            "lctl": "⌃ Ctrl",
            "rctl": "⌃ Ctrl",
            "lsft": "⇧ Shift",
            "rsft": "⇧ Shift",
            "hyper": "✦ Hyper",
            "meh": "◇ Meh"
        ]
        if let symbol = keySymbols[key.lowercased()] {
            return symbol
        }

        var result = key
        var prefix = ""
        if result.hasPrefix("M-") {
            prefix = "⌘"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("C-") {
            prefix = "⌃"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("A-") {
            prefix = "⌥"
            result = String(result.dropFirst(2))
        } else if result.hasPrefix("S-") {
            prefix = "⇧"
            result = String(result.dropFirst(2))
        }
        return prefix + result
    }
}
