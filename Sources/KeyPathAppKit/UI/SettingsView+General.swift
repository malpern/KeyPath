import KeyPathCore
import KeyPathWizardCore
import SwiftUI

// MARK: - General Settings Tab

private enum GeneralSettingsSection: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case virtualKeys = "Virtual Keys"
    #if DEBUG
        case experimental = "Experimental"
    #endif

    var id: String {
        rawValue
    }

    /// Sections to show based on feature flags and build configuration
    static var visibleSections: [GeneralSettingsSection] {
        var sections: [GeneralSettingsSection] = [.settings]
        if FeatureFlags.simulatorAndVirtualKeysEnabled {
            sections.append(.virtualKeys)
        }
        #if DEBUG
            sections.append(.experimental)
        #endif
        return sections
    }
}

struct GeneralSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var settingsToastManager = WizardToastManager()
    @State private var selectedSection: GeneralSettingsSection = .settings
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @State private var showingKeymapInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control for section switching
            Picker("Section", selection: $selectedSection) {
                ForEach(GeneralSettingsSection.visibleSections) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .accessibilityIdentifier("settings-general-section-picker")

            // Content based on selected section
            Group {
                switch selectedSection {
                case .settings:
                    generalSettingsContent
                case .virtualKeys:
                    if FeatureFlags.simulatorAndVirtualKeysEnabled {
                        VirtualKeysInspectorView()
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                #if DEBUG
                    case .experimental:
                        ExperimentalSettingsSection()
                #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
    }

    // MARK: - General Settings Content

    private var generalSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 40) {
                    // Left: Logs
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Logs")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 30) {
                            // KeyPath Log
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)

                                Text("KeyPath log")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("Open") {
                                    openLogFile(NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("settings-open-keypath-log-button")
                                .accessibilityLabel("Open KeyPath log")
                            }

                            // Kanata Log
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.green)

                                Text("Kanata log")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button("Open") {
                                    openLogFile("/var/log/kanata.log")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("settings-open-kanata-log-button")
                                .accessibilityLabel("Open Kanata log")
                            }
                        }
                    }
                    .frame(minWidth: 220)

                    // Right: Recording Settings
                    VStack(alignment: .leading, spacing: 20) {
                        // Capture Mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Capture Mode")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Picker(
                                "",
                                selection: Binding(
                                    get: { PreferencesService.shared.isSequenceMode },
                                    set: { PreferencesService.shared.isSequenceMode = $0 }
                                )
                            ) {
                                Label {
                                    Text("Sequences - Keys one after another")
                                } icon: {
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                }
                                .tag(true)

                                Label {
                                    Text("Combos - Keys together")
                                } icon: {
                                    Image(systemName: "command")
                                        .foregroundColor(.secondary)
                                }
                                .tag(false)
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                            .accessibilityIdentifier("settings-capture-mode-picker")
                            .accessibilityLabel("Capture Mode")
                        }

                        // Recording Behavior
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recording Behavior")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Picker(
                                "",
                                selection: Binding(
                                    get: { PreferencesService.shared.applyMappingsDuringRecording },
                                    set: { PreferencesService.shared.applyMappingsDuringRecording = $0 }
                                )
                            ) {
                                Label {
                                    Text("Physical keys only (pause mappings)")
                                } icon: {
                                    Image(systemName: "keyboard")
                                        .foregroundColor(.secondary)
                                }
                                .tag(false)

                                Label {
                                    Text("Include KeyPath mappings")
                                } icon: {
                                    Image(systemName: "wand.and.stars")
                                        .foregroundColor(.blue)
                                }
                                .tag(true)
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                            .accessibilityIdentifier("settings-recording-behavior-picker")
                            .accessibilityLabel("Recording Behavior")
                        }

                        // Overlay Settings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keyboard Overlay")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Picker("Layout", selection: $selectedLayoutId) {
                                ForEach(PhysicalLayout.all) { layout in
                                    Text(layout.name).tag(layout.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                            .accessibilityIdentifier("settings-overlay-layout-picker")
                            .accessibilityLabel("Keyboard Overlay Layout")

                            HStack(spacing: 6) {
                                Picker("Keymap", selection: $selectedKeymapId) {
                                    ForEach(LogicalKeymap.all) { keymap in
                                        Text(keymap.name).tag(keymap.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 200)
                                .accessibilityIdentifier("settings-overlay-keymap-picker")
                                .accessibilityLabel("Keyboard Overlay Keymap")

                                Button {
                                    showingKeymapInfo.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Keymap details")
                                .popover(isPresented: $showingKeymapInfo) {
                                    KeymapInfoPopover(keymap: selectedKeymap)
                                }
                            }

                            Button("Reset Overlay Size") {
                                LiveKeyboardOverlayController.shared.resetWindowFrame()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Reset the keyboard overlay to its default size and position")
                            .accessibilityIdentifier("settings-reset-overlay-size-button")
                            .accessibilityLabel("Reset Overlay Size")
                        }

                        // Context HUD Settings
                        ContextHUDSettingsSection()
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
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

    private var selectedKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }
}

private struct KeymapInfoPopover: View {
    let keymap: LogicalKeymap

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(keymap.name)
                .font(.headline)
            Text(keymap.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Learn more", destination: keymap.learnMoreURL)
        }
        .padding(12)
        .frame(maxWidth: 260)
    }
}
