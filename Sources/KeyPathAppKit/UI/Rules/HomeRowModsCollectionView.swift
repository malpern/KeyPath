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
    let onEnableLayerCollections: (([UUID]) async -> Void)?

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @State private var showingCustomizeWindow = false
    @State private var selectedKey: String?
    @State private var showingNewLayerSheet = false
    @State private var newLayerName = ""
    @State private var locallyCreatedLayers: Set<String> = []
    @State private var hoveredHoldBehavior: HomeRowHoldMode?
    @State private var hoveredLayerToggleMode: LayerToggleMode?
    @State private var showingHelp = false

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
            .padding(.bottom, 8)

            if hasCustomAssignments {
                Button {
                    resetAssignmentsToDefaults()
                } label: {
                    Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("home-row-mods-reset-defaults")
                .padding(.bottom, 8)
            }

            HStack {
                Spacer()

                Button("Settings...") {
                    showingCustomizeWindow = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("home-row-mods-customize-button")
                .accessibilityLabel("Home row mods settings")
            }
            .padding(.trailing, 10)
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

                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-row-mods-prefs-help-button")
                .accessibilityLabel("Home row mods help")

                Spacer()

                Button("Done") {
                    showingCustomizeWindow = false
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("home-row-mods-done-button")
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
        .sheet(isPresented: $showingNewLayerSheet) {
            newLayerSheet
        }
        .sheet(isPresented: $showingHelp) {
            MarkdownHelpSheet(resource: "home-row-mods", title: "Home Row Mods")
        }
    }

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
                Group {
                    if !config.enabledKeys.contains(key) {
                        enableKeyPopoverContent(for: key)
                    } else if config.holdMode == .layers {
                        layerPopoverContent(for: key)
                    } else {
                        modifierPopoverContent(for: key)
                    }
                }
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

            if config.holdMode == .layers {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Layer Activation")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        SettingsOptionCard(
                            icon: "hand.raised",
                            title: "While Held",
                            subtitle: "Active only while holding",
                            isSelected: config.layerToggleMode == .whileHeld,
                            onHoverChanged: { hovering in
                                hoveredLayerToggleMode = hovering ? .whileHeld : nil
                            }
                        ) {
                            config.layerToggleMode = .whileHeld
                            updateConfig()
                        }
                        .accessibilityIdentifier("home-row-mods-layer-toggle-while-held")

                        SettingsOptionCard(
                            icon: "switch.2",
                            title: "Toggle",
                            subtitle: "Press once to stay on",
                            isSelected: config.layerToggleMode == .toggle,
                            onHoverChanged: { hovering in
                                hoveredLayerToggleMode = hovering ? .toggle : nil
                            }
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

            Divider()

            HomeRowTimingSection(
                config: $config,
                showsHrmInsights: true,
                onConfigChanged: onConfigChanged
            )
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

            PopoverListDivider()

            disableKeyButton(for: key)
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

            disableKeyButton(for: key)

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

    private func enableKeyPopoverContent(for key: String) -> some View {
        VStack(spacing: 0) {
            Button {
                config.enabledKeys.insert(key)
                // Restore default assignment for this key's position
                if config.holdMode == .modifiers {
                    config.modifierAssignments[key] = HomeRowModsConfig.cagsMacDefault[key]
                } else {
                    config.layerAssignments[key] = HomeRowModsConfig.defaultLayerAssignments[key]
                }
                config.keySelection = .custom
                updateConfig()
                selectedKey = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 20)
                        .foregroundStyle(Color.accentColor)
                    Text("Enable Key")
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
            .accessibilityIdentifier("home-row-mods-enable-key-\(key)")
            .accessibilityLabel("Enable \(displayLabel(forCanonicalKey: key))")
        }
        .padding(.vertical, 6)
        .frame(minWidth: 210)
        .pickerPopoverChrome()
    }

    private func disableKeyButton(for key: String) -> some View {
        Button {
            config.enabledKeys.remove(key)
            config.keySelection = .custom
            updateConfig()
            selectedKey = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "nosign")
                    .font(.body)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text("Disable Key")
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
        .accessibilityIdentifier("home-row-mods-disable-key-\(key)")
        .accessibilityLabel("Disable \(displayLabel(forCanonicalKey: key))")
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
        ["fun", "num", "sym", "nav"]
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

    /// Whether the current assignments differ from defaults (for either mode)
    private var hasCustomAssignments: Bool {
        let hasDisabledKeys = config.enabledKeys != Set(HomeRowModsConfig.allKeys)
        if config.holdMode == .modifiers {
            return hasDisabledKeys || modifierPresetSelection(from: config.modifierAssignments) == .custom
        } else {
            return hasDisabledKeys || layerPresetSelection(from: config.layerAssignments) == .custom
        }
    }

    /// Reset assignments to the default for the current hold mode
    private func resetAssignmentsToDefaults() {
        if config.holdMode == .modifiers {
            config.modifierAssignments = HomeRowModsConfig.cagsMacDefault
        } else {
            config.layerAssignments = recommendedLayerAssignments
        }
        config.enabledKeys = Set(HomeRowModsConfig.allKeys)
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
                Task {
                    let ids = [
                        RuleCollectionIdentifier.vimNavigation,
                        RuleCollectionIdentifier.symbolLayer,
                        RuleCollectionIdentifier.numpadLayer,
                        RuleCollectionIdentifier.funLayer
                    ]
                    await onEnableLayerCollections?(ids)
                    config.layerAssignments = recommendedLayerAssignments
                    applyHoldMode(.layers)
                }
                return
            }
            applyHoldMode(mode)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
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
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.35)
                            : (isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)),
                        lineWidth: isSelected ? 1.5 : (isHovered ? 1.5 : 0.5)
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

    private var layerActivationExplanationText: String {
        switch hoveredLayerToggleMode ?? config.layerToggleMode {
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
