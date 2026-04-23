import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct TapHoldPickerContent: View {
    /// Preset options + initial selection. Nil renders an empty shell.
    /// Decoupled from `RuleCollection` so Gallery's Pack Detail (and any
    /// future caller) can construct a config directly without fabricating
    /// a collection wrapper.
    let config: TapHoldPickerConfig?
    /// When true, selection callbacks still fire but the picker's own
    /// `@State` still tracks the selection — mounts outside Rules that want
    /// a live editor wired to external persistence can opt in as they land.
    let isEditable: Bool
    let onSelectTapOutput: (String) -> Void
    let onSelectHoldOutput: (String) -> Void

    @State private var selectedTap: String
    @State private var selectedHold: String
    @State private var showingCustomTapPopover = false
    @State private var showingCustomHoldPopover = false
    @State private var customTapInput = ""
    @State private var customHoldInput = ""

    init(
        config: TapHoldPickerConfig?,
        isEditable: Bool = true,
        onSelectTapOutput: @escaping (String) -> Void = { _ in },
        onSelectHoldOutput: @escaping (String) -> Void = { _ in }
    ) {
        self.config = config
        self.isEditable = isEditable
        self.onSelectTapOutput = onSelectTapOutput
        self.onSelectHoldOutput = onSelectHoldOutput
        let tapOptions = config?.tapOptions ?? []
        let holdOptions = config?.holdOptions ?? []
        _selectedTap = State(initialValue: config?.selectedTapOutput ?? tapOptions.first?.output ?? "hyper")
        _selectedHold = State(initialValue: config?.selectedHoldOutput ?? holdOptions.first?.output ?? "hyper")
    }

    private var tapOptions: [SingleKeyPreset] {
        config?.tapOptions ?? []
    }

    private var holdOptions: [SingleKeyPreset] {
        config?.holdOptions ?? []
    }

    private var selectedTapPreset: SingleKeyPreset? {
        tapOptions.first { $0.output == selectedTap }
    }

    private var selectedHoldPreset: SingleKeyPreset? {
        holdOptions.first { $0.output == selectedHold }
    }

    private var isCustomTapSelection: Bool {
        !tapOptions.contains { $0.output == selectedTap } && !selectedTap.isEmpty
    }

    private var isCustomHoldSelection: Bool {
        !holdOptions.contains { $0.output == selectedHold } && !selectedHold.isEmpty
    }

    /// Get display label for a custom tap selection (handles system actions)
    private var customTapDisplayLabel: String {
        displayLabelFor(selectedTap)
    }

    /// Get display label for a custom hold selection (handles system actions)
    private var customHoldDisplayLabel: String {
        displayLabelFor(selectedHold)
    }

    /// Get display label for a custom value (system action or key)
    private func displayLabelFor(_ value: String) -> String {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: value),
           let action = CustomRuleValidator.systemAction(for: actionId)
        {
            return action.name
        }
        return value
    }

    /// Get SF Symbol for a custom value if it's a system action
    private func sfSymbolFor(_ value: String) -> String? {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: value),
           let action = CustomRuleValidator.systemAction(for: actionId)
        {
            return action.sfSymbol
        }
        return nil
    }

    /// Check if caps lock is "lost" (not available via tap or hold)
    private var capsLockLost: Bool {
        selectedTap != "caps" && selectedHold != "caps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // TAP section
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(tapOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedTap == preset.output,
                            isFirst: false,
                            isLast: false
                        ) {
                            guard isEditable else { return }
                            selectedTap = preset.output
                            onSelectTapOutput(preset.output)
                        }
                    }

                    if isCustomTapSelection {
                        CustomValueSegment(
                            label: customTapDisplayLabel,
                            sfSymbol: sfSymbolFor(selectedTap),
                            isSelected: true,
                            isLast: false
                        ) {}
                    }

                    PickerSegment(
                        label: isCustomTapSelection ? "Edit" : "Custom",
                        isSelected: false,
                        isFirst: false,
                        isLast: false
                    ) {
                        customTapInput = isCustomTapSelection ? selectedTap : ""
                        showingCustomTapPopover = true
                    }
                    .popover(isPresented: $showingCustomTapPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customTapInput,
                            onConfirm: {
                                if CustomRuleValidator.isSystemActionOutput(customTapInput) {
                                    selectedTap = customTapInput
                                    onSelectTapOutput(customTapInput)
                                } else {
                                    let normalized = CustomRuleValidator.normalizeKey(customTapInput)
                                    if CustomRuleValidator.isValidKey(normalized) {
                                        selectedTap = normalized
                                        onSelectTapOutput(normalized)
                                    }
                                }
                                showingCustomTapPopover = false
                            },
                            onCancel: {
                                showingCustomTapPopover = false
                            }
                        )
                    }
                }

                if let preset = selectedTapPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()
                .padding(.vertical, 14)

            // HOLD section
            VStack(alignment: .leading, spacing: 8) {
                Text("Hold")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                FlowLayout(spacing: 6) {
                    ForEach(holdOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedHold == preset.output,
                            isFirst: false,
                            isLast: false
                        ) {
                            guard isEditable else { return }
                            selectedHold = preset.output
                            onSelectHoldOutput(preset.output)
                        }
                    }

                    if isCustomHoldSelection {
                        CustomValueSegment(
                            label: customHoldDisplayLabel,
                            sfSymbol: sfSymbolFor(selectedHold),
                            isSelected: true,
                            isLast: false
                        ) {}
                    }

                    PickerSegment(
                        label: isCustomHoldSelection ? "Edit" : "Custom",
                        isSelected: false,
                        isFirst: false,
                        isLast: false
                    ) {
                        customHoldInput = isCustomHoldSelection ? selectedHold : ""
                        showingCustomHoldPopover = true
                    }
                    .popover(isPresented: $showingCustomHoldPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customHoldInput,
                            onConfirm: {
                                if CustomRuleValidator.isSystemActionOutput(customHoldInput) {
                                    selectedHold = customHoldInput
                                    onSelectHoldOutput(customHoldInput)
                                } else {
                                    let normalized = CustomRuleValidator.normalizeKey(customHoldInput)
                                    if CustomRuleValidator.isValidKey(normalized) {
                                        selectedHold = normalized
                                        onSelectHoldOutput(normalized)
                                    }
                                }
                                showingCustomHoldPopover = false
                            },
                            onCancel: {
                                showingCustomHoldPopover = false
                            }
                        )
                    }
                }

                if let preset = selectedHoldPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Suggestion: Lost Caps Lock
            if capsLockLost {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Lost Caps Lock? Enable \"Backup Caps Lock\" to get it back via Both Shifts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.yellow.opacity(0.08))
                )
                .padding(.top, 16)
            }
        }
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.15), value: selectedTap)
        .animation(.easeInOut(duration: 0.15), value: selectedHold)
    }
}
