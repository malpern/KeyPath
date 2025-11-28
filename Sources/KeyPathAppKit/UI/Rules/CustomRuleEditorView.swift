import KeyPathCore
import SwiftUI

struct CustomRuleEditorView: View {
    enum Mode {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var input: String
    @State private var output: String
    @State private var notes: String
    @State private var isEnabled: Bool
    @State private var validationErrors: [CustomRuleValidator.ValidationError] = []
    @State private var inputSuggestions: [String] = []
    @State private var outputSuggestions: [String] = []
    @State private var currentTipIndex: Int = .random(in: 0 ..< 6)
    @FocusState private var inputFieldFocused: Bool
    @FocusState private var outputFieldFocused: Bool
    private let existingRule: CustomRule?
    private let existingRules: [CustomRule]
    private let mode: Mode
    let onSave: (CustomRule) -> Void

    init(
        rule: CustomRule?,
        existingRules: [CustomRule] = [],
        onSave: @escaping (CustomRule) -> Void
    ) {
        existingRule = rule
        self.existingRules = existingRules
        self.onSave = onSave
        if let rule {
            _title = State(initialValue: rule.title)
            _input = State(initialValue: rule.input)
            _output = State(initialValue: rule.output)
            _notes = State(initialValue: rule.notes ?? "")
            _isEnabled = State(initialValue: rule.isEnabled)
            mode = .edit
        } else {
            _title = State(initialValue: "")
            _input = State(initialValue: "")
            _output = State(initialValue: "")
            _notes = State(initialValue: "")
            _isEnabled = State(initialValue: true)
            mode = .create
        }
    }

    private var inputError: String? {
        validationErrors.compactMap { error in
            if case let .invalidInputKey(key) = error {
                if let suggestion = CustomRuleValidator.suggestCorrection(for: key) {
                    return "Invalid key '\(key)'. Did you mean '\(suggestion)'?"
                }
                return "Invalid key '\(key)'"
            }
            if case .emptyInput = error {
                return "Input key is required"
            }
            return nil
        }.first
    }

    private var outputError: String? {
        validationErrors.compactMap { error in
            if case let .invalidOutputKey(key) = error {
                if let suggestion = CustomRuleValidator.suggestCorrection(for: key) {
                    return "Invalid key '\(key)'. Did you mean '\(suggestion)'?"
                }
                return "Invalid key '\(key)'"
            }
            if case .emptyOutput = error {
                return "Output key is required"
            }
            return nil
        }.first
    }

    private var selfMappingError: String? {
        validationErrors.compactMap { error in
            if case .selfMapping = error {
                return "Input and output are the same (rule has no effect)"
            }
            return nil
        }.first
    }

    private var conflictError: String? {
        validationErrors.compactMap { error in
            if case let .conflict(name, key) = error {
                return "Conflicts with '\(name)' on key '\(key)'"
            }
            return nil
        }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create ? "New Custom Rule" : "Edit Custom Rule")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                TextField("Friendly name (optional)", text: $title)

                // Input key with inline autocomplete
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Input key (e.g. caps, esc, f18)", text: $input)
                        .focused($inputFieldFocused)
                        .onChange(of: input) { _, newValue in
                            updateInputSuggestions(for: newValue)
                            validationErrors.removeAll()
                        }
                        .onAppear {
                            updateInputSuggestions(for: input)
                        }

                    if inputFieldFocused {
                        inlineSuggestionsList(
                            suggestions: inputSuggestions,
                            currentValue: input,
                            onSelect: { suggestion in
                                input = suggestion
                                inputFieldFocused = false
                            }
                        )
                    }

                    if let error = inputError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Output key with inline autocomplete
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Output key or sequence (e.g. esc, M-right)", text: $output)
                        .focused($outputFieldFocused)
                        .onChange(of: output) { _, newValue in
                            updateOutputSuggestions(for: newValue)
                            validationErrors.removeAll()
                        }
                        .onAppear {
                            updateOutputSuggestions(for: output)
                        }

                    if outputFieldFocused {
                        inlineSuggestionsList(
                            suggestions: outputSuggestions,
                            currentValue: output.components(separatedBy: " ").last ?? "",
                            onSelect: { suggestion in
                                // For output, replace last token with suggestion
                                let tokens = CustomRuleValidator.tokenize(output)
                                if tokens.count > 1 {
                                    var newTokens = Array(tokens.dropLast())
                                    newTokens.append(suggestion)
                                    output = newTokens.joined(separator: " ")
                                } else {
                                    output = suggestion
                                }
                                // Keep focus for adding more keys
                            }
                        )

                        Text("Tip: Space-separate multiple keys (e.g. \"M-right M-left\")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let error = outputError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if let error = selfMappingError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if let error = conflictError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Toggle("Enabled", isOn: $isEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $notes)
                        .frame(height: 70)
                        .font(.body)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            }
            .textFieldStyle(.roundedBorder)

            Spacer()

            // Rotating tip
            RotatingTipView(currentIndex: $currentTipIndex)
                .padding(.bottom, 8)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(mode == .create ? "Add Rule" : "Save Changes") {
                    saveRule()
                }
                .disabled(
                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 400)
    }

    @ViewBuilder
    private func inlineSuggestionsList(
        suggestions: [String],
        currentValue: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let trimmedValue = currentValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredSuggestions = suggestions.filter { suggestion in
            trimmedValue.isEmpty || suggestion.hasPrefix(trimmedValue)
        }

        if !filteredSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !trimmedValue.isEmpty {
                    Text("Matching keys:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filteredSuggestions.prefix(20), id: \.self) { suggestion in
                            Button {
                                onSelect(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(suggestion == trimmedValue
                                                ? Color.accentColor.opacity(0.2)
                                                : Color.primary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                suggestion == trimmedValue
                                                    ? Color.accentColor
                                                    : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 28)

                if filteredSuggestions.count > 20 {
                    Text("+ \(filteredSuggestions.count - 20) more matches")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func updateInputSuggestions(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            inputSuggestions = CustomRuleValidator.commonKeys
        } else {
            inputSuggestions = CustomRuleValidator.suggestions(for: trimmed)
        }
    }

    private func updateOutputSuggestions(for text: String) {
        // For output, get suggestions for the last token (space-separated)
        let tokens = CustomRuleValidator.tokenize(text)
        let lastToken = tokens.last ?? ""
        if lastToken.isEmpty {
            outputSuggestions = CustomRuleValidator.commonKeys
        } else {
            outputSuggestions = CustomRuleValidator.suggestions(for: lastToken)
        }
    }

    private func saveRule() {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let rule = CustomRule(
            id: existingRule?.id ?? UUID(),
            title: title,
            input: trimmedInput,
            output: trimmedOutput,
            isEnabled: isEnabled,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: existingRule?.createdAt ?? Date()
        )

        // Validate the rule including conflict checking
        let errors = CustomRuleValidator.validate(rule, existingRules: existingRules)
        if !errors.isEmpty {
            validationErrors = errors
            return
        }

        onSave(rule)
        dismiss()
    }
}

// MARK: - Rotating Tip View

private struct RotatingTipView: View {
    @Binding var currentIndex: Int

    private static let tips: [(example: String, description: String)] = [
        ("M-right", "⌘→ moves cursor one word right"),
        ("C-S-a", "⌃⇧A selects all with Control+Shift+A"),
        ("A-bspc", "⌥⌫ deletes the previous word"),
        ("M-S-left M-S-left", "Chain keys: two ⌘⇧← for double word select"),
        ("f18", "F18 is a \"Hyper\" key for app shortcuts"),
        ("M-up", "⌘↑ jumps to document start")
    ]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundColor(.yellow.opacity(0.8))
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tip: ")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    +
                    Text(Self.tips[currentIndex].example)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundColor(.accentColor)
                    +
                    Text(" — \(Self.tips[currentIndex].description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentIndex = (currentIndex + 1) % Self.tips.count
                }
            } label: {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Next tip")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.08))
        )
    }
}
