import KeyPathRulesCore
import SwiftUI
#if os(macOS)
    import AppKit
#endif

// MARK: - Configuration & Customize Window

extension HomeRowModsCollectionView {
    var customizeWindowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Home row preferences")
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .accessibilityIdentifier("home-row-mods-preferences-panel")
                .accessibilityLabel("Home row preferences")
                .accessibilityValue(homeRowModsAccessibilityValue)

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
                .accessibilityLabel("Done editing home row preferences")
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

    var customizeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(usesTopRowKeys
                ? "These settings control what your top-row keys do when you hold them. Tap still types letters."
                : "These settings control what your home-row keys do when you hold them. Tap still types letters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Hold Behavior")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Hold action mode")
                    .frame(width: 0, height: 0)
                    .opacity(0.01)
                    .accessibilityIdentifier("home-row-mods-hold-mode-picker")
                    .accessibilityLabel("Hold action mode")
                    .accessibilityValue(config.holdMode.displayName)

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

                    Text("Layer activation mode")
                        .frame(width: 0, height: 0)
                        .opacity(0.01)
                        .accessibilityIdentifier("home-row-mods-layer-toggle-mode-picker")
                        .accessibilityLabel("Layer activation mode")
                        .accessibilityValue(config.layerToggleMode.displayName)

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
                        .accessibilityLabel("Layer activation while held")
                        .accessibilityValue(config.layerToggleMode == .whileHeld ? "selected" : "not selected")

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
                        .accessibilityLabel("Layer activation toggle")
                        .accessibilityValue(config.layerToggleMode == .toggle ? "selected" : "not selected")
                    }

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
            .frame(maxWidth: 500)
        }
    }

    @ViewBuilder
    func holdBehaviorOptionCard(
        mode: HomeRowHoldMode,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = config.holdMode == mode
        let isHovered = hoveredHoldBehavior == mode

        Button {
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
        .accessibilityLabel("Use \(title) for home row holds")
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }

    func applyHoldMode(_ mode: HomeRowHoldMode) {
        var updatedConfig = config
        if mode == .layers {
            updatedConfig.layerAssignments = recommendedLayerAssignments
        }
        updatedConfig.holdMode = mode
        updatedConfig.hasUserSelectedHoldMode = true
        config = updatedConfig
        selectedKey = nil
        updateConfig(updatedConfig)
    }

    var holdBehaviorExplanationText: String {
        let keyDesc = usesTopRowKeys ? "a top-row key" : "a home-row key"
        switch hoveredHoldBehavior ?? config.holdMode {
        case .modifiers:
            return "Best for shortcuts and general app use. Hold \(keyDesc) to get Cmd/Opt/Ctrl/Shift."
        case .layers:
            return "Best for advanced layouts. Hold \(keyDesc) to temporarily access another key layer."
        }
    }

    var layerActivationExplanationText: String {
        switch hoveredLayerToggleMode ?? config.layerToggleMode {
        case .whileHeld:
            "Momentary mode: layer turns off when you release the key."
        case .toggle:
            "Latch mode: layer stays active until you switch it off."
        }
    }

    var newLayerSheet: some View {
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
                    pendingNewLayerAssignmentKey = nil
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
                        if let assignmentKey = pendingNewLayerAssignmentKey ?? selectedKey {
                            HomeRowModsNewLayerAssignment.assign(layerName: raw, to: assignmentKey, config: &config)
                            updateConfig()
                        }
                        newLayerName = ""
                        pendingNewLayerAssignmentKey = nil
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
        .accessibilityIdentifier("home-row-mods-new-layer-sheet")
        .accessibilityLabel("Create new home row layer")
    }
}

enum HomeRowModsNewLayerAssignment {
    static func assign(layerName: String, to key: String, config: inout HomeRowModsConfig) {
        let normalizedLayer = layerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedLayer.isEmpty else { return }
        config.layerAssignments[key] = normalizedLayer
    }
}
