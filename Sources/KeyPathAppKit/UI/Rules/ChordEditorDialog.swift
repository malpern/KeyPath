import KeyPathRulesCore
import SwiftUI

// MARK: - Chord Editor Dialog

struct ChordEditorDialog: View {
    let chord: ChordDefinition
    let onSave: (ChordDefinition) -> Void
    let onCancel: () -> Void

    @State private var keys: [String]
    @State private var selectedAction: KeyAction
    @State private var description: String
    @State private var newKeyInput: String = ""
    @State private var outputMode: OutputMode
    @State private var customOutput: String = ""
    @State private var keyIDs: [UUID]

    enum OutputMode: String, CaseIterable {
        case keystroke = "Keystroke"
        case systemAction = "System"
        case appLaunch = "App"
        case custom = "Custom"
    }

    init(chord: ChordDefinition, onSave: @escaping (ChordDefinition) -> Void, onCancel: @escaping () -> Void) {
        self.chord = chord
        self.onSave = onSave
        self.onCancel = onCancel
        _keys = State(initialValue: chord.keys)
        _selectedAction = State(initialValue: chord.action)
        _description = State(initialValue: chord.description ?? "")
        _outputMode = State(initialValue: Self.modeFor(chord.action))
        _keyIDs = State(initialValue: chord.keys.map { _ in UUID() })
        _customOutput = State(initialValue: {
            if case let .rawKanata(expr) = chord.action { return expr }
            return ""
        }())
    }

    private static func modeFor(_ action: KeyAction) -> OutputMode {
        switch action {
        case .keystroke: .keystroke
        case .launchApp: .appLaunch
        case .systemAction: .systemAction
        case .rawKanata: .custom
        default: .keystroke
        }
    }

    private static let keycapText = KeyPathColors.keycapText
    private static let keycapBg = Color(white: 0.12)

    private var isValid: Bool {
        keys.filter { !$0.isEmpty }.count >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            keycapPreview
                .padding(.top, 24)
                .padding(.bottom, 16)

            VStack(spacing: 14) {
                // Keys
                HStack(alignment: .center) {
                    Text("Keys")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)

                    HStack(spacing: 4) {
                        ForEach(keyIDs, id: \.self) { id in
                            if let index = keyIDs.firstIndex(of: id), keys.indices.contains(index) {
                                let key = keys[index]

                                if !key.isEmpty {
                                    Button {
                                        keys.remove(at: index)
                                        keyIDs.remove(at: index)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text(key.uppercased())
                                                .font(.callout.weight(.semibold).monospaced())
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if keys.filter({ !$0.isEmpty }).count < 4 {
                            TextField("key", text: $newKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospaced())
                                .frame(width: 60)
                                .onSubmit {
                                    let trimmed = newKeyInput.trimmingCharacters(in: .whitespaces).lowercased()
                                    if !trimmed.isEmpty {
                                        keys = keys.filter { !$0.isEmpty }
                                        keyIDs = Array(keyIDs.prefix(keys.count))
                                        keys.append(trimmed)
                                        keyIDs.append(UUID())
                                        newKeyInput = ""
                                    }
                                }
                        }
                    }
                }

                // Output type picker
                HStack(alignment: .top) {
                    Text("Action")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $outputMode) {
                            ForEach(OutputMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        outputContent
                    }
                }

                // Note
                HStack(alignment: .firstTextBaseline) {
                    Text("Note")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)

                    TextField("Optional description", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("chord-editor-cancel")
                Spacer()
                Button("Save") {
                    let updated = ChordDefinition(
                        id: chord.id,
                        keys: keys.filter { !$0.isEmpty },
                        action: selectedAction,
                        description: description.isEmpty ? nil : description,
                        isEnabled: chord.isEnabled
                    )
                    onSave(updated)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .accessibilityIdentifier("chord-editor-save")
            }
            .padding(20)
        }
        .frame(width: 440, height: 460)
    }

    // MARK: - Output Content (switches on mode)

    @ViewBuilder
    private var outputContent: some View {
        switch outputMode {
        case .keystroke:
            KeystrokePresetGridView(
                selectedKey: { if case let .keystroke(k) = selectedAction { return k }; return nil }(),
                onSelect: { selectedAction = .keystroke(key: $0) }
            )

        case .systemAction:
            SystemActionGridView(
                groups: OutputActionGrouping.compact,
                selectedActionID: { if case let .systemAction(id) = selectedAction { return id }; return nil }(),
                style: .labelPill(),
                onSelect: { selectedAction = .systemAction(id: $0.id) }
            )

        case .appLaunch:
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter app name or bundle ID:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Safari", text: Binding(
                    get: {
                        if case let .launchApp(name, _) = selectedAction { return name }
                        return ""
                    },
                    set: { selectedAction = .launchApp(name: $0, bundleId: nil) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.body)
            }

        case .custom:
            VStack(alignment: .leading, spacing: 6) {
                Text("Kanata expression:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("C-x", text: $customOutput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onChange(of: customOutput) { _, newValue in
                        if !newValue.isEmpty {
                            selectedAction = .rawKanata(newValue)
                        }
                    }
            }
        }
    }

    // MARK: - Keycap Preview

    private var keycapPreview: some View {
        HStack(spacing: 10) {
            // Input keycaps
            HStack(spacing: 4) {
                let displayKeys = keys.filter { !$0.isEmpty }
                if displayKeys.isEmpty {
                    placeholderKeycap("?")
                    placeholderKeycap("?")
                } else {
                    ForEach(displayKeys, id: \.self) { key in
                        keycap(key.uppercased())
                    }
                }
            }

            Image(systemName: "arrow.right")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            // Output keycap
            keycap(selectedAction.commonDisplayInfo?.label ?? selectedAction.displayName)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold).monospaced())
            .foregroundStyle(Self.keycapText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.keycapBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
    }

    private func placeholderKeycap(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold).monospaced())
            .foregroundStyle(.secondary.opacity(0.4))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Self.keycapBg.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
            )
    }
}
