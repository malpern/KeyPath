import KeyPathCore
import SwiftUI

// MARK: - Tap-Hold Picker Content

struct TapHoldPickerContent: View {
    let collection: RuleCollection
    let onSelectTapOutput: (String) -> Void
    let onSelectHoldOutput: (String) -> Void

    @State private var selectedTap: String
    @State private var selectedHold: String
    @State private var showingCustomTapPopover = false
    @State private var showingCustomHoldPopover = false
    @State private var customTapInput = ""
    @State private var customHoldInput = ""

    init(collection: RuleCollection, onSelectTapOutput: @escaping (String) -> Void, onSelectHoldOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectTapOutput = onSelectTapOutput
        self.onSelectHoldOutput = onSelectHoldOutput
        let tapOptions = collection.tapHoldOptions?.tapOptions ?? []
        let holdOptions = collection.tapHoldOptions?.holdOptions ?? []
        _selectedTap = State(initialValue: collection.selectedTapOutput ?? tapOptions.first?.output ?? "esc")
        _selectedHold = State(initialValue: collection.selectedHoldOutput ?? holdOptions.first?.output ?? "hyper")
    }

    private var tapOptions: [SingleKeyPreset] {
        collection.tapHoldOptions?.tapOptions ?? []
    }

    private var holdOptions: [SingleKeyPreset] {
        collection.tapHoldOptions?.holdOptions ?? []
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

    /// Check if caps lock is "lost" (not available via tap or hold)
    private var capsLockLost: Bool {
        selectedTap != "caps" && selectedHold != "caps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // TAP section
            VStack(alignment: .leading, spacing: 8) {
                Text("TAP")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    ForEach(tapOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedTap == preset.output,
                            isFirst: preset.id == tapOptions.first?.id,
                            isLast: preset.id == tapOptions.last?.id && !isCustomTapSelection
                        ) {
                            selectedTap = preset.output
                            onSelectTapOutput(preset.output)
                        }
                    }

                    PickerSegment(
                        label: "Custom",
                        isSelected: isCustomTapSelection,
                        isFirst: false,
                        isLast: true
                    ) {
                        customTapInput = isCustomTapSelection ? selectedTap : ""
                        showingCustomTapPopover = true
                    }
                    .popover(isPresented: $showingCustomTapPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customTapInput,
                            onConfirm: {
                                let normalized = CustomRuleValidator.normalizeKey(customTapInput)
                                if CustomRuleValidator.isValidKey(normalized) {
                                    selectedTap = normalized
                                    onSelectTapOutput(normalized)
                                }
                                showingCustomTapPopover = false
                            },
                            onCancel: {
                                showingCustomTapPopover = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)

                if let preset = selectedTapPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            // HOLD section
            VStack(alignment: .leading, spacing: 8) {
                Text("HOLD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    ForEach(holdOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedHold == preset.output,
                            isFirst: preset.id == holdOptions.first?.id,
                            isLast: preset.id == holdOptions.last?.id && !isCustomHoldSelection
                        ) {
                            selectedHold = preset.output
                            onSelectHoldOutput(preset.output)
                        }
                    }

                    PickerSegment(
                        label: "Custom",
                        isSelected: isCustomHoldSelection,
                        isFirst: false,
                        isLast: true
                    ) {
                        customHoldInput = isCustomHoldSelection ? selectedHold : ""
                        showingCustomHoldPopover = true
                    }
                    .popover(isPresented: $showingCustomHoldPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customHoldInput,
                            onConfirm: {
                                let normalized = CustomRuleValidator.normalizeKey(customHoldInput)
                                if CustomRuleValidator.isValidKey(normalized) {
                                    selectedHold = normalized
                                    onSelectHoldOutput(normalized)
                                }
                                showingCustomHoldPopover = false
                            },
                            onCancel: {
                                showingCustomHoldPopover = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)

                if let preset = selectedHoldPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            // Suggestion: Lost Caps Lock
            if capsLockLost {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Lost Caps Lock? Enable \"Backup Caps Lock\" to get it back via Both Shifts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.1))
                )
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: selectedTap)
        .animation(.easeInOut(duration: 0.15), value: selectedHold)
    }
}
