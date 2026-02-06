import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Toolbar

struct CustomRulesToolbarView: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom Rules")
                    .font(.headline)
                Text("These rules stay separate from presets so you can manage them independently.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Inline Editor

struct CustomRulesInlineEditor: View {
    @Binding var inputKey: String
    @Binding var outputKey: String
    @Binding var title: String
    @Binding var notes: String
    @Binding var inlineError: String?
    let keyOptions: [String]
    let onAddRule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Add")
                .font(.subheadline.weight(.medium))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                InlineKeyField(
                    title: "Input",
                    text: $inputKey,
                    options: keyOptions,
                    fieldWidth: 200,
                    textFieldIdentifier: "custom-rules-inline-input",
                    menuIdentifier: "custom-rules-inline-input-menu"
                )

                Text("→")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 18)

                InlineKeyField(
                    title: "Output",
                    text: $outputKey,
                    options: keyOptions,
                    fieldWidth: 240,
                    textFieldIdentifier: "custom-rules-inline-output",
                    menuIdentifier: "custom-rules-inline-output-menu"
                )

                Button {
                    onAddRule()
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("custom-rules-inline-add-button")
                .accessibilityLabel("Add custom rule")
                .padding(.top, 18)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .accessibilityIdentifier("custom-rules-inline-title")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                        .lineLimit(1 ... 3)
                        .accessibilityIdentifier("custom-rules-inline-notes")
                }
            }

            Text("Tip: type modifiers like C-a or M-k, or space-separated sequences.")
                .font(.caption2)
                .foregroundColor(.secondary)

            if let inlineError {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("custom-rules-inline-error")
            }
        }
    }
}

// MARK: - List View

struct CustomRulesListView: View {
    let rules: [CustomRule]
    let appKeymaps: [AppKeymap]
    let onToggleRule: (CustomRule, Bool) -> Void
    let onEditRule: (CustomRule) -> Void
    let onDeleteRule: (CustomRule) -> Void
    let onDeleteAppRule: (AppKeymap, AppKeyOverride) -> Void

    private var hasAnyRules: Bool {
        !rules.isEmpty || !appKeymaps.isEmpty
    }

    var body: some View {
        if !hasAnyRules {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(.secondary.opacity(0.3))

                    VStack(spacing: 4) {
                        Text("No Custom Rules Yet")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text("Create personalized key mappings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // MARK: - Everywhere Section

                    if !rules.isEmpty {
                        RulesSectionHeader(
                            title: "Everywhere",
                            systemImage: "globe",
                            subtitle: "These rules apply in all apps"
                        )
                        .padding(.horizontal, 16)

                        ForEach(rules) { rule in
                            CustomRuleRow(
                                rule: rule,
                                onToggle: { isOn in
                                    onToggleRule(rule, isOn)
                                },
                                onEditInDrawer: {
                                    onEditRule(rule)
                                },
                                onDelete: {
                                    onDeleteRule(rule)
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    }

                    // MARK: - App-Specific Sections

                    ForEach(appKeymaps) { keymap in
                        AppRulesSectionHeader(keymap: keymap)
                            .padding(.horizontal, 16)
                            .padding(.top, rules.isEmpty ? 0 : 8)

                        ForEach(keymap.overrides) { override in
                            AppRuleRow(
                                keymap: keymap,
                                override: override,
                                onDelete: {
                                    onDeleteAppRule(keymap, override)
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Custom Rule Row

struct CustomRuleRow: View {
    let rule: CustomRule
    let onToggle: (Bool) -> Void
    let onEditInDrawer: () -> Void
    let onDelete: () -> Void

    /// Extract app identifier from push-msg launch output
    private var appLaunchIdentifier: String? {
        KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: rule.output)
    }

    /// Extract system action identifier from push-msg output
    private var systemActionIdentifier: String? {
        // Look for (push-msg "system:ACTION_NAME") pattern
        let pattern = #"\(push-msg\s+"system:([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: rule.output, range: NSRange(rule.output.startIndex..., in: rule.output)),
              let actionRange = Range(match.range(at: 1), in: rule.output)
        else {
            return nil
        }
        return String(rule.output[actionRange])
    }

    /// Extract URL from push-msg open output
    private var urlIdentifier: String? {
        KeyboardVisualizationViewModel.extractUrlIdentifier(from: rule.output)
    }

    /// Extract layer name from layer-switch output
    private var layerSwitchIdentifier: String? {
        LayerInfo.extractLayerName(from: rule.output)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.displayTitle)
                        .font(.headline)

                    HStack(spacing: 8) {
                        KeyCapChip(text: rule.input)
                        Text("→")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Show appropriate chip based on action type
                        if let appId = appLaunchIdentifier {
                            AppLaunchChip(appIdentifier: appId)
                        } else if let actionId = systemActionIdentifier {
                            SystemActionChip(actionIdentifier: actionId)
                        } else if let urlId = urlIdentifier {
                            URLChip(urlString: urlId)
                        } else if let layerName = layerSwitchIdentifier {
                            LayerSwitchChip(layerName: layerName)
                        } else {
                            KeyCapChip(text: rule.output)
                        }

                        // Behavior summary on same line
                        if let behavior = rule.behavior {
                            behaviorSummaryView(behavior: behavior)
                        }

                        Spacer(minLength: 0)
                    }

                    if let notes = rule.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { onToggle($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("custom-rules-toggle-\(rule.id)")
                .accessibilityLabel("Toggle \(rule.displayTitle)")

                Menu {
                    Button("Edit in Drawer") { onEditInDrawer() }
                        .accessibilityIdentifier("custom-rules-menu-edit-drawer-button-\(rule.id)")
                        .accessibilityLabel("Edit rule in drawer")
                    Button("Delete", role: .destructive) { onDelete() }
                        .accessibilityIdentifier("custom-rules-menu-delete-button-\(rule.id)")
                        .accessibilityLabel("Delete rule")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .padding(.leading, 4)
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("custom-rules-menu-\(rule.id)")
                .accessibilityLabel("Rule options menu")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
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
