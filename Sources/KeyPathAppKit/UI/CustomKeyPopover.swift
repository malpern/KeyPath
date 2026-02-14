import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct CustomKeyPopover: View {
    @Binding var keyInput: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showingSuggestions = true
    @FocusState private var isInputFocused: Bool

    private var structuredSuggestions: [CustomRuleValidator.Suggestion] {
        Array(CustomRuleValidator.structuredSuggestions(for: keyInput).prefix(12))
    }

    private var isValidKey: Bool {
        // For system action outputs, they're already in the correct format
        if CustomRuleValidator.isSystemActionOutput(keyInput) {
            return true
        }
        let normalized = CustomRuleValidator.normalizeKey(keyInput)
        return CustomRuleValidator.isValidKey(normalized)
    }

    /// Display label for the current input (shows friendly name for system actions)
    private var displayLabel: String {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: keyInput),
           let action = CustomRuleValidator.systemAction(for: actionId)
        {
            return action.name
        }
        return keyInput
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Custom Key or Action")
                .font(.headline)

            // Key input with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                TextField("Key name or action (e.g., tab, Mission Control)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        if isValidKey {
                            onConfirm()
                        }
                    }
                    .onChange(of: keyInput) { _, _ in
                        showingSuggestions = true
                    }

                // Autocomplete suggestions with icons for system actions
                if showingSuggestions, !structuredSuggestions.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(structuredSuggestions.indices, id: \.self) { suggestionIndex in
                                let suggestion = structuredSuggestions[suggestionIndex]
                                Button {
                                    keyInput = suggestion.value
                                    showingSuggestions = false
                                } label: {
                                    HStack(spacing: 6) {
                                        if let symbol = suggestion.sfSymbol {
                                            Image(systemName: symbol)
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                                .frame(width: 16)
                                        }
                                        Text(suggestion.displayLabel)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.08))
                                    .clipShape(.rect(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                // Show friendly name when system action is selected
                if CustomRuleValidator.isSystemActionOutput(keyInput) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Action: \(displayLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                // Validation feedback for invalid input
                else if !keyInput.isEmpty, !isValidKey {
                    Text("Unknown key name")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("rules-summary-custom-key-cancel-button")
                .accessibilityLabel("Cancel")

                Spacer()

                Button("OK") {
                    onConfirm()
                }
                .keyboardShortcut(.return)
                .disabled(!isValidKey)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rules-summary-custom-key-ok-button")
                .accessibilityLabel("OK")
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            isInputFocused = true
        }
    }
}
