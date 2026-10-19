import KeyPathCore
import SwiftUI

/// Visual settings section for the Shortcut List
struct ContextHUDSettingsSection: View {
    @Environment(\.services) private var services
    @Environment(KanataViewModel.self) private var kanataManager
    @State private var displayMode = PreferencesService.shared.contextHUDDisplayMode
    @State private var triggerMode = PreferencesService.shared.contextHUDTriggerMode
    @State private var holdDelayPreset = PreferencesService.shared.contextHUDHoldDelayPreset
    @State private var customHoldDelayMs = PreferencesService.shared.contextHUDHoldDelayCustomMs
    @State private var advancedExpanded = false

    var body: some View {
        SettingsSection(title: "Shortcut List") {
            SettingsCard {
                VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
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
                                isSelected: triggerMode == .holdToShow,
                                cardWidth: SettingsOptionCard.settingsRowWidth
                            ) {
                                applyShortcutListInput(triggerMode: .holdToShow)
                            }
                            .accessibilityIdentifier("settings-context-hud-trigger-holdToShow")
                            .accessibilityLabel("Hold trigger mode")

                            SettingsOptionCard(
                                icon: "hand.point.up",
                                title: "Tap",
                                subtitle: "Toggle on/off",
                                isSelected: triggerMode == .tapToToggle,
                                cardWidth: SettingsOptionCard.settingsRowWidth
                            ) {
                                applyShortcutListInput(triggerMode: .tapToToggle)
                            }
                            .accessibilityIdentifier("settings-context-hud-trigger-tapToToggle")
                            .accessibilityLabel("Tap trigger mode")
                        }
                    }

                    DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 4) {
                                    Text(TimingCopy.leaderHoldDelay)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    InfoTip(String(localized: TimingCopy.leaderHoldDelayExplanation))
                                }

                                Spacer()

                                Picker(selection: $holdDelayPreset) {
                                    ForEach(ContextHUDHoldDelayPreset.allCases, id: \.self) { preset in
                                        Text(preset.displayName).tag(preset)
                                    }
                                } label: {
                                    Text(TimingCopy.leaderHoldDelay)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 140)
                                .onChange(of: holdDelayPreset) { _, newValue in
                                    applyShortcutListInput(holdDelayPreset: newValue)
                                }
                                .accessibilityIdentifier("settings-context-hud-hold-delay-preset")
                                .accessibilityLabel(Text(TimingCopy.leaderHoldDelay))
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
                                        applyShortcutListInput(customHoldDelayMs: newValue)
                                    }
                                    .accessibilityIdentifier("settings-context-hud-hold-delay-custom")
                                    .accessibilityLabel(Text(TimingCopy.customLeaderHoldDelayAccessibilityLabel))
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                    .accessibilityIdentifier("settings-context-hud-advanced")
                }
            }
        }
        .onAppear { refreshPreferences() }
        .onReceive(NotificationCenter.default.publisher(for: .ruleCollectionsChanged)) { _ in
            refreshPreferences()
        }
    }

    private func refreshPreferences() {
        let input = services.preferences.shortcutListGenerationInput
        triggerMode = input.triggerMode
        holdDelayPreset = input.holdDelayPreset
        customHoldDelayMs = input.customHoldDelayMs
        displayMode = services.preferences.contextHUDDisplayMode
    }

    // MARK: - Display Mode Card

    private func applyShortcutListInput(
        triggerMode: ContextHUDTriggerMode? = nil,
        holdDelayPreset: ContextHUDHoldDelayPreset? = nil,
        customHoldDelayMs: Int? = nil
    ) {
        let candidate = ShortcutListGenerationInput(
            triggerMode: triggerMode ?? self.triggerMode,
            holdDelayPreset: holdDelayPreset ?? self.holdDelayPreset,
            customHoldDelayMs: customHoldDelayMs ?? self.customHoldDelayMs
        )
        guard candidate != services.preferences.shortcutListGenerationInput else { return }
        Task {
            guard await kanataManager.applyShortcutListGenerationInput(candidate) else {
                let restored = services.preferences.shortcutListGenerationInput
                self.triggerMode = restored.triggerMode
                self.holdDelayPreset = restored.holdDelayPreset
                self.customHoldDelayMs = restored.customHoldDelayMs
                return
            }
            self.triggerMode = candidate.triggerMode
            self.holdDelayPreset = candidate.holdDelayPreset
            self.customHoldDelayMs = candidate.customHoldDelayMs
        }
    }

    private func displayModeCard(
        mode: ContextHUDDisplayMode,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        SettingsOptionCard(
            icon: icon, title: title, subtitle: subtitle,
            isSelected: displayMode == mode,
            cardWidth: SettingsDesign.compactOptionWidth
        ) {
            displayMode = mode
            services.preferences.contextHUDDisplayMode = mode
        }
        .accessibilityIdentifier("settings-context-hud-display-\(mode.rawValue)")
        .accessibilityLabel("\(title) display mode")
    }
}
