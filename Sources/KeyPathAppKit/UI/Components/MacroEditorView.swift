import SwiftUI

/// Editor for macro behavior - key sequence or text expansion.
struct MacroEditorView: View {
    @Binding var macro: MacroBehavior?
    @Binding var isRecordingKeys: Bool
    let onRecordKeys: () -> Void
    var showsRecordButton: Bool = true

    @State private var editMode: MacroEditMode = .text

    enum MacroEditMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case keys = "Keys"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $editMode) {
                ForEach(MacroEditMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("macro-editor-mode-picker")

            if editMode == .text {
                textExpansionEditor
            } else {
                keySequenceEditor
            }

            if let error = macro?.validationErrors.first {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("macro-editor-error")
            }
        }
        .onAppear {
            syncModeFromMacro()
        }
        .onChange(of: macro?.source) { _, _ in
            syncModeFromMacro()
        }
        .onChange(of: editMode) { _, newValue in
            updateMacroSource(newValue)
        }
    }

    private var textExpansionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type text to expand:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("e.g., hello@example.com", text: textBinding)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("macro-editor-text-field")
        }
    }

    private var keySequenceEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Record key sequence:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("e.g., M-c v", text: outputsBinding)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("macro-editor-keys-field")

            HStack(spacing: 8) {
                Text(keySequenceDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if showsRecordButton {
                    Button {
                        onRecordKeys()
                    } label: {
                        Image(systemName: isRecordingKeys ? "stop.fill" : "record.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("macro-editor-record-button")
                }

                Button {
                    macro = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("macro-editor-clear-button")
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: {
                macro?.text ?? ""
            },
            set: { newValue in
                var updated = macro ?? MacroBehavior()
                updated.text = newValue
                updated.source = .text
                macro = updated
            }
        )
    }

    private var keySequenceDisplay: String {
        let outputs = macro?.outputs ?? []
        if outputs.isEmpty {
            return "Not configured"
        }
        return outputs.joined(separator: " ")
    }

    private var outputsBinding: Binding<String> {
        Binding(
            get: {
                (macro?.outputs ?? []).joined(separator: " ")
            },
            set: { newValue in
                var updated = macro ?? MacroBehavior()
                updated.outputs = newValue
                    .split(separator: " ")
                    .map { String($0) }
                updated.source = .keys
                macro = updated
            }
        )
    }

    private func syncModeFromMacro() {
        if macro?.source == .keys {
            editMode = .keys
        } else {
            editMode = .text
        }
    }

    private func updateMacroSource(_ mode: MacroEditMode) {
        guard var existing = macro else {
            macro = MacroBehavior(source: mode == .text ? .text : .keys)
            return
        }
        existing.source = mode == .text ? .text : .keys
        macro = existing
    }
}
