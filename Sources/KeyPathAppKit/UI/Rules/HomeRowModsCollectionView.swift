import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Main view for Home Row Mods collection with progressive disclosure
struct HomeRowModsCollectionView: View {
    @Binding var config: HomeRowModsConfig
    let onConfigChanged: (HomeRowModsConfig) -> Void
    
    @State private var showCustomize = false
    @State private var selectedKey: String?
    @State private var showModifierPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Visual keyboard (always visible when expanded)
            HomeRowKeyboardView(
                enabledKeys: config.enabledKeys,
                modifierAssignments: config.modifierAssignments,
                selectedKey: selectedKey,
                onKeySelected: { key in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedKey = selectedKey == key ? nil : key
                        showModifierPicker = selectedKey != nil
                    }
                }
            )
            .padding(.bottom, 16)
            
            // Progressive disclosure: Customize section
            if showCustomize {
                customizeSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showCustomize = true
                    }
                }) {
                    HStack {
                        Text("Customize...")
                            .font(.body)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            
            // Modifier picker (contextual, appears when key is selected)
            if showModifierPicker, let selectedKey = selectedKey {
                modifierPickerSection(for: selectedKey)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showCustomize)
        .animation(.easeInOut(duration: 0.2), value: showModifierPicker)
    }
    
    // MARK: - Customize Section
    
    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Key selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Which keys?")
                    .font(.body)
                
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
            }
            
            // Fewer Options button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showCustomize = false
                    selectedKey = nil
                    showModifierPicker = false
                }
            }) {
                HStack {
                    Text("Fewer Options")
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
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
                ForEach(HomeRowModsConfig.allKeys, id: \.self) { key in
                    Button(action: {
                        if config.enabledKeys.contains(key) {
                            config.enabledKeys.remove(key)
                        } else {
                            config.enabledKeys.insert(key)
                        }
                        updateConfig()
                    }) {
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
                }
            }
        }
    }
    
    // MARK: - Modifier Picker
    
    private func modifierPickerSection(for key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Modifier for \"\(key.uppercased())\":")
                    .font(.body)
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
            }
            
            HStack(spacing: 12) {
                ForEach(modifierOptions, id: \.key) { option in
                    modifierButton(
                        label: option.label,
                        symbol: option.symbol,
                        isSelected: config.modifierAssignments[key] == option.key,
                        action: {
                            config.modifierAssignments[key] = option.key
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
    }
    
    // MARK: - Helpers
    
    private func updateConfig() {
        onConfigChanged(config)
    }
}

