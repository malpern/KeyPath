import SwiftUI

// MARK: - Custom Key Popover

struct CustomKeyPopover: View {
    @Binding var keyInput: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showingSuggestions = false
    @FocusState private var isInputFocused: Bool

    private var suggestions: [String] {
        CustomRuleValidator.suggestions(for: keyInput).prefix(8).map { $0 }
    }

    private var isValidKey: Bool {
        let normalized = CustomRuleValidator.normalizeKey(keyInput)
        return CustomRuleValidator.isValidKey(normalized)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Custom Key")
                .font(.headline)

            // Key input with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                TextField("Key name (e.g., tab, grv)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        if isValidKey {
                            onConfirm()
                        }
                    }
                    .onChange(of: keyInput) { _, newValue in
                        showingSuggestions = !newValue.isEmpty
                    }

                // Autocomplete suggestions
                if showingSuggestions, !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    keyInput = suggestion
                                    showingSuggestions = false
                                } label: {
                                    Text(suggestion)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .clipShape(.rect(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 28)
                }

                // Validation feedback
                if !keyInput.isEmpty, !isValidKey {
                    Text("Unknown key name")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("OK") {
                    onConfirm()
                }
                .keyboardShortcut(.return)
                .disabled(!isValidKey)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            isInputFocused = true
        }
    }
}
