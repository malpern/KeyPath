import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Modal dialog for Home Row Mods customization
struct HomeRowModsModalView: View {
    @Binding var config: HomeRowModsConfig
    let onSave: (HomeRowModsConfig) -> Void
    let onCancel: () -> Void
    let initialSelectedKey: String?

    @State private var localConfig: HomeRowModsConfig
    @State private var selectedKey: String?
    @State private var showModifierPicker = false

    init(config: Binding<HomeRowModsConfig>, onSave: @escaping (HomeRowModsConfig) -> Void, onCancel: @escaping () -> Void, initialSelectedKey: String? = nil) {
        _config = config
        self.onSave = onSave
        self.onCancel = onCancel
        self.initialSelectedKey = initialSelectedKey
        _localConfig = State(initialValue: config.wrappedValue)
        _selectedKey = State(initialValue: initialSelectedKey)
        _showModifierPicker = State(initialValue: initialSelectedKey != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Customize Home Row Mods")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-row-mods-modal-close-button")
                .accessibilityLabel("Close")
            }
            .padding()

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // Visual keyboard
                    HomeRowKeyboardView(
                        enabledKeys: localConfig.enabledKeys,
                        modifierAssignments: localConfig.modifierAssignments,
                        selectedKey: selectedKey,
                        onKeySelected: { key in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedKey = selectedKey == key ? nil : key
                                showModifierPicker = selectedKey != nil
                            }
                        }
                    )
                    .padding(.top, 16)
                    .padding(.horizontal)

                    // Key selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Which keys?")
                            .font(.headline)

                        Picker("Preset", selection: Binding(
                            get: { presetSelection(from: localConfig.modifierAssignments) },
                            set: { preset in
                                switch preset {
                                case .macCAGS:
                                    localConfig.modifierAssignments = HomeRowModsConfig.cagsMacDefault
                                case .winGACS:
                                    localConfig.modifierAssignments = HomeRowModsConfig.gacsWindows
                                case .custom:
                                    break
                                }
                            }
                        )) {
                            Text("Mac (CAGS: Cmd on index)").tag(HomeRowPreset.macCAGS)
                            Text("Windows/Linux (GACS)").tag(HomeRowPreset.winGACS)
                            Text("Custom").tag(HomeRowPreset.custom)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("home-row-mods-modal-preset-picker")
                        .accessibilityLabel("Preset selection")

                        Picker("Key Selection", selection: Binding(
                            get: { localConfig.keySelection },
                            set: { newValue in
                                localConfig.keySelection = newValue
                                localConfig.enabledKeys = newValue.enabledKeys
                            }
                        )) {
                            Text("Both hands").tag(KeySelection.both)
                            Text("Left hand only").tag(KeySelection.leftOnly)
                            Text("Right hand only").tag(KeySelection.rightOnly)
                            Text("Custom").tag(KeySelection.custom)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                        .accessibilityIdentifier("home-row-mods-modal-key-selection-picker")
                        .accessibilityLabel("Key selection")

                        // Custom key picker (appears contextually)
                        if localConfig.keySelection == .custom {
                            customKeyPicker
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal)

                    // Timing controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timing")
                            .font(.headline)

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tap window")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("", value: Binding(
                                        get: { localConfig.timing.tapWindow },
                                        set: { localConfig.timing.tapWindow = $0 }
                                    ), format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("ms")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hold delay")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("", value: Binding(
                                        get: { localConfig.timing.holdDelay },
                                        set: { localConfig.timing.holdDelay = $0 }
                                    ), format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("ms")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Toggle("Favor tap when another key is pressed (quick tap)", isOn: Binding(
                            get: { localConfig.timing.quickTapEnabled },
                            set: { localConfig.timing.quickTapEnabled = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("home-row-mods-modal-quick-tap-toggle")
                        .accessibilityLabel("Favor tap when another key is pressed")

                        HStack {
                            Text("Quick tap term")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { Double(localConfig.timing.quickTapTermMs) },
                                set: { localConfig.timing.quickTapTermMs = Int($0) }
                            ), in: 0 ... 80, step: 5)
                            Text(String(localized: "\(localConfig.timing.quickTapTermMs) ms"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .disabled(!localConfig.timing.quickTapEnabled)

                        Toggle("Show per-key timing offsets", isOn: Binding(
                            get: { localConfig.showAdvanced },
                            set: { localConfig.showAdvanced = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("home-row-mods-modal-show-advanced-toggle")
                        .accessibilityLabel("Show per-key timing offsets")

                        if localConfig.showAdvanced {
                            VStack(alignment: .leading, spacing: 12) {
                                Divider().padding(.vertical, 4)

                                Text("Per-Key Tap Offsets")
                                    .font(.subheadline)
                                    .fontWeight(.bold)

                                ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                                    HStack(spacing: 12) {
                                        ForEach(row, id: \.self) { key in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(key.uppercased())
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                TextField("0", value: Binding(
                                                    get: { localConfig.timing.tapOffsets[key] ?? 0 },
                                                    set: { newValue in
                                                        if newValue == 0 {
                                                            localConfig.timing.tapOffsets.removeValue(forKey: key)
                                                        } else {
                                                            localConfig.timing.tapOffsets[key] = newValue
                                                        }
                                                    }
                                                ), format: .number)
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 70)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                Text("Extends tap window for a key (e.g., `50` makes it easier to tap). Leave blank or `0` for default.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Divider().padding(.vertical, 4)

                                Text("Per-Key Hold Offsets")
                                    .font(.subheadline)
                                    .fontWeight(.bold)

                                Picker("Hold Preset", selection: holdPresetBinding) {
                                    Text("Standard").tag(HoldPreset.standard)
                                    Text("Slow Pinkies").tag(HoldPreset.slowPinkies)
                                    Text("Custom").tag(HoldPreset.custom)
                                }
                                .pickerStyle(.segmented)
                                .padding(.bottom, 4)

                                ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                                    HStack(spacing: 12) {
                                        ForEach(row, id: \.self) { key in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(key.uppercased())
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                TextField("0", value: Binding(
                                                    get: { localConfig.timing.holdOffsets[key] ?? 0 },
                                                    set: { newValue in
                                                        if newValue == 0 {
                                                            localConfig.timing.holdOffsets.removeValue(forKey: key)
                                                        } else {
                                                            localConfig.timing.holdOffsets[key] = newValue
                                                        }
                                                    }
                                                ), format: .number)
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 70)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                Text("Extends hold delay for a key (e.g., `50` makes it easier to hold). Leave blank or `0` for default.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal)

                    // Modifier picker (contextual, appears when key is selected)
                    if showModifierPicker, let selectedKey {
                        modifierPickerSection(for: selectedKey)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.bottom, 24)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("home-row-mods-modal-cancel-button")
                    .accessibilityLabel("Cancel")
                Button("Save", action: {
                    onSave(localConfig)
                })
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-row-mods-modal-save-button")
                .accessibilityLabel("Save")
            }
            .padding()
        }
        .frame(width: 750, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: showModifierPicker)
        .onAppear {
            // Set initial selection when view appears (State init doesn't always work in SwiftUI)
            if let key = initialSelectedKey {
                selectedKey = key
                showModifierPicker = true
            }
        }
    }

    // MARK: - Custom Key Picker

    private var customKeyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select keys:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(HomeRowModsConfig.allKeys, id: \.self) { key in
                    Button(action: {
                        if localConfig.enabledKeys.contains(key) {
                            localConfig.enabledKeys.remove(key)
                        } else {
                            localConfig.enabledKeys.insert(key)
                        }
                    }) {
                        Text(key.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(localConfig.enabledKeys.contains(key) ? .white : .primary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(localConfig.enabledKeys.contains(key) ? .accentColor : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-row-mods-modal-key-button-\(key)")
                    .accessibilityLabel("Toggle key \(key.uppercased())")
                }
            }
        }
    }

    // MARK: - Modifier Picker

    private func modifierPickerSection(for key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Modifier for \"\(key.uppercased())\":")
                    .font(.headline)
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedKey = nil
                        showModifierPicker = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-row-mods-modal-modifier-picker-close-button")
                .accessibilityLabel("Close modifier picker")
            }

            HStack(spacing: 12) {
                ForEach(modifierOptions, id: \.key) { option in
                    modifierButton(
                        label: option.label,
                        symbol: option.symbol,
                        isSelected: localConfig.modifierAssignments[key] == option.key,
                        action: {
                            localConfig.modifierAssignments[key] = option.key
                        }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    private var modifierOptions: [(key: String, label: String, symbol: String)] {
        [
            ("lmet", "Command", "⌘"),
            ("lalt", "Option", "⌥"),
            ("lctl", "Control", "⌃"),
            ("lsft", "Shift", "⇧")
        ]
    }

    private func modifierButton(label: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? .accentColor : Color(NSColor.controlBackgroundColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? .accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-row-mods-modal-modifier-button-\(label.lowercased())")
        .accessibilityLabel("Select \(label) modifier")
    }

    private enum HoldPreset {
        case standard, slowPinkies, custom
    }

    private var holdPresetBinding: Binding<HoldPreset> {
        Binding(
            get: {
                if localConfig.timing.holdOffsets.isEmpty {
                    .standard
                } else if localConfig.timing.holdOffsets == ["a": 50, ";": 50] {
                    .slowPinkies
                } else {
                    .custom
                }
            },
            set: { preset in
                switch preset {
                case .standard:
                    localConfig.timing.holdOffsets = [:]
                case .slowPinkies:
                    localConfig.timing.holdOffsets = ["a": 50, ";": 50]
                case .custom:
                    // When user selects custom, we don't change the values,
                    // allowing them to create their own custom configuration.
                    break
                }
            }
        )
    }
}

// MARK: - Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}

private enum HomeRowPreset: Hashable {
    case macCAGS
    case winGACS
    case custom
}

private func presetSelection(from assignments: [String: String]) -> HomeRowPreset {
    if assignments == HomeRowModsConfig.cagsMacDefault { return .macCAGS }
    if assignments == HomeRowModsConfig.gacsWindows { return .winGACS }
    return .custom
}
