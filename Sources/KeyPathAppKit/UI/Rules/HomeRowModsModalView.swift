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
    @State private var showHelp = false

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
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-row-mods-help-button")
                .accessibilityLabel("Home Row Mods Help")
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
        .sheet(isPresented: $showHelp) {
            MarkdownHelpSheet(resource: "home-row-mods-guide", title: "Home Row Mods Guide")
        }
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
                    Text("Default (fun, num, sym, nav)").tag(HomeRowLayerPreset.default)
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
        HomeRowTimingSection(config: $localConfig) { newConfig in
            localConfig = newConfig
        }
        .padding(.horizontal)
    }
}

// MARK: - Helpers

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
