import KeyPathCore
import KeyPathPluginKit
import SwiftUI

/// Settings section for experimental features and feature flags
struct ExperimentalSettingsSection: View {
    @Environment(\.services) private var services

    // Feature flag states
    @State private var captureListenOnlyEnabled = FeatureFlags.captureListenOnlyEnabled
    @State private var useSMAppServiceForDaemon = FeatureFlags.useSMAppServiceForDaemon
    @State private var simulatorAndVirtualKeysEnabled = FeatureFlags.simulatorAndVirtualKeysEnabled
    @State private var uninstallForTesting = FeatureFlags.uninstallForTesting
    @State private var learningTipsMode = FeatureFlags.learningTipsMode
    @State private var contextHUDListEnabled = FeatureFlags.contextHUDListEnabled
    @State private var qmkSearchEnabled = UserDefaults.standard.object(forKey: LayoutPreferences.qmkSearchEnabledKey) != nil
        ? UserDefaults.standard.bool(forKey: LayoutPreferences.qmkSearchEnabledKey)
        : LayoutPreferences.qmkSearchEnabledDefault
    @State private var accessibilityTestMode = PreferencesService.shared.accessibilityTestMode
    @State private var suppressedBundleIDs: [String] = Array(PreferencesService.shared.overlaySuppressedBundleIDs).sorted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Quick Features Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(icon: "keyboard.badge.ellipsis", title: "Quick Features", color: .blue)

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
                        SectionHeader(icon: "sparkles", title: "AI Config Generation", color: .purple)

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
                ForEach(PluginManager.shared.availablePlugins) { entry in
                    SettingsCard {
                        PluginCatalogCard(entry: entry)
                    }
                }

                // Per-app overlay suppression
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            icon: "eye.slash",
                            title: "Hide Overlay in Specific Apps",
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
                                            .font(.system(size: 12, weight: .medium))
                                        Text(bundleID)
                                            .font(.system(size: 10, design: .monospaced))
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
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("overlay-suppressed-add-app")
                    }
                }

                // Testing Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(icon: "ant.fill", title: "Testing", color: .green)

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Text("Accessibility Test Mode")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                InfoTip("Makes overlay discoverable by automation tools (Peekaboo). Takes effect immediately.")
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { accessibilityTestMode },
                                set: { newValue in
                                    accessibilityTestMode = newValue
                                    services.preferences.accessibilityTestMode = newValue
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .accessibilityIdentifier("settings-accessibility-test-mode")
                            .accessibilityLabel("Accessibility test mode")
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Developer Feature Flags Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(icon: "flag.fill", title: "Developer Feature Flags", color: .orange)

                        Text("These flags control experimental functionality. Changes may require app restart.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        featureFlagsSection
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Global Hotkey Toggle

    private var globalHotkeyToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Global Hotkey")
                    .font(.body)
                    .fontWeight(.medium)
                Text("⌥⌘K to show/hide overlay, ⌥⌘L to reset & center")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { GlobalHotkeyService.shared.isEnabled },
                set: { GlobalHotkeyService.shared.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .accessibilityIdentifier("settings-global-hotkey-toggle")
        .accessibilityLabel("Global hotkey to show/hide KeyPath")
    }

    // MARK: - QMK Search Toggle

    private var qmkSearchToggle: some View {
        HStack {
            HStack(spacing: 4) {
                Text("QMK Keyboard Search")
                    .font(.body)
                    .fontWeight(.medium)
                InfoTip("Search and import layouts from the QMK keyboard database")
            }
            Spacer()
            Toggle("", isOn: $qmkSearchEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
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
                title: "Simulator + Virtual Keys",
                description: "Enable overlay labels via simulator",
                isOn: $simulatorAndVirtualKeysEnabled,
                onChange: { FeatureFlags.setSimulatorAndVirtualKeysEnabled($0) },
                identifier: "feature-flag-simulator"
            )
            .accessibilityIdentifier("feature-flag-simulator-row")

            featureFlagToggle(
                title: "Listen-Only Event Tap",
                description: "CGEvent tap only listens (no modification)",
                isOn: $captureListenOnlyEnabled,
                onChange: { FeatureFlags.setCaptureListenOnlyEnabled($0) },
                identifier: "feature-flag-listen-only"
            )
            .accessibilityIdentifier("feature-flag-listen-only-row")

            featureFlagToggle(
                title: "SMAppService for Daemon",
                description: "Use modern daemon registration API",
                isOn: $useSMAppServiceForDaemon,
                onChange: { FeatureFlags.setUseSMAppServiceForDaemon($0) },
                identifier: "feature-flag-smappservice"
            )
            .accessibilityIdentifier("feature-flag-smappservice-row")

            featureFlagToggle(
                title: "Uninstall for Testing",
                description: "Reset TCC permissions & prefs on uninstall",
                isOn: $uninstallForTesting,
                onChange: { FeatureFlags.setUninstallForTesting($0) },
                identifier: "feature-flag-uninstall-testing"
            )
            .accessibilityIdentifier("feature-flag-uninstall-testing-row")

            featureFlagToggle(
                title: "Context HUD List",
                description: "Show compact key list window on layer activation",
                isOn: $contextHUDListEnabled,
                onChange: { FeatureFlags.setContextHUDListEnabled($0) },
                identifier: "feature-flag-context-hud-list"
            )
            .accessibilityIdentifier("feature-flag-context-hud-list-row")

            learningTipsModePicker
                .accessibilityIdentifier("feature-flag-learning-tips-row")
        }
    }

    private func featureFlagToggle(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    isOn.wrappedValue = newValue
                    onChange(newValue)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(title)
        }
        .padding(.vertical, 4)
    }

    private var learningTipsModePicker: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Learning Tips")
                    .font(.subheadline)
                    .fontWeight(.medium)
                InfoTip("Control when contextual tips are shown")
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
        panel.title = "Choose an app"
        panel.prompt = "Choose"
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

// MARK: - Supporting Views

private struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.body)
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
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
