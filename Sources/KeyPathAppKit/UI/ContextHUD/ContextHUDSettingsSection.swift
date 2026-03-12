import KeyPathCore
import SwiftUI

/// Visual settings section for the Shortcut List
struct ContextHUDSettingsSection: View {
    @Environment(\.services) private var services
    @State private var displayMode = PreferencesService.shared.contextHUDDisplayMode
    @State private var triggerMode = PreferencesService.shared.contextHUDTriggerMode
    @State private var holdDelayPreset = PreferencesService.shared.contextHUDHoldDelayPreset
    @State private var customHoldDelayMs = PreferencesService.shared.contextHUDHoldDelayCustomMs
    @State private var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcut List")
                .font(.headline)
                .foregroundColor(.secondary)

            // Display Mode (only when Context HUD List is enabled)
            if FeatureFlags.contextHUDListEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        displayModeCard(
                            mode: .overlayOnly,
                            icon: "keyboard",
                            title: "Overlay",
                            subtitle: "Full keyboard"
                        )
                        displayModeCard(
                            mode: .hudOnly,
                            icon: "list.bullet.rectangle",
                            title: "List",
                            subtitle: "Compact view"
                        )
                        displayModeCard(
                            mode: .both,
                            icon: "rectangle.on.rectangle",
                            title: "Both",
                            subtitle: "Overlay + List"
                        )
                    }
                }
            }

            // Trigger Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    SettingsOptionCard(
                        icon: "hand.tap",
                        title: "Hold",
                        subtitle: "Show while held",
                        isSelected: triggerMode == .holdToShow
                    ) {
                        triggerMode = .holdToShow
                        services.preferences.contextHUDTriggerMode = .holdToShow
                    }
                    .accessibilityIdentifier("settings-context-hud-trigger-holdToShow")
                    .accessibilityLabel("Hold trigger mode")

                    SettingsOptionCard(
                        icon: "hand.point.up",
                        title: "Tap",
                        subtitle: "Toggle on/off",
                        isSelected: triggerMode == .tapToToggle
                    ) {
                        triggerMode = .tapToToggle
                        services.preferences.contextHUDTriggerMode = .tapToToggle
                    }
                    .accessibilityIdentifier("settings-context-hud-trigger-tapToToggle")
                    .accessibilityLabel("Tap trigger mode")
                }
            }

            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Hold Delay")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            InfoTip("Default is Long. Medium matches previous behavior.")
                        }

                        Spacer()

                        Picker("Hold Delay", selection: $holdDelayPreset) {
                            ForEach(ContextHUDHoldDelayPreset.allCases, id: \.self) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 140)
                        .onChange(of: holdDelayPreset) { _, newValue in
                            services.preferences.contextHUDHoldDelayPreset = newValue
                            customHoldDelayMs = services.preferences.contextHUDHoldDelayCustomMs
                        }
                        .accessibilityIdentifier("settings-context-hud-hold-delay-preset")
                        .accessibilityLabel("Shortcut List hold delay preset")
                    }

                    if holdDelayPreset == .custom {
                        HStack {
                            Text("Custom (ms)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            TextField(
                                "Milliseconds",
                                value: $customHoldDelayMs,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .onChange(of: customHoldDelayMs) { _, newValue in
                                services.preferences.contextHUDHoldDelayCustomMs = newValue
                                customHoldDelayMs = services.preferences.contextHUDHoldDelayCustomMs
                            }
                            .accessibilityIdentifier("settings-context-hud-hold-delay-custom")
                            .accessibilityLabel("Custom Shortcut List hold delay in milliseconds")
                        }
                    }
                }
                .padding(.top, 2)
            }
            .accessibilityIdentifier("settings-context-hud-advanced")
        }
    }

    // MARK: - Display Mode Card

    private func displayModeCard(
        mode: ContextHUDDisplayMode,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = displayMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                displayMode = mode
                services.preferences.contextHUDDisplayMode = mode
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        .frame(height: 40)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 84)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-context-hud-display-\(mode.rawValue)")
        .accessibilityLabel("\(title) display mode")
    }
}
