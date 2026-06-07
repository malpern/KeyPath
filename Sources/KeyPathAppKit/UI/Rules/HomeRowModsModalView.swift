import KeyPathCore
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
            Text("Customize home row mods")
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .accessibilityIdentifier("home-row-mods-modal")
                .accessibilityLabel("Customize home row mods")
                .accessibilityValue(homeRowModsAccessibilityValue)

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
                    hrmExplainer
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
                    AppLogger.shared.log("🧪 [QA] Home Row Mods modal saved: \(homeRowModsAccessibilityValue)")
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
            MarkdownHelpSheet(resource: "home-row-mods", title: "Home Row Mods")
        }
    }

    private var hrmExplainer: some View {
        DisclosureGroup("What are home row mods?") {
            Text("Home row mods turn your home row keys (A S D F / J K L ;) into dual-role keys: tap for the letter, hold for a modifier like Shift or Command.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .accessibilityIdentifier("home-row-mods-explainer-disclosure")
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
            .accessibilityValue(localConfig.holdMode.displayName)
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
                .accessibilityValue(modifierPresetAccessibilityValue)
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
                .accessibilityValue(layerPresetAccessibilityValue)

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
                .accessibilityValue(localConfig.layerToggleMode.displayName)
            }
        }
        .padding(.horizontal)
    }

    private var timingSection: some View {
        HomeRowTimingSection(config: $localConfig, showsHrmInsights: true) { newConfig in
            localConfig = newConfig
        }
        .padding(.horizontal)
    }

    private var homeRowModsAccessibilityValue: String {
        let enabledKeys = localConfig.enabledKeys.sorted().joined(separator: ",")
        return "mode \(localConfig.holdMode.displayName), layer activation \(localConfig.layerToggleMode.displayName), enabled keys \(enabledKeys), tap window \(localConfig.timing.tapWindow) ms, hold delay \(localConfig.timing.holdDelay) ms, opposite hand \(localConfig.oppositeHandMode.displayName)"
    }

    private var modifierPresetAccessibilityValue: String {
        switch modifierPresetSelection(from: localConfig.modifierAssignments) {
        case .macCAGS: "Mac CAGS"
        case .winGACS: "Windows Linux GACS"
        case .custom: "Custom"
        }
    }

    private var layerPresetAccessibilityValue: String {
        switch layerPresetSelection(from: localConfig.layerAssignments) {
        case .default: "Default"
        case .custom: "Custom"
        }
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
