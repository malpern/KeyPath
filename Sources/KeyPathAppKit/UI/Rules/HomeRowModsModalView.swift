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

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @State private var localConfig: HomeRowModsConfig

    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    init(config: Binding<HomeRowModsConfig>, onSave: @escaping (HomeRowModsConfig) -> Void, onCancel: @escaping () -> Void, initialSelectedKey: String? = nil) {
        _config = config
        self.onSave = onSave
        self.onCancel = onCancel
        self.initialSelectedKey = initialSelectedKey
        _localConfig = State(initialValue: config.wrappedValue)
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
                    holdModeSection
                    preferencesSection
                    timingSection
                }
                .padding(.top, 16)
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
    }

    private var holdModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hold Action")
                .font(.headline)

            Picker("Hold Action", selection: Binding(
                get: { localConfig.holdMode },
                set: { localConfig.holdMode = $0 }
            )) {
                Text("Modifiers").tag(HomeRowHoldMode.modifiers)
                Text("Layers").tag(HomeRowHoldMode.layers)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("home-row-mods-modal-hold-mode-picker")
            .accessibilityLabel("Hold action mode")
        }
        .padding(.horizontal)
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Defaults")
                .font(.headline)

            if localConfig.holdMode == .modifiers {
                Picker("Preset", selection: Binding(
                    get: { modifierPresetSelection(from: localConfig.modifierAssignments) },
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
                    Text("Mac (CAGS: Cmd on index)").tag(HomeRowModifierPreset.macCAGS)
                    Text("Windows/Linux (GACS)").tag(HomeRowModifierPreset.winGACS)
                    Text("Custom").tag(HomeRowModifierPreset.custom)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home-row-mods-modal-preset-picker")
                .accessibilityLabel("Modifier preset selection")
            } else {
                Picker("Layer Preset", selection: Binding(
                    get: { layerPresetSelection(from: localConfig.layerAssignments) },
                    set: { preset in
                        switch preset {
                        case .default:
                            localConfig.layerAssignments = HomeRowModsConfig.defaultLayerAssignments
                        case .custom:
                            break
                        }
                    }
                )) {
                    Text("Default (num, sys1, sys2, nav)").tag(HomeRowLayerPreset.default)
                    Text("Custom").tag(HomeRowLayerPreset.custom)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home-row-mods-modal-layer-preset-picker")
                .accessibilityLabel("Layer preset selection")

                Picker("Layer Mode", selection: Binding(
                    get: { localConfig.layerToggleMode },
                    set: { localConfig.layerToggleMode = $0 }
                )) {
                    Text(LayerToggleMode.whileHeld.displayName).tag(LayerToggleMode.whileHeld)
                    Text(LayerToggleMode.toggle.displayName).tag(LayerToggleMode.toggle)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .accessibilityIdentifier("home-row-mods-modal-layer-toggle-mode-picker")
                .accessibilityLabel("Layer activation mode")
            }
        }
        .padding(.horizontal)
    }

    private var timingSection: some View {
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
                                    Text(displayLabel(forCanonicalKey: key))
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
                    .accessibilityIdentifier("home-row-mods-hold-preset-picker")
                    .accessibilityLabel("Hold preset")

                    ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(displayLabel(forCanonicalKey: key))
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

    private func displayLabel(forCanonicalKey key: String) -> String {
        guard let keyCode = LogicalKeymap.keyCode(forQwertyLabel: key),
              let label = activeKeymap.label(for: keyCode, includeExtraKeys: false)
        else {
            return key.uppercased()
        }
        return label.uppercased()
    }
}

// MARK: - Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}

private enum HomeRowModifierPreset: Hashable {
    case macCAGS
    case winGACS
    case custom
}

private enum HomeRowLayerPreset: Hashable {
    case `default`
    case custom
}

private func modifierPresetSelection(from assignments: [String: String]) -> HomeRowModifierPreset {
    if assignments == HomeRowModsConfig.cagsMacDefault { return .macCAGS }
    if assignments == HomeRowModsConfig.gacsWindows { return .winGACS }
    return .custom
}

private func layerPresetSelection(from assignments: [String: String]) -> HomeRowLayerPreset {
    if assignments == HomeRowModsConfig.defaultLayerAssignments { return .default }
    return .custom
}
