import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore
import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTabView: View {
    @Environment(KanataViewModel.self) var kanataManager
    @Environment(\.services) private var services
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
            VStack(alignment: .leading, spacing: SettingsDesign.sectionGap) {
                LaunchAtLoginSettingsSection()
                // What appears while a layer is active (overlay, list, banner)
                ContextHUDSettingsSection()
                SettingsSection(title: "Keyboard Appearance") {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                            Text("Key labels").font(.body.weight(.medium))
                            HStack(spacing: SettingsDesign.optionGap) {
                                SettingsKeyPreviewChoice(title: "Symbols", keys: ["⌫", "⇥", "⇧"],
                                                         isSelected: services.preferences.keyLabelStyle == .symbols,
                                                         identifier: "settings-key-label-symbols")
                                {
                                    services.preferences.keyLabelStyle = .symbols
                                }
                                SettingsKeyPreviewChoice(title: "Text", keys: ["delete", "tab", "shift"],
                                                         isSelected: services.preferences.keyLabelStyle == .text,
                                                         identifier: "settings-key-label-text")
                                {
                                    services.preferences.keyLabelStyle = .text
                                }
                            }
                            Divider()
                            Text("Unmapped keys on layers").font(.body.weight(.medium))
                            HStack(spacing: SettingsDesign.optionGap) {
                                SettingsKeyPreviewChoice(title: "Normal", keys: ["A", "S", "D"],
                                                         isSelected: services.preferences.unmappedLayerKeyStyle == .baseLayer,
                                                         identifier: "settings-unmapped-layer-keys-base")
                                {
                                    services.preferences.unmappedLayerKeyStyle = .baseLayer
                                }
                                SettingsKeyPreviewChoice(title: "Dimmed", keys: ["A", "S", "D"], dimmed: true,
                                                         isSelected: services.preferences.unmappedLayerKeyStyle == .dimmed,
                                                         identifier: "settings-unmapped-layer-keys-dimmed")
                                {
                                    services.preferences.unmappedLayerKeyStyle = .dimmed
                                }
                            }
                            Divider()
                            OverlayOpacityRow()
                            SettingsToggleRow(
                                title: "Fade when idle",
                                subtitle: "The overlay fades after a while without typing.",
                                isOn: Binding(
                                    get: { services.preferences.overlayFadesWhenIdle },
                                    set: { services.preferences.overlayFadesWhenIdle = $0 }
                                ),
                                identifier: "settings-overlay-fade-when-idle"
                            )
                        }
                    }
                }

                SettingsSection(title: "Recording") {
                    SettingsCard {
                        VStack(spacing: SettingsDesign.rowGap) {
                            SettingsControlRow(title: "Capture", icon: "record.circle", help: "Record keys one after another, or a combination pressed together.") {
                                Picker("Capture", selection: Binding(get: { services.preferences.isSequenceMode }, set: { services.preferences.isSequenceMode = $0 })) {
                                    Text("Sequences").tag(true)
                                    Text("Combos").tag(false)
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: SettingsDesign.optionWidth)
                                .accessibilityIdentifier("settings-capture-mode-picker")
                            }
                            Divider()
                            SettingsControlRow(title: "Record", icon: "keyboard", help: "Physical keys pauses your mappings while recording. With mappings includes KeyPath’s remapped output.") {
                                Picker(
                                    "Recording behavior",
                                    selection: Binding(get: { services.preferences.applyMappingsDuringRecording }, set: { services.preferences.applyMappingsDuringRecording = $0 })
                                ) {
                                    Text("Physical keys").tag(false)
                                    Text("With mappings").tag(true)
                                }
                                .pickerStyle(.segmented).labelsHidden().frame(width: SettingsDesign.optionWidth)
                                .accessibilityIdentifier("settings-recording-behavior-picker")
                            }
                        }
                    }
                }

                SettingsSection(title: "Caps Lock") {
                    SettingsCard { SessionCapsSettingsSection() }
                }

                SettingsSection(title: "Advanced") {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                                    HStack {
                                        Button("KeyPath Log") { openLogFile(KeyPathConstants.Logs.userDebugLog) }
                                            .settingsAction().accessibilityIdentifier("settings-open-keypath-log-button")
                                        Button("Runtime Log") { openLogFile(WizardSystemPaths.kanataLogFile) }
                                            .settingsAction().accessibilityIdentifier("settings-open-kanata-log-button")
                                    }
                                    VerboseLoggingToggle()
                                }.padding(.top, SettingsDesign.rowGap)
                            } label: { Label("Logs & Diagnostics", systemImage: "waveform.path.ecg") }
                                .accessibilityIdentifier("settings-logs-disclosure")
                            if FeatureFlags.simulatorAndVirtualKeysEnabled {
                                Divider()
                                DisclosureGroup {
                                    VirtualKeysInspectorView()
                                } label: { Label("Virtual Keys", systemImage: "keyboard.badge.ellipsis") }
                                    .accessibilityIdentifier("settings-virtual-keys-disclosure")
                            }
                            #if DEBUG
                                Divider()
                                DisclosureGroup {
                                    ExperimentalSettingsSection().padding(.top, SettingsDesign.rowGap)
                                } label: { Label("Experimental", systemImage: "flask") }
                                    .accessibilityIdentifier("settings-experimental-disclosure")
                            #endif
                        }
                    }
                }
            }
            .padding(.horizontal, SettingsDesign.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func openLogFile(_ filePath: String) {
        Task {
            do {
                _ = try await SubprocessRunner.shared.run("/usr/bin/open", args: ["-t", filePath])
                AppLogger.shared.log("📝 [Settings] Opened log in default text editor: \(filePath)")
            } catch {
                AppLogger.shared.log("❌ [Settings] Failed to open log file: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Overlay Opacity

struct OverlayOpacityRow: View {
    @Environment(\.services) private var services

    var body: some View {
        let opacity = Binding(
            get: { services.preferences.overlayOpacity },
            set: { services.preferences.overlayOpacity = $0 }
        )
        HStack(spacing: SettingsDesign.rowGap) {
            VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
                Text("Overlay opacity").font(.body.weight(.medium))
                Text("Lower it to see your work through the keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Slider(value: opacity, in: 0.3 ... 1.0, step: 0.05)
                .frame(width: 160)
                .accessibilityIdentifier("settings-overlay-opacity-slider")
                .accessibilityLabel("Overlay opacity")
                .accessibilityValue("\(Int((opacity.wrappedValue * 100).rounded())) percent")
            Text("\(Int((opacity.wrappedValue * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Layer Indicator Toggle

struct LayerIndicatorToggle: View {
    @AppStorage("KeyPath.layerIndicatorDisabled") private var disabled: Bool = true

    var body: some View {
        SettingsToggleRow(
            title: "Layer change notification",
            subtitle: "Banner and sound when switching layers.",
            isOn: Binding(get: { !disabled }, set: { disabled = !$0 }),
            identifier: "settings-layer-indicator-toggle"
        )
    }
}

// MARK: - Verbose Logging Toggle

struct VerboseLoggingToggle: View {
    @Environment(KanataViewModel.self) var kanataManager
    @Environment(\.services) private var services
    @State private var verboseLogging = PreferencesService.shared.verboseKanataLogging
    @State private var showingRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsToggleRow(
                title: "Verbose Logging", subtitle: "May impact performance",
                help: "Detailed Kanata trace logs for debugging",
                isOn: $verboseLogging, identifier: "settings-verbose-logging-toggle"
            )
            .onChange(of: verboseLogging) { _, newValue in
                services.preferences.verboseKanataLogging = newValue
                showingRestartAlert = true
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
        .alert("Service Restart Required", isPresented: $showingRestartAlert) {
            Button("Later", role: .cancel) {}
            Button("Restart Now") {
                Task {
                    await restartKeyPathRuntime()
                }
            }
        } message: {
            Text(
                "Kanata needs to restart for the new logging setting to take effect. Would you like to restart now?"
            )
        }
    }

    private func restartKeyPathRuntime() async {
        AppLogger.shared.log("\u{1F504} [VerboseLogging] Restarting KeyPath Runtime with new logging flags")
        let success = await kanataManager.restartKanata(reason: "Verbose logging toggle")
        if !success {
            AppLogger.shared.error("\u{274C} [VerboseLogging] KeyPath Runtime restart failed after verbose toggle")
        }
    }
}
