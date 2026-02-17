import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Main view for Home Row Mods collection with progressive disclosure
struct HomeRowModsCollectionView: View {
    @Binding var config: HomeRowModsConfig
    let availableLayers: [String]
    let onConfigChanged: (HomeRowModsConfig) -> Void
    let onEnsureLayersExist: ([String]) async -> Void

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @State private var showingCustomizeWindow = false
    @State private var selectedKey: String?
    @State private var showingLayerModeSetup = false
    @State private var showingNewLayerSheet = false
    @State private var newLayerName = ""
    @State private var locallyCreatedLayers: Set<String> = []
    @State private var hoveredHoldBehavior: HomeRowHoldMode?
    @State private var pendingLayerModeChoice: LayerModeDialogChoice = .useLayersRecommended

    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    private var homeRowDisplayLabels: [String: String] {
        Dictionary(uniqueKeysWithValues: HomeRowModsConfig.allKeys.map { key in
            (key, displayLabel(forCanonicalKey: key))
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Key Mapping")
                    .font(.body.weight(.semibold))
                Text(keyMappingInstructionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)

            // Visual keyboard (always visible when expanded)
            ViewThatFits(in: .horizontal) {
                homeRowKeyboard(size: 72)
                homeRowKeyboard(size: 68)
                homeRowKeyboard(size: 64)
                homeRowKeyboard(size: 60)
                homeRowKeyboard(size: 56)
                homeRowKeyboard(size: 52)
                homeRowKeyboard(size: 48)
            }
            .padding(.bottom, 16)

            HStack {
                Spacer()

                Button("Settings...") {
                    showingCustomizeWindow = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("home-row-mods-customize-button")
                .accessibilityLabel("Home row mods settings")
            }

        }
        .animation(.easeInOut(duration: 0.2), value: selectedKey)
        .onAppear {
            normalizeLegacyLayerModeIfNeeded()
        }
        .sheet(isPresented: $showingCustomizeWindow) {
            customizeWindowContent
        }
    }

    // MARK: - Customize Section

    private var customizeWindowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Home Row Preferences")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") {
                    showingCustomizeWindow = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                customizeSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .settingsBackground()
        .sheet(isPresented: $showingLayerModeSetup) {
            layerModeSetupSheet
        }
        .sheet(isPresented: $showingNewLayerSheet) {
            newLayerSheet
        }
    }

    @ViewBuilder
    private func homeRowKeyboard(size: CGFloat) -> some View {
        HomeRowKeyboardView(
            enabledKeys: config.enabledKeys,
            modifierAssignments: activeHoldAssignments,
            holdMode: config.holdMode,
            selectedKey: selectedKey,
            keyDisplayLabels: homeRowDisplayLabels,
            helperText: config.holdMode == .modifiers ? "Tap for letter, hold for modifier" : "Tap for letter, hold for layer",
            keyChipSize: size,
            keyPopoverContent: { key in
                AnyView(
                    Group {
                        if config.holdMode == .layers {
                            layerPopoverContent(for: key)
                        } else {
                            modifierPopoverContent(for: key)
                        }
                    }
                )
            },
            onPopoverDismiss: {
                selectedKey = nil
            },
            onKeySelected: { key in
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedKey = selectedKey == key ? nil : key
                }
            }
        )
    }

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("These settings control what your home-row keys do when you hold them. Tap still types letters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Hold Behavior")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    holdBehaviorOptionCard(
                        mode: .modifiers,
                        icon: "command",
                        title: "Modifiers",
                        subtitle: "Recommended"
                    )

                    holdBehaviorOptionCard(
                        mode: .layers,
                        icon: "square.stack.3d.up",
                        title: "Layers",
                        subtitle: "Advanced"
                    )
                }
                .accessibilityIdentifier("home-row-mods-hold-mode-picker")
                .accessibilityLabel("Hold action mode")

                Text(holdBehaviorExplanationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(config.holdMode == .modifiers ? "Modifier Preset" : "Layer Preset")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if config.holdMode == .modifiers {
                    HStack(spacing: 10) {
                        SettingsOptionCard(
                            icon: "applelogo",
                            title: "Mac (CAGS)",
                            subtitle: "Command on index keys",
                            isSelected: modifierPresetSelection(from: config.modifierAssignments) == .macCAGS
                        ) {
                            config.modifierAssignments = HomeRowModsConfig.cagsMacDefault
                            config.enabledKeys = Set(HomeRowModsConfig.allKeys)
                            updateConfig()
                        }
                        .accessibilityIdentifier("home-row-mods-preset-mac-cags")

                        SettingsOptionCard(
                            icon: "desktopcomputer",
                            title: "Windows (GACS)",
                            subtitle: "GUI on pinky keys",
                            isSelected: modifierPresetSelection(from: config.modifierAssignments) == .winGACS
                        ) {
                            config.modifierAssignments = HomeRowModsConfig.gacsWindows
                            config.enabledKeys = Set(HomeRowModsConfig.allKeys)
                            updateConfig()
                        }
                        .accessibilityIdentifier("home-row-mods-preset-windows-gacs")

                        SettingsOptionCard(
                            icon: "slider.horizontal.3",
                            title: "Custom",
                            subtitle: "Choose per-key manually",
                            isSelected: modifierPresetSelection(from: config.modifierAssignments) == .custom
                        ) {
                            // Keep existing assignments; user edits per key on the keyboard.
                        }
                        .accessibilityIdentifier("home-row-mods-preset-custom")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home-row-mods-preset-picker")
                    .accessibilityLabel("Modifier preset selection")

                    Text(modifierPresetExplanationText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Layer Preset")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            SettingsOptionCard(
                                icon: "sparkles",
                                title: "Recommended",
                                subtitle: "Balanced left/right defaults",
                                isSelected: layerPresetSelection(from: config.layerAssignments) == .default
                            ) {
                                applyLayerPreset(.default)
                            }
                            .accessibilityIdentifier("home-row-mods-layer-preset-recommended")

                            SettingsOptionCard(
                                icon: "slider.horizontal.3",
                                title: "Custom",
                                subtitle: "Use your current assignments",
                                isSelected: layerPresetSelection(from: config.layerAssignments) == .custom
                            ) {
                                applyLayerPreset(.custom)
                            }
                            .accessibilityIdentifier("home-row-mods-layer-preset-custom")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home-row-mods-layer-preset-picker")
                        .accessibilityLabel("Layer preset selection")

                        Text(layerPresetExplanationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Layer Activation")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            SettingsOptionCard(
                                icon: "hand.raised",
                                title: "While Held",
                                subtitle: "Active only while holding",
                                isSelected: config.layerToggleMode == .whileHeld
                            ) {
                                config.layerToggleMode = .whileHeld
                                updateConfig()
                            }
                            .accessibilityIdentifier("home-row-mods-layer-toggle-while-held")

                            SettingsOptionCard(
                                icon: "switch.2",
                                title: "Toggle",
                                subtitle: "Press once to stay on",
                                isSelected: config.layerToggleMode == .toggle
                            ) {
                                config.layerToggleMode = .toggle
                                updateConfig()
                            }
                            .accessibilityIdentifier("home-row-mods-layer-toggle-mode")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home-row-mods-layer-toggle-mode-picker")
                        .accessibilityLabel("Layer activation mode")

                        Text(layerActivationExplanationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Active Keys")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Choose which home-row keys use tap-hold behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    SettingsOptionCard(
                        icon: "hands.sparkles",
                        title: "Both Hands",
                        subtitle: "All 8 home-row keys",
                        isSelected: config.keySelection == .both
                    ) {
                        applyKeySelection(.both)
                    }
                    .accessibilityIdentifier("home-row-mods-key-selection-both")

                    SettingsOptionCard(
                        icon: "hand.point.left.fill",
                        title: "Left Only",
                        subtitle: "A S D F",
                        isSelected: config.keySelection == .leftOnly
                    ) {
                        applyKeySelection(.leftOnly)
                    }
                    .accessibilityIdentifier("home-row-mods-key-selection-left")

                    SettingsOptionCard(
                        icon: "hand.point.right.fill",
                        title: "Right Only",
                        subtitle: "J K L ;",
                        isSelected: config.keySelection == .rightOnly
                    ) {
                        applyKeySelection(.rightOnly)
                    }
                    .accessibilityIdentifier("home-row-mods-key-selection-right")

                    SettingsOptionCard(
                        icon: "slider.horizontal.3",
                        title: "Custom",
                        subtitle: "Pick individual keys",
                        isSelected: config.keySelection == .custom
                    ) {
                        applyKeySelection(.custom)
                    }
                    .accessibilityIdentifier("home-row-mods-key-selection-custom")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home-row-mods-key-selection-picker")
                .accessibilityLabel("Key selection")

                Text(keySelectionExplanationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if config.keySelection == .custom {
                    customKeyPicker
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Timing")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Defaults usually work. Adjust only if you get accidental holds or missed holds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                .accessibilityIdentifier("home-row-mods-quick-tap-toggle")
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

                Toggle("Show advanced per-finger timing", isOn: Binding(
                    get: { config.showAdvanced },
                    set: { newValue in
                        config.showAdvanced = newValue
                        updateConfig()
                    }
                ))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("home-row-mods-show-advanced-toggle")
                .accessibilityLabel("Show advanced per-finger timing")

                if config.showAdvanced {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(timingEducationText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Use small values first (10-30ms). Set 0 to use global timing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)

                        Text("Per-finger tap offsets (ms)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(displayLabel(forCanonicalKey: key))
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
                        Text("Positive values extend tap window for that finger/key.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Text("Per-finger hold offsets (ms)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Toggle("Use pinky-friendly hold defaults", isOn: pinkyDefaultsBinding)
                            .toggleStyle(.checkbox)
                            .disabled(isCustomHoldOffsets)
                            .accessibilityIdentifier("home-row-mods-pinky-defaults-toggle")
                            .accessibilityLabel("Use pinky-friendly hold defaults")

                        if isCustomHoldOffsets {
                            HStack(spacing: 8) {
                                Text("Manual per-key overrides are active.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("Reset to standard") {
                                    config.timing.holdOffsets = [:]
                                    updateConfig()
                                }
                                .buttonStyle(.link)
                                .accessibilityIdentifier("home-row-mods-reset-hold-offsets-button")
                                .accessibilityLabel("Reset per-key hold offsets to standard")
                            }
                        }

                        ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(displayLabel(forCanonicalKey: key))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("0", value: Binding(
                                            get: { config.timing.holdOffsets[key] ?? 0 },
                                            set: { newValue in
                                                if newValue == 0 {
                                                    config.timing.holdOffsets.removeValue(forKey: key)
                                                } else {
                                                    config.timing.holdOffsets[key] = newValue
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
                        Text("Positive values extend hold delay for that finger/key.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
                        if config.enabledKeys.contains(key) {
                            config.enabledKeys.remove(key)
                        } else {
                            config.enabledKeys.insert(key)
                        }
                        updateConfig()
                    }) {
                        Text(displayLabel(forCanonicalKey: key))
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
                    .accessibilityIdentifier("home-row-mods-key-button-\(key)")
                    .accessibilityLabel("Toggle key \(displayLabel(forCanonicalKey: key))")
                }
            }
        }
    }

    // MARK: - Assignment Popovers

    private var modifierOptions: [(kind: String, label: String, symbol: String)] {
        [
            ("met", "Command", "⌘"),
            ("alt", "Option", "⌥"),
            ("ctl", "Control", "⌃"),
            ("sft", "Shift", "⇧")
        ]
    }

    private func modifierPopoverContent(for key: String) -> some View {
        VStack(spacing: 0) {
            ForEach(modifierOptions.indices, id: \.self) { index in
                let option = modifierOptions[index]
                Button {
                    config.modifierAssignments[key] = sidedModifierAssignment(for: key, kind: option.kind)
                    updateConfig()
                    selectedKey = nil
                } label: {
                    HStack(spacing: 10) {
                        Text(option.symbol)
                            .font(.body.weight(.semibold))
                            .frame(width: 20)
                            .foregroundStyle(isModifierOptionSelected(option.kind, for: key) ? Color.accentColor : .secondary)
                        Text(option.label)
                            .font(.body)
                        Spacer()
                        if isModifierOptionSelected(option.kind, for: key) {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)
                .accessibilityIdentifier("home-row-mods-modifier-option-\(option.kind)")
                .accessibilityLabel("Set \(displayLabel(forCanonicalKey: key)) to \(option.symbol) \(option.label)")

                if index < modifierOptions.count - 1 {
                    PopoverListDivider()
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 210)
        .pickerPopoverChrome()
    }

    private func layerPopoverContent(for key: String) -> some View {
        VStack(spacing: 0) {
            ForEach(layerOptions.indices, id: \.self) { index in
                let option = layerOptions[index]
                Button {
                    config.layerAssignments[key] = option.key
                    updateConfig()
                    selectedKey = nil
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: option.icon)
                            .font(.body)
                            .frame(width: 20)
                            .foregroundStyle(config.layerAssignments[key] == option.key ? Color.accentColor : .secondary)
                        Text(option.label)
                            .font(.body)
                        Spacer()
                        if config.layerAssignments[key] == option.key {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LayerPickerItemButtonStyle())
                .focusable(false)
                .accessibilityIdentifier("home-row-mods-layer-option-\(option.key)")
                .accessibilityLabel("Set \(displayLabel(forCanonicalKey: key)) to \(option.label) layer")

                if index < layerOptions.count - 1 {
                    PopoverListDivider()
                }
            }

            PopoverListDivider()

            Button {
                showingNewLayerSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("home-row-mods-layer-option-new")
            .accessibilityLabel("Create a new layer")
        }
        .padding(.vertical, 6)
        .frame(minWidth: 210)
        .pickerPopoverChrome()
    }

    private var layerOptions: [(key: String, label: String, icon: String)] {
        let options = availableLayerNames.map { layer in
            (key: layer, label: LayerInfo.displayName(for: layer), icon: LayerInfo.iconName(for: layer))
        }
        assert(
            options.allSatisfy { knownAvailableLayerNames.contains($0.key.lowercased()) },
            "Home row layer options must only include existing (or just-created) layers."
        )
        return options
    }

    // MARK: - Helpers

    private func updateConfig() {
        onConfigChanged(config)
    }

    private var activeHoldAssignments: [String: String] {
        config.holdMode == .modifiers ? config.modifierAssignments : config.layerAssignments
    }

    private func displayLabel(forCanonicalKey key: String) -> String {
        guard let keyCode = LogicalKeymap.keyCode(forQwertyLabel: key),
              let label = activeKeymap.label(for: keyCode, includeExtraKeys: false)
        else {
            return key.uppercased()
        }
        return label.uppercased()
    }

    private var keyMappingInstructionText: String {
        if config.holdMode == .layers {
            return "Click a key to choose its layer."
        }
        return "Click a key to choose its modifier."
    }

    private var knownAvailableLayerNames: Set<String> {
        Set(
            availableLayers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        ).union(
            locallyCreatedLayers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private var availableLayerNames: [String] {
        let names = Array(knownAvailableLayerNames).sorted()
        assert(Set(names.map { $0.lowercased() }) == knownAvailableLayerNames, "Layer names should be normalized.")
        return names
    }

    private var recommendedLayerNames: [String] {
        ["num", "sys1", "sys2", "nav"]
    }

    private var recommendedLayerAssignments: [String: String] {
        let left = recommendedLayerNames
        return [
            "a": left[0], "s": left[1], "d": left[2], "f": left[3],
            "j": left[3], "k": left[2], "l": left[1], ";": left[0]
        ]
    }

    private var missingRecommendedLayers: [String] {
        let existing = Set(availableLayerNames.map { $0.lowercased() })
        let needed = Set(recommendedLayerNames.map { $0.lowercased() })
        return needed.filter { !existing.contains($0) }.sorted()
    }

    private var layerModeSetupSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Home Row Layer Mode")
                .font(.title3.weight(.semibold))

            Text("Tap still types letters. Hold temporarily switches to a layer for navigation, symbols, or numpad.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Use Modifiers for shortcut-heavy workflows. Use Layers for larger key layouts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if !missingRecommendedLayers.isEmpty {
                Text("Recommended layers that will be created: \(missingRecommendedLayers.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                SettingsOptionCard(
                    icon: "command",
                    title: "Keep Modifiers",
                    subtitle: "Best for shortcuts",
                    isSelected: pendingLayerModeChoice == .keepModifiers
                ) {
                    pendingLayerModeChoice = .keepModifiers
                }
                .accessibilityIdentifier("home-row-mods-layer-setup-keep-modifiers")

                SettingsOptionCard(
                    icon: "sparkles",
                    title: "Use Layers (Recommended)",
                    subtitle: "Best for expanded layouts",
                    isSelected: pendingLayerModeChoice == .useLayersRecommended
                ) {
                    pendingLayerModeChoice = .useLayersRecommended
                }
                .accessibilityIdentifier("home-row-mods-layer-setup-use-layers-recommended")

                SettingsOptionCard(
                    icon: "slider.horizontal.3",
                    title: "Use Layers (Manual)",
                    subtitle: "Keep existing layers",
                    isSelected: pendingLayerModeChoice == .useLayersManual
                ) {
                    pendingLayerModeChoice = .useLayersManual
                }
                .accessibilityIdentifier("home-row-mods-layer-setup-use-layers-manual")
            }
            .padding(.top, 2)

            HStack {
                Spacer()
                Button("Cancel") {
                    showingLayerModeSetup = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("home-row-mods-layer-setup-cancel-button")

                Button("OK") {
                    switch pendingLayerModeChoice {
                    case .keepModifiers:
                        applyHoldMode(.modifiers)
                        showingLayerModeSetup = false
                    case .useLayersRecommended:
                        Task {
                            if !missingRecommendedLayers.isEmpty {
                                await onEnsureLayersExist(missingRecommendedLayers)
                                locallyCreatedLayers.formUnion(missingRecommendedLayers.map { $0.lowercased() })
                            }
                            config.layerAssignments = recommendedLayerAssignments
                            applyHoldMode(.layers)
                            showingLayerModeSetup = false
                        }
                    case .useLayersManual:
                        applyManualLayerModeWithoutCreating()
                        showingLayerModeSetup = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("home-row-mods-layer-setup-ok-button")
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 560)
        .settingsBackground()
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

    private enum LayerModeDialogChoice {
        case keepModifiers
        case useLayersRecommended
        case useLayersManual
    }

    private func modifierPresetSelection(from assignments: [String: String]) -> HomeRowModifierPreset {
        if assignments == HomeRowModsConfig.cagsMacDefault { return .macCAGS }
        if assignments == HomeRowModsConfig.gacsWindows { return .winGACS }
        return .custom
    }

    private func normalizeLegacyLayerModeIfNeeded() {
        guard config.holdMode == .layers, config.hasUserSelectedHoldMode == false else { return }
        config.holdMode = .modifiers
        selectedKey = nil
        updateConfig()
    }

    private func applyHoldMode(_ mode: HomeRowHoldMode) {
        config.holdMode = mode
        config.hasUserSelectedHoldMode = true
        selectedKey = nil
        updateConfig()
    }

    private func openLayerModeDialog() {
        if config.holdMode == .layers {
            pendingLayerModeChoice = layerPresetSelection(from: config.layerAssignments) == .default
                ? .useLayersRecommended : .useLayersManual
        } else {
            pendingLayerModeChoice = .useLayersRecommended
        }
        showingLayerModeSetup = true
    }

    private func applyKeySelection(_ selection: KeySelection) {
        config.keySelection = selection
        if selection == .custom {
            if config.enabledKeys.isEmpty {
                config.enabledKeys = Set(HomeRowModsConfig.allKeys)
            }
        } else {
            config.enabledKeys = selection.enabledKeys
        }
        updateConfig()
    }

    private func applyLayerPreset(_ preset: HomeRowLayerPreset) {
        switch preset {
        case .default:
            config.layerAssignments = recommendedLayerAssignments
            config.enabledKeys = Set(HomeRowModsConfig.allKeys)
        case .custom:
            break
        }
        updateConfig()
    }

    @ViewBuilder
    private func holdBehaviorOptionCard(
        mode: HomeRowHoldMode,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = config.holdMode == mode
        let isHovered = hoveredHoldBehavior == mode

        Button {
            if mode == .layers {
                openLayerModeDialog()
                return
            }
            applyHoldMode(mode)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle((isSelected || isHovered) ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight((isSelected || isHovered) ? .semibold : .regular))
                        .foregroundStyle((isSelected || isHovered) ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((isSelected || isHovered) ? Color.accentColor.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        (isSelected || isHovered) ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: (isSelected || isHovered) ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            hoveredHoldBehavior = hovering ? mode : (hoveredHoldBehavior == mode ? nil : hoveredHoldBehavior)
        }
        .accessibilityIdentifier(
            mode == .modifiers ? "home-row-mods-hold-mode-modifiers" : "home-row-mods-hold-mode-layers"
        )
    }

    private var holdBehaviorExplanationText: String {
        switch hoveredHoldBehavior ?? config.holdMode {
        case .modifiers:
            "Best for shortcuts and general app use. Hold a home-row key to get Cmd/Opt/Ctrl/Shift."
        case .layers:
            "Best for advanced layouts. Hold a home-row key to temporarily access another key layer."
        }
    }

    private var modifierPresetExplanationText: String {
        switch modifierPresetSelection(from: config.modifierAssignments) {
        case .macCAGS:
            "Mac default: index fingers get Command for common shortcuts."
        case .winGACS:
            "Windows/Linux default: pinkies get GUI/Super to match common workflows."
        case .custom:
            "Custom preset active. Click keys in the keyboard preview to assign modifiers."
        }
    }

    private var keySelectionExplanationText: String {
        switch config.keySelection {
        case .both:
            "Uses all home-row keys on both hands."
        case .leftOnly:
            "Only left-hand home-row keys use tap-hold behavior."
        case .rightOnly:
            "Only right-hand home-row keys use tap-hold behavior."
        case .custom:
            "Choose exactly which keys are active below."
        }
    }

    private var layerPresetExplanationText: String {
        switch layerPresetSelection(from: config.layerAssignments) {
        case .default:
            "Recommended preset is active. Home-row keys map to a symmetric layer layout."
        case .custom:
            "Custom preset is active. Click a key in the keyboard preview to choose its layer."
        }
    }

    private var layerActivationExplanationText: String {
        switch config.layerToggleMode {
        case .whileHeld:
            "Momentary mode: layer turns off when you release the key."
        case .toggle:
            "Latch mode: layer stays active until you switch it off."
        }
    }

    private func layerPresetSelection(from assignments: [String: String]) -> HomeRowLayerPreset {
        if assignments == recommendedLayerAssignments { return .default }
        return .custom
    }

    private func applyManualLayerModeWithoutCreating() {
        let existing = Set(availableLayerNames.map { $0.lowercased() })
        var sanitized: [String: String] = [:]

        for key in HomeRowModsConfig.allKeys {
            guard let assigned = config.layerAssignments[key], existing.contains(assigned.lowercased()) else { continue }
            sanitized[key] = assigned
        }

        if sanitized.isEmpty, let fallback = availableLayerNames.first {
            for key in HomeRowModsConfig.allKeys {
                sanitized[key] = fallback
            }
        }

        config.layerAssignments = sanitized
        applyHoldMode(.layers)
    }

    private var newLayerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create New Layer")
                .font(.title3.weight(.semibold))

            TextField("Layer name", text: $newLayerName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("home-row-mods-new-layer-name")

            HStack {
                Spacer()
                Button("Cancel") {
                    newLayerName = ""
                    showingNewLayerSheet = false
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("home-row-mods-new-layer-cancel-button")

                Button("Create") {
                    Task {
                        let raw = newLayerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        guard !raw.isEmpty else { return }
                        await onEnsureLayersExist([raw])
                        locallyCreatedLayers.insert(raw)
                        if let selectedKey {
                            config.layerAssignments[selectedKey] = raw
                            updateConfig()
                        }
                        newLayerName = ""
                        showingNewLayerSheet = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newLayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("home-row-mods-new-layer-create-button")
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var timingEducationText: String {
        if config.holdMode == .layers {
            return "Layer holds are sensitive to finger roll speed. People often add extra hold delay on pinkies/ring fingers to avoid accidental layer switches while typing."
        }
        return "Modifier holds are sensitive to finger speed too. People often add extra hold delay on pinkies/ring fingers to avoid accidental modifiers during normal typing."
    }

    private var pinkyDefaultsBinding: Binding<Bool> {
        Binding(
            get: { config.timing.holdOffsets == ["a": 50, ";": 50] },
            set: { isEnabled in
                if isEnabled {
                    config.timing.holdOffsets = ["a": 50, ";": 50]
                } else {
                    config.timing.holdOffsets = [:]
                }
                updateConfig()
            }
        )
    }

    private var isCustomHoldOffsets: Bool {
        let offsets = config.timing.holdOffsets
        return !offsets.isEmpty && offsets != ["a": 50, ";": 50]
    }

    private func isModifierOptionSelected(_ kind: String, for key: String) -> Bool {
        guard let assignment = config.modifierAssignments[key] else { return false }
        return canonicalModifierKind(from: assignment) == kind
    }

    private func sidedModifierAssignment(for key: String, kind: String) -> String {
        let isRightHand = HomeRowModsConfig.rightHandKeys.contains(key)
        return (isRightHand ? "r" : "l") + kind
    }

    private func canonicalModifierKind(from assignment: String) -> String {
        guard assignment.count == 4 else { return assignment }
        if assignment.hasPrefix("l") || assignment.hasPrefix("r") {
            return String(assignment.dropFirst())
        }
        return assignment
    }
}

// MARK: - Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}
