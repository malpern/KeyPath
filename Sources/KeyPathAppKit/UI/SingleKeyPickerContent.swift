import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct SingleKeyPickerContent: View {
    let collection: RuleCollection
    let onSelectOutput: (String) -> Void

    @State private var selectedOutput: String
    @State private var showingCustomPopover = false
    @State private var customKeyInput = ""

    private var config: SingleKeyPickerConfig? {
        collection.configuration.singleKeyPickerConfig
    }

    init(collection: RuleCollection, onSelectOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectOutput = onSelectOutput
        let cfg = collection.configuration.singleKeyPickerConfig
        _selectedOutput = State(initialValue: cfg?.selectedOutput ?? cfg?.presetOptions.first?.output ?? "")
    }

    private var selectedPreset: SingleKeyPreset? {
        config?.presetOptions.first { $0.output == selectedOutput }
    }

    private var isCustomSelection: Bool {
        guard let cfg = config else { return false }
        return !cfg.presetOptions.contains { $0.output == selectedOutput }
            && !selectedOutput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Segmented picker
            HStack(spacing: 0) {
                ForEach(config?.presetOptions ?? []) { preset in
                    PickerSegment(
                        label: preset.label,
                        isSelected: selectedOutput == preset.output,
                        isFirst: preset.id == config?.presetOptions.first?.id,
                        isLast: preset.id == config?.presetOptions.last?.id && !isCustomSelection
                    ) {
                        selectedOutput = preset.output
                        onSelectOutput(preset.output)
                    }
                }

                // Custom segment with popover
                PickerSegment(
                    label: "Custom",
                    isSelected: isCustomSelection,
                    isFirst: false,
                    isLast: true
                ) {
                    customKeyInput = isCustomSelection ? selectedOutput : ""
                    showingCustomPopover = true
                }
                .popover(isPresented: $showingCustomPopover, arrowEdge: .bottom) {
                    CustomKeyPopover(
                        keyInput: $customKeyInput,
                        onConfirm: {
                            let normalized = CustomRuleValidator.normalizeKey(customKeyInput)
                            if CustomRuleValidator.isValidKey(normalized) {
                                selectedOutput = normalized
                                onSelectOutput(normalized)
                            }
                            showingCustomPopover = false
                        },
                        onCancel: {
                            showingCustomPopover = false
                        }
                    )
                }
            }
            .padding(.horizontal, 4)

            // Description that updates based on selection
            if let preset = selectedPreset {
                Text(preset.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                    .id(preset.output)
            } else if isCustomSelection {
                HStack {
                    Text("Custom key: \(selectedOutput)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Edit") {
                        customKeyInput = selectedOutput
                        showingCustomPopover = true
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                    .accessibilityIdentifier("rules-summary-custom-key-edit-button")
                    .accessibilityLabel("Edit custom key")
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: selectedOutput)
    }
}
