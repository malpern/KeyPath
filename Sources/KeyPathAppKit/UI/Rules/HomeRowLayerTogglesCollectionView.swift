import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Main view for Home Row Layer Toggles collection with progressive disclosure
struct HomeRowLayerTogglesCollectionView: View {
    @Binding var config: HomeRowLayerTogglesConfig
    let onConfigChanged: (HomeRowLayerTogglesConfig) -> Void

    @State private var showCustomize = false
    @State private var selectedKey: String?
    @State private var showLayerPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Visual keyboard (always visible when expanded)
            HomeRowKeyboardView(
                enabledKeys: config.enabledKeys,
                modifierAssignments: config.layerAssignments,
                selectedKey: selectedKey,
                onKeySelected: { key in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedKey = selectedKey == key ? nil : key
                        showLayerPicker = selectedKey != nil
                    }
                }
            )
            .padding(.bottom, 16)

            // Progressive disclosure: Customize section
            if showCustomize {
                customizeSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCustomize = true
                    }
                } label: {
                    HStack {
                        Text("Customize...")
                            .font(.body)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .accessibilityIdentifier("home-row-layer-toggles-customize-button")
                .accessibilityLabel("Customize home row layer toggles")
            }

            // Layer picker (contextual, appears when key is selected)
            if showLayerPicker, let selectedKey {
                layerPickerSection(for: selectedKey)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showCustomize)
        .animation(.easeInOut(duration: 0.2), value: showLayerPicker)
    }

    // MARK: - Customize Section

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Layer toggle mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Layer Toggle Mode")
                    .font(.body)

                Picker("Mode", selection: Binding(
                    get: { config.toggleMode },
                    set: { newValue in
                        config.toggleMode = newValue
                        updateConfig()
                    }
                )) {
                    Text(LayerToggleMode.whileHeld.displayName).tag(LayerToggleMode.whileHeld)
                    Text(LayerToggleMode.toggle.displayName).tag(LayerToggleMode.toggle)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .accessibilityIdentifier("home-row-layer-toggles-mode-picker")
                .accessibilityLabel("Layer toggle mode")

                Text(config.toggleMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Key selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Which keys?")
                    .font(.body)

                Picker("Preset", selection: Binding(
                    get: { presetSelection(from: config.layerAssignments) },
                    set: { preset in
                        switch preset {
                        case .default:
                            config.layerAssignments = HomeRowLayerTogglesConfig.defaultLayerAssignments
                            config.enabledKeys = Set(HomeRowLayerTogglesConfig.allKeys)
                        case .custom:
                            break
                        }
                        updateConfig()
                    }
                )) {
                    Text("Default (num, sys1, sys2, nav)").tag(HomeRowLayerPreset.default)
                    Text("Custom").tag(HomeRowLayerPreset.custom)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home-row-layer-toggles-preset-picker")
                .accessibilityLabel("Preset selection")

                Picker("Key Selection", selection: Binding(
                    get: { config.keySelection },
                    set: { newValue in
                        config.keySelection = newValue
                        config.enabledKeys = newValue.enabledKeys
                        updateConfig()
                    }
                )) {
                    Text("Both hands").tag(KeySelection.both)
                    Text("Left hand only").tag(KeySelection.leftOnly)
                    Text("Right hand only").tag(KeySelection.rightOnly)
                    Text("Custom").tag(KeySelection.custom)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .accessibilityIdentifier("home-row-layer-toggles-key-selection-picker")
                .accessibilityLabel("Key selection")

                // Custom key picker (appears contextually)
                if config.keySelection == .custom {
                    customKeyPicker
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Timing controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Timing")
                    .font(.body)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap window")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("", value: Binding(
                                get: { config.timing.tapWindow },
                                set: { newValue in
                                    config.timing.tapWindow = newValue
                                    updateConfig()
                                }
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
                                get: { config.timing.holdDelay },
                                set: { newValue in
                                    config.timing.holdDelay = newValue
                                    updateConfig()
                                }
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
                    get: { config.timing.quickTapEnabled },
                    set: { newValue in
                        config.timing.quickTapEnabled = newValue
                        updateConfig()
                    }
                ))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("home-row-layer-toggles-quick-tap-toggle")
                .accessibilityLabel("Favor tap when another key is pressed")

                HStack {
                    Text("Quick tap term")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { Double(config.timing.quickTapTermMs) },
                        set: { newValue in
                            config.timing.quickTapTermMs = Int(newValue)
                            updateConfig()
                        }
                    ), in: 0 ... 80, step: 5)
                    Text(String(localized: "\(config.timing.quickTapTermMs) ms"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .disabled(!config.timing.quickTapEnabled)

                Toggle("Show per-key tap offsets", isOn: Binding(
                    get: { config.showAdvanced },
                    set: { newValue in
                        config.showAdvanced = newValue
                        updateConfig()
                    }
                ))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("home-row-layer-toggles-show-advanced-toggle")
                .accessibilityLabel("Show per-key tap offsets")

                if config.showAdvanced {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Per-key tap offsets (ms)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(chunks(of: HomeRowLayerTogglesConfig.allKeys, size: 4), id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key.uppercased())
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("0", value: Binding(
                                            get: { config.timing.tapOffsets[key] ?? 0 },
                                            set: { newValue in
                                                if newValue == 0 {
                                                    config.timing.tapOffsets.removeValue(forKey: key)
                                                } else {
                                                    config.timing.tapOffsets[key] = newValue
                                                }
                                                updateConfig()
                                            }
                                        ), format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 70)
                                    }
                                }
                                Spacer()
                            }
                        }
                        Text("Positive values extend the tap window per key; leave 0 for default.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Fewer Options button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showCustomize = false
                    selectedKey = nil
                    showLayerPicker = false
                }
            } label: {
                HStack {
                    Text("Fewer Options")
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .accessibilityIdentifier("home-row-layer-toggles-fewer-options-button")
            .accessibilityLabel("Fewer options")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
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
                        if config.enabledKeys.contains(key) {
                            config.enabledKeys.remove(key)
                        } else {
                            config.enabledKeys.insert(key)
                        }
                        updateConfig()
                    } label: {
                        Text(key.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(config.enabledKeys.contains(key) ? .white : .primary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(config.enabledKeys.contains(key) ? .accentColor : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-row-layer-toggles-key-button-\(key)")
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
                    .font(.body)
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
                .accessibilityIdentifier("home-row-layer-toggles-layer-picker-close-button")
                .accessibilityLabel("Close layer picker")
            }

            HStack(spacing: 12) {
                ForEach(layerOptions, id: \.key) { option in
                    layerButton(
                        label: option.label,
                        icon: option.icon,
                        isSelected: config.layerAssignments[key] == option.key,
                        action: {
                            config.layerAssignments[key] = option.key
                            updateConfig()
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
        .accessibilityIdentifier("home-row-layer-toggles-layer-button-\(label.lowercased())")
        .accessibilityLabel("Select \(label) layer")
    }

    // MARK: - Helpers

    private func updateConfig() {
        onConfigChanged(config)
    }

    private enum HomeRowLayerPreset: Hashable {
        case `default`
        case custom
    }

    private func presetSelection(from assignments: [String: String]) -> HomeRowLayerPreset {
        if assignments == HomeRowLayerTogglesConfig.defaultLayerAssignments { return .default }
        return .custom
    }
}

// MARK: - Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}
