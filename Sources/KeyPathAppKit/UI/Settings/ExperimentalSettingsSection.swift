import KeyPathCore
import KeyPathPermissions
import KeyPathPluginKit
import SwiftUI

/// Settings section for experimental features and feature flags
struct ExperimentalSettingsSection: View {
    @Environment(\.services) private var services

    // Feature flag states
    @State private var captureListenOnlyEnabled = FeatureFlags.captureListenOnlyEnabled
    @State private var simulatorAndVirtualKeysEnabled = FeatureFlags.simulatorAndVirtualKeysEnabled
    @State private var uninstallForTesting = FeatureFlags.uninstallForTesting
    @State private var learningTipsMode = FeatureFlags.learningTipsMode
    @State private var contextHUDListEnabled = FeatureFlags.contextHUDListEnabled
    @State private var keyboardAttributionEnabled = KeyboardAttributionMonitor.isEnabled()
    @State private var qmkSearchEnabled = UserDefaults.standard.object(forKey: LayoutPreferences.qmkSearchEnabledKey) != nil
        ? UserDefaults.standard.bool(forKey: LayoutPreferences.qmkSearchEnabledKey)
        : LayoutPreferences.qmkSearchEnabledDefault
    @State private var accessibilityTestMode = PreferencesService.shared.accessibilityTestMode
    @State private var suppressedBundleIDs: [String] = Array(PreferencesService.shared.overlaySuppressedBundleIDs).sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.sectionGap) {
            // Quick Features Section
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(title: String(localized: "Quick Features"), icon: "keyboard.badge.ellipsis", color: .blue)

                    globalHotkeyToggle
                    Divider()
                    qmkSearchToggle
                }
            }

            // Script Execution Section
            SettingsCard {
                ScriptExecutionSettingsSection()
            }

            // AI Config Section
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: String(localized: "AI Config Generation"), icon: "sparkles", color: .purple)

                    AIConfigGenerationSettingsSection()
                }
            }

            // Plugins Section
            if !PluginManager.shared.plugins.isEmpty {
                ForEach(PluginManager.shared.plugins.map(PluginWrapper.init)) { wrapper in
                    SettingsCard {
                        InstalledPluginCard(plugin: wrapper.plugin)
                    }
                }
            }

            // Per-app overlay suppression
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(
                        title: String(localized: "Hide Overlay in Specific Apps"),
                        icon: "eye.slash",
                        color: .indigo
                    )
                    Text("The live keyboard overlay and hint panel auto-hide while these apps are frontmost. They restore when you switch away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(suppressedBundleIDs, id: \.self) { bundleID in
                            HStack {
                                Image(systemName: appIcon(for: bundleID))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(appDisplayName(for: bundleID))
                                        .font(.callout.weight(.medium))
                                    Text(bundleID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    removeBundleID(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(appDisplayName(for: bundleID))")
                                .accessibilityIdentifier("overlay-suppressed-remove-\(bundleID)")
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                        if suppressedBundleIDs.isEmpty {
                            Text("No apps configured.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                        }
                    }

                    Button {
                        addAppViaPicker()
                    } label: {
                        Label("Add App…", systemImage: "plus")
                            .font(.callout.weight(.medium))
                    }
                    .settingsAction()
                    .accessibilityIdentifier("overlay-suppressed-add-app")
                }
            }

            // Testing Section
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: String(localized: "Testing", comment: "Settings section header for test-only options"), icon: "ant.fill", color: .green)

                    SettingsToggleRow(
                        title: String(localized: "Accessibility Test Mode"),
                        help: String(localized: "Makes overlay discoverable by automation tools (Peekaboo). Takes effect immediately."),
                        isOn: Binding(get: { accessibilityTestMode }, set: { newValue in
                            accessibilityTestMode = newValue
                            services.preferences.accessibilityTestMode = newValue
                        }), identifier: "settings-accessibility-test-mode"
                    )
                }
            }

            // Developer Feature Flags Section
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: String(localized: "Developer Feature Flags"), icon: "flag.fill", color: .orange)

                    Text("These flags control experimental functionality. Changes may require app restart.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    featureFlagsSection
                }
            }
        }
    }

    // MARK: - Global Hotkey Toggle

    private var globalHotkeyToggle: some View {
        SettingsToggleRow(
            title: String(localized: "Global Hotkey"), subtitle: String(localized: "⌥⌘K to show/hide overlay, ⌥⌘L to reset & center"),
            isOn: Binding(get: { GlobalHotkeyService.shared.isEnabled }, set: { GlobalHotkeyService.shared.isEnabled = $0 }),
            identifier: "settings-global-hotkey-toggle"
        )
    }

    // MARK: - QMK Search Toggle

    private var qmkSearchToggle: some View {
        SettingsToggleRow(title: String(localized: "QMK Keyboard Search"),
                          help: String(localized: "Search and import layouts from the QMK keyboard database"),
                          isOn: $qmkSearchEnabled, identifier: "settings-qmk-search-toggle")
            .onChange(of: qmkSearchEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: LayoutPreferences.qmkSearchEnabledKey)
            }
            .accessibilityIdentifier("settings-qmk-search-toggle")
            .accessibilityLabel("Enable QMK keyboard search")
    }

    // MARK: - Feature Flags

    private var featureFlagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureFlagToggle(
                title: String(localized: "Simulator + Virtual Keys"),
                description: String(localized: "Enable overlay labels via simulator"),
                isOn: $simulatorAndVirtualKeysEnabled,
                onChange: { FeatureFlags.setSimulatorAndVirtualKeysEnabled($0) },
                identifier: "feature-flag-simulator"
            )

            featureFlagToggle(
                title: String(localized: "Listen-Only Event Tap"),
                description: String(localized: "CGEvent tap only listens (no modification)"),
                isOn: $captureListenOnlyEnabled,
                onChange: { FeatureFlags.setCaptureListenOnlyEnabled($0) },
                identifier: "feature-flag-listen-only"
            )

            featureFlagToggle(
                title: String(localized: "Uninstall for Testing"),
                description: String(localized: "Reset TCC permissions & prefs on uninstall"),
                isOn: $uninstallForTesting,
                onChange: { FeatureFlags.setUninstallForTesting($0) },
                identifier: "feature-flag-uninstall-testing"
            )

            featureFlagToggle(
                title: String(localized: "Context HUD List"),
                description: String(localized: "Show compact key list window on layer activation"),
                isOn: $contextHUDListEnabled,
                onChange: { FeatureFlags.setContextHUDListEnabled($0) },
                identifier: "feature-flag-context-hud-list"
            )

            featureFlagToggle(
                title: String(localized: "Keyboard Attribution (log only)"),
                description: String(localized: "Count which keyboard each key came from, in the log. Needs Input Monitoring. Applies when the engine next starts."),
                isOn: $keyboardAttributionEnabled,
                onChange: { enabled in
                    UserDefaults.standard.set(enabled, forKey: KeyboardAttributionMonitor.enabledKey)
                    if enabled, SystemStateProvider.shared.keyPathInputMonitoringStatus() != .granted {
                        SystemStateProvider.shared.requestKeyPathInputMonitoring()
                    }
                },
                identifier: "feature-flag-keyboard-attribution"
            )

            learningTipsModePicker
        }
    }

    private func featureFlagToggle(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void,
        identifier: String
    ) -> some View {
        SettingsToggleRow(title: title, subtitle: description, isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                onChange(newValue)
            }
        ), identifier: identifier)
    }

    private var learningTipsModePicker: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Learning Tips")
                    .font(.subheadline)
                    .fontWeight(.medium)
                InfoTip(String(localized: "Control when contextual tips are shown"))
            }

            Spacer()

            Picker("", selection: Binding(
                get: { learningTipsMode },
                set: { newValue in
                    learningTipsMode = newValue
                    FeatureFlags.setLearningTipsMode(newValue)
                }
            )) {
                ForEach(LearningTipsMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityIdentifier("feature-flag-learning-tips")
            .accessibilityLabel("Learning tips mode")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Per-app suppression helpers

    private func addAppViaPicker() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an app")
        panel.prompt = String(localized: "Choose", comment: "Open panel button: choose the selected app")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier
        else { return }
        var updated = Set(suppressedBundleIDs)
        updated.insert(bundleID)
        applySuppressedChange(updated)
    }

    private func removeBundleID(_ id: String) {
        var updated = Set(suppressedBundleIDs)
        updated.remove(id)
        applySuppressedChange(updated)
    }

    private func applySuppressedChange(_ updated: Set<String>) {
        suppressedBundleIDs = Array(updated).sorted()
        services.preferences.overlaySuppressedBundleIDs = updated
    }

    /// Best-effort nice display name for a bundle id (reads
    /// `CFBundleDisplayName` / `CFBundleName` from the installed app).
    /// Falls back to the last path component of the bundle id.
    private func appDisplayName(for bundleID: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path,
           let bundle = Bundle(path: path),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
           ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        {
            return name
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    private func appIcon(for _: String) -> String {
        "app"
    }
}

#Preview {
    ExperimentalSettingsSection()
        .frame(width: 600, height: 800)
}

#Preview("Experimental Settings - Compact") {
    ExperimentalSettingsSection()
        .frame(width: 420, height: 640)
        .padding()
}
