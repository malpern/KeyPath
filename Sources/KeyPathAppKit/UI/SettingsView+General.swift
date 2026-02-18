import KeyPathCore
import KeyPathWizardCore
import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTabView: View {
    @Environment(KanataViewModel.self) var kanataManager
    @State private var settingsToastManager = WizardToastManager()

    var body: some View {
        generalSettingsContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .settingsBackground()
            .withToasts(settingsToastManager)
    }

    // MARK: - General Settings Content

    private var generalSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Shortcut List
                ContextHUDSettingsSection()

                // Capture Mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture Mode")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        SettingsOptionCard(
                            icon: "arrow.right",
                            title: "Sequences",
                            subtitle: "Keys one after another",
                            isSelected: PreferencesService.shared.isSequenceMode
                        ) {
                            PreferencesService.shared.isSequenceMode = true
                        }
                        .accessibilityLabel("Sequences capture mode")

                        SettingsOptionCard(
                            icon: "command",
                            title: "Combos",
                            subtitle: "Keys pressed together",
                            isSelected: !PreferencesService.shared.isSequenceMode
                        ) {
                            PreferencesService.shared.isSequenceMode = false
                        }
                        .accessibilityLabel("Combos capture mode")
                    }
                    .accessibilityIdentifier("settings-capture-mode-picker")
                }

                // Recording Behavior
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording Behavior")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        SettingsOptionCard(
                            icon: "keyboard",
                            title: "Physical Keys",
                            subtitle: "Pause mappings",
                            isSelected: !PreferencesService.shared.applyMappingsDuringRecording
                        ) {
                            PreferencesService.shared.applyMappingsDuringRecording = false
                        }
                        .accessibilityLabel("Physical Keys recording behavior")

                        SettingsOptionCard(
                            icon: "wand.and.stars",
                            title: "With Mappings",
                            subtitle: "Include KeyPath",
                            isSelected: PreferencesService.shared.applyMappingsDuringRecording
                        ) {
                            PreferencesService.shared.applyMappingsDuringRecording = true
                        }
                        .accessibilityLabel("With Mappings recording behavior")
                    }
                    .accessibilityIdentifier("settings-recording-behavior-picker")
                }

                Divider()

                // Logs
                VStack(alignment: .leading, spacing: 10) {
                    Text("Logs")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            openLogFile(NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log")
                        } label: {
                            Label("KeyPath Log", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityIdentifier("settings-open-keypath-log-button")
                        .accessibilityLabel("Open KeyPath log")

                        Button {
                            openLogFile(WizardSystemPaths.kanataLogFile)
                        } label: {
                            Label("Kanata Log", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityIdentifier("settings-open-kanata-log-button")
                        .accessibilityLabel("Open Kanata log")
                    }

                    VerboseLoggingToggle()
                        .padding(.top, 4)
                }

                if FeatureFlags.simulatorAndVirtualKeysEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Virtual Keys")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        VirtualKeysInspectorView()
                    }
                    .accessibilityIdentifier("settings-virtual-keys-section")
                }

                #if DEBUG
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Experimental")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        ExperimentalSettingsSection()
                            .padding(.top, 8)
                    }
                    .accessibilityIdentifier("settings-experimental-section")
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func openLogFile(_ filePath: String) {
        // Try to open with Zed editor first (if available)
        let zedProcess = Process()
        zedProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/zed")
        zedProcess.arguments = [filePath]

        do {
            try zedProcess.run()
            AppLogger.shared.log("📝 [Settings] Opened log in Zed: \(filePath)")
            return
        } catch {
            // Fallback: Try to open with default text editor
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallbackProcess.arguments = ["-t", filePath]

            do {
                try fallbackProcess.run()
                AppLogger.shared.log("📝 [Settings] Opened log in default text editor: \(filePath)")
            } catch {
                AppLogger.shared.log("❌ [Settings] Failed to open log file: \(error.localizedDescription)")
                settingsToastManager.showError("Failed to open log file")
            }
        }
    }
}

// MARK: - Verbose Logging Toggle

struct VerboseLoggingToggle: View {
    @Environment(KanataViewModel.self) var kanataManager
    @State private var verboseLogging = PreferencesService.shared.verboseKanataLogging
    @State private var showingRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verbose Logging")
                        .font(.headline)
                    Text("Detailed Kanata trace logs for debugging")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: $verboseLogging
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.blue)
                .accessibilityIdentifier("settings-verbose-logging-toggle")
                .accessibilityLabel("Verbose Kanata Logging")
                .onChange(of: verboseLogging) { _, newValue in
                    Task { @MainActor in
                        PreferencesService.shared.verboseKanataLogging = newValue
                        showingRestartAlert = true
                    }
                }
            }

            if verboseLogging {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text(
                        "Generates large log files. Use for debugging only."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor.windowBackgroundColor))
        )
        .alert("Service Restart Required", isPresented: $showingRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                Task {
                    await restartKanataService()
                }
            }
        } message: {
            Text(
                "Kanata needs to restart for the new logging setting to take effect. Would you like to restart now?"
            )
        }
    }

    private func restartKanataService() async {
        AppLogger.shared.log("\u{1F504} [VerboseLogging] Restarting Kanata service with new logging flags")
        let success = await kanataManager.restartKanata(reason: "Verbose logging toggle")
        if !success {
            AppLogger.shared.error("\u{274C} [VerboseLogging] Kanata restart failed after verbose toggle")
        }
    }
}
