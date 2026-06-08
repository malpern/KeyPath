import SwiftUI
#if os(macOS)
    import AppKit
#endif

// MARK: - Assignment Popovers

extension HomeRowModsCollectionView {
    var modifierOptions: [(kind: String, label: String, symbol: String)] {
        [
            ("met", "Command", "\u{2318}"),
            ("alt", "Option", "\u{2325}"),
            ("ctl", "Control", "\u{2303}"),
            ("sft", "Shift", "\u{21E7}")
        ]
    }

    func modifierPopoverContent(for key: String) -> some View {
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
                .accessibilityValue(isModifierOptionSelected(option.kind, for: key) ? "selected" : "not selected")

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

    func layerPopoverContent(for key: String) -> some View {
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
                .accessibilityValue(config.layerAssignments[key] == option.key ? "selected" : "not selected")

                if index < layerOptions.count - 1 {
                    PopoverListDivider()
                }
            }

            PopoverListDivider()

            disableKeyButton(for: key)

            PopoverListDivider()

            Button {
                pendingNewLayerAssignmentKey = key
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

    func enableKeyPopoverContent(for key: String) -> some View {
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
            .accessibilityValue(config.enabledKeys.contains(key) ? "enabled" : "disabled")
        }
        .padding(.vertical, 6)
        .frame(minWidth: 210)
        .pickerPopoverChrome()
    }

    func disableKeyButton(for key: String) -> some View {
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
        .accessibilityValue(config.enabledKeys.contains(key) ? "enabled" : "disabled")
    }

    func isModifierOptionSelected(_ kind: String, for key: String) -> Bool {
        guard let assignment = config.modifierAssignments[key] else { return false }
        return canonicalModifierKind(from: assignment) == kind
    }

    func sidedModifierAssignment(for key: String, kind: String) -> String {
        let isRightHand = HomeRowModsConfig.rightHandKeys.contains(key)
        return (isRightHand ? "r" : "l") + kind
    }

    func canonicalModifierKind(from assignment: String) -> String {
        guard assignment.count == 4 else { return assignment }
        if assignment.hasPrefix("l") || assignment.hasPrefix("r") {
            return String(assignment.dropFirst())
        }
        return assignment
    }
}
