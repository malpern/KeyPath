import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Modal dialog for Home Row Layer Toggles customization
struct HomeRowLayerTogglesModalView: View {
    @Binding var config: HomeRowLayerTogglesConfig
    let onSave: (HomeRowLayerTogglesConfig) -> Void
    let onCancel: () -> Void
    let initialSelectedKey: String?

    @State private var localConfig: HomeRowLayerTogglesConfig
    @State private var selectedKey: String?
    @State private var showLayerPicker = false

    init(config: Binding<HomeRowLayerTogglesConfig>, onSave: @escaping (HomeRowLayerTogglesConfig) -> Void, onCancel: @escaping () -> Void, initialSelectedKey: String? = nil) {
        _config = config
        self.onSave = onSave
        self.onCancel = onCancel
        self.initialSelectedKey = initialSelectedKey
        _localConfig = State(initialValue: config.wrappedValue)
        _selectedKey = State(initialValue: initialSelectedKey)
        _showLayerPicker = State(initialValue: initialSelectedKey != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Customize Home Row Layer Toggles")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-row-layer-toggles-modal-close-button")
                .accessibilityLabel("Close")
            }
            .padding()

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 24) {
                    // Visual keyboard
                    HomeRowKeyboardView(
                        enabledKeys: localConfig.enabledKeys,
                        modifierAssignments: localConfig.layerAssignments,
                        selectedKey: selectedKey,
                        onKeySelected: { key in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedKey = selectedKey == key ? nil : key
                                showLayerPicker = selectedKey != nil
                            }
                        }
                    )
                    .padding(.top, 16)
                    .padding(.horizontal)

                    // Layer toggle mode
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Layer Toggle Mode")
                            .font(.headline)

                        Picker("Mode", selection: Binding(
                            get: { localConfig.toggleMode },
                            set: { localConfig.toggleMode = $0 }
                        )) {
                            Text(LayerToggleMode.whileHeld.displayName).tag(LayerToggleMode.whileHeld)
                            Text(LayerToggleMode.toggle.displayName).tag(LayerToggleMode.toggle)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                        .accessibilityIdentifier("home-row-layer-toggles-modal-mode-picker")
                        .accessibilityLabel("Layer toggle mode")

                        Text(localConfig.toggleMode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Key selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Which keys?")
                            .font(.headline)

                        Picker("Preset", selection: Binding(
                            get: { presetSelection(from: localConfig.layerAssignments) },
                            set: { preset in
                                switch preset {
                                case .default:
                                    localConfig.layerAssignments = HomeRowLayerTogglesConfig.defaultLayerAssignments
                                case .custom:
                                    break
                                }
                            }
                        )) {
                            Text("Default (num, sys1, sys2, nav)").tag(HomeRowLayerPreset.default)
                            Text("Custom").tag(HomeRowLayerPreset.custom)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("home-row-layer-toggles-modal-preset-picker")
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
                        .accessibilityIdentifier("home-row-layer-toggles-modal-key-selection-picker")
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
                        .accessibilityIdentifier("home-row-layer-toggles-modal-quick-tap-toggle")
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
                        .accessibilityIdentifier("home-row-layer-toggles-modal-show-advanced-toggle")
                        .accessibilityLabel("Show per-key timing offsets")

                        if localConfig.showAdvanced {
                            VStack(alignment: .leading, spacing: 12) {
                                Divider().padding(.vertical, 4)

                                Text("Per-Key Tap Offsets")
                                    .font(.subheadline)
                                    .fontWeight(.bold)

                                ForEach(chunks(of: HomeRowLayerTogglesConfig.allKeys, size: 4), id: \.self) { row in
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

                                ForEach(chunks(of: HomeRowLayerTogglesConfig.allKeys, size: 4), id: \.self) { row in
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

                    // Layer picker (contextual, appears when key is selected)
                    if showLayerPicker, let selectedKey {
                        layerPickerSection(for: selectedKey)
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
                    .accessibilityIdentifier("home-row-layer-toggles-modal-cancel-button")
                    .accessibilityLabel("Cancel")
                Button("Save", action: {
                    onSave(localConfig)
                })
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-row-layer-toggles-modal-save-button")
                .accessibilityLabel("Save")
            }
            .padding()
        }
        .frame(width: 750, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: showLayerPicker)
        .onAppear {
            // Set initial selection when view appears (State init doesn't always work in SwiftUI)
            if let key = initialSelectedKey {
                selectedKey = key
                showLayerPicker = true
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
                ForEach(HomeRowLayerTogglesConfig.allKeys, id: \.self) { key in
                    Button {
                        if localConfig.enabledKeys.contains(key) {
                            localConfig.enabledKeys.remove(key)
                        } else {
                            localConfig.enabledKeys.insert(key)
                        }
                    } label: {
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
                    .accessibilityIdentifier("home-row-layer-toggles-modal-key-button-\(key)")
                    .accessibilityLabel("Toggle key \(key.uppercased())")
                }
            }
        }
    }

    // MARK: - Layer Picker

    private func layerPickerSection(for key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Layer for \"\(key.uppercased())\":")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedKey = nil
                        showLayerPicker = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-row-layer-toggles-modal-layer-picker-close-button")
                .accessibilityLabel("Close layer picker")
            }

            HStack(spacing: 12) {
                ForEach(layerOptions, id: \.key) { option in
                    layerButton(
                        label: option.label,
                        icon: option.icon,
                        isSelected: localConfig.layerAssignments[key] == option.key,
                        action: {
                            localConfig.layerAssignments[key] = option.key
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

    private var layerOptions: [(key: String, label: String, icon: String)] {
        [
            ("num", "Numpad", "keyboard"),
            ("sys1", "System 1", "command"),
            ("sys2", "System 2", "option"),
            ("nav", "Navigation", "arrow.up.arrow.down")
        ]
    }

    private func layerButton(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
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
        .accessibilityIdentifier("home-row-layer-toggles-modal-layer-button-\(label.lowercased())")
        .accessibilityLabel("Select \(label) layer")
    }
}

// MARK: - Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}

private enum HomeRowLayerPreset: Hashable {
    case `default`
    case custom
}

private func presetSelection(from assignments: [String: String]) -> HomeRowLayerPreset {
    if assignments == HomeRowLayerTogglesConfig.defaultLayerAssignments { return .default }
    return .custom
}
