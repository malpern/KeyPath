import KeyPathCore
import SwiftUI

/// Settings section for experimental features and feature flags
struct ExperimentalSettingsSection: View {
    // Feature flag states
    @State private var captureListenOnlyEnabled = FeatureFlags.captureListenOnlyEnabled
    @State private var useSMAppServiceForDaemon = FeatureFlags.useSMAppServiceForDaemon
    @State private var simulatorAndVirtualKeysEnabled = FeatureFlags.simulatorAndVirtualKeysEnabled
    @State private var uninstallForTesting = FeatureFlags.uninstallForTesting
    @State private var learningTipsMode = FeatureFlags.learningTipsMode
    @State private var qmkSearchEnabled = UserDefaults.standard.bool(forKey: LayoutPreferences.qmkSearchEnabledKey)

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

                // Activity Logging Section
                SettingsCard {
                    ActivityLoggingSettingsSection()
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
            VStack(alignment: .leading, spacing: 2) {
                Text("QMK Keyboard Search")
                    .font(.body)
                    .fontWeight(.medium)
                Text("Search and import layouts from the QMK keyboard database")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Learning Tips")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Control when contextual tips are shown")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
