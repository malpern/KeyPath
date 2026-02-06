import KeyPathCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - Mapping Row View

struct MappingRowView: View {
    let mapping: (input: String, output: String, shiftedOutput: String?, ctrlOutput: String?, description: String?, sectionBreak: Bool, enabled: Bool, id: UUID, behavior: MappingBehavior?)
    let layerActivator: MomentaryActivator?
    var leaderKeyDisplay: String = "␣ Space"
    let onEditMapping: ((UUID) -> Void)?
    let onDeleteMapping: ((UUID) -> Void)?
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    /// Extract app identifier from push-msg launch output
    private var appLaunchIdentifier: String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: mapping.output)
    }

    private var isEditable: Bool {
        onEditMapping != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Mapping content
                HStack(spacing: 8) {
                    // Show layer activator if present
                    if layerActivator != nil {
                        HStack(spacing: 4) {
                            Text("Hold")
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(.accentColor)
                            Text(leaderKeyDisplay)
                                .font(.body.monospaced().weight(.semibold))
                                .foregroundColor(KeycapStyle.textColor)
                        }
                        .modifier(KeycapStyle())

                        Text("+")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    Text(prettyKeyName(mapping.input))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)

                    // Show app icon + name for launch actions, otherwise show key chip
                    if let appId = appLaunchIdentifier {
                        RulesSummaryAppLaunchChip(appIdentifier: appId)
                    } else {
                        Text(prettyKeyName(mapping.output))
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundColor(KeycapStyle.textColor)
                            .modifier(KeycapStyle())
                    }

                    // Show rule name/title if provided
                    if let title = mapping.description, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Behavior summary for custom rules on same line
                    if let behavior = mapping.behavior {
                        behaviorSummaryView(behavior: behavior)
                    }

                    Spacer(minLength: 0)
                }

                Spacer()

                // Action buttons - subtle icons that appear on hover
                if onEditMapping != nil || onDeleteMapping != nil {
                    HStack(spacing: 4) {
                        if let onEdit = onEditMapping {
                            Button {
                                onEdit(mapping.id)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if let onDelete = onDeleteMapping {
                            Button {
                                onDelete(mapping.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // Spacer for alignment
                        Spacer()
                            .frame(width: 0)
                    }
                }
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered && isEditable ? Color.primary.opacity(0.03) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if isEditable {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .onTapGesture {
            if let onEdit = onEditMapping {
                onEdit(mapping.id)
            }
        }
    }

    @ViewBuilder
    private func behaviorSummaryView(behavior: MappingBehavior) -> some View {
        HStack(spacing: 6) {
            switch behavior {
            case let .dualRole(dr):
                behaviorItem(icon: "hand.point.up.left", label: "Hold", key: dr.holdAction)

            case let .tapOrTapDance(tapBehavior):
                if case let .tapDance(td) = tapBehavior {
                    let behaviorItems = extractBehaviorItemsInEditOrder(from: td)

                    if behaviorItems.isEmpty {
                        EmptyView()
                    } else {
                        ForEach(Array(behaviorItems.enumerated()), id: \.offset) { itemIndex, item in
                            if itemIndex > 0 {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            behaviorItem(icon: item.0, label: item.1, key: item.2)
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

    // Extract tap dance steps (skip index 0 which is single tap = output)
    private func extractBehaviorItemsInEditOrder(from td: TapDanceBehavior) -> [(String, String, String)] {
        var behaviorItems: [(String, String, String)] = []

        // Step 0 = single tap (shown as "Finish" already)
        // Step 1+ = double tap, triple tap, etc.
        let tapLabels = ["Double Tap", "Triple Tap", "Quad Tap", "5× Tap", "6× Tap", "7× Tap"]
        let tapIcons = ["hand.tap", "hand.tap", "hand.tap", "hand.tap", "hand.tap", "hand.tap"]

        for index in 1 ..< td.steps.count {
            let step = td.steps[index]
            guard !step.action.isEmpty else { continue }

            let labelIndex = index - 1
            let label = labelIndex < tapLabels.count ? tapLabels[labelIndex] : "\(index + 1)× Tap"
            let icon = labelIndex < tapIcons.count ? tapIcons[labelIndex] : "hand.tap"

            behaviorItems.append((icon, label, step.action))
        }

        return behaviorItems
    }

    @ViewBuilder
    private func behaviorItem(icon: String, label: String, key: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
            KeyCapChip(text: formatKeyForBehavior(key))
        }
    }

    /// Format a modifier key for display
    private func formatModifierForDisplay(_ modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    private func formatKeyForBehavior(_ key: String) -> String {
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
            "rsft": "⇧ Shift"
        ]

        if let symbol = keySymbols[key.lowercased()] {
            return symbol
        }

        // Handle modifier prefixes
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

        if let symbol = keySymbols[result.lowercased()] {
            return prefix + symbol
        }

        return prefix + result.capitalized
    }
}
