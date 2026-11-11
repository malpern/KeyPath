import SwiftUI

/// Update preferences. Sparkle stores them; Info.plist supplies only the first
/// defaults (check daily, install automatically on Quit).
struct UpdatesSettingsSection: View {
    @State private var updateService = UpdateService.shared

    var body: some View {
        SettingsSection(title: "Updates") {
            SettingsCard {
                VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                    if updateService.usesManualDownloads {
                        Text("Download the latest version, then quit KeyPath before replacing the app. Your rules are kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        SettingsToggleRow(
                            title: "Check for updates automatically",
                            subtitle: "Once a day.",
                            isOn: Binding(get: { updateService.automaticallyChecksForUpdates },
                                          set: { updateService.setAutomaticChecks(enabled: $0) }),
                            identifier: "settings-updates-auto-check-toggle"
                        )
                        SettingsToggleRow(
                            title: "Download and install updates automatically",
                            subtitle: "Installs when you quit KeyPath. Your rules are kept.",
                            isOn: Binding(get: { updateService.automaticallyDownloadsUpdates },
                                          set: { updateService.setAutomaticDownloads(enabled: $0) }),
                            identifier: "settings-updates-auto-install-toggle"
                        )
                        .disabled(!updateService.allowsAutomaticUpdates)
                        HStack {
                            Text("Channel").font(.subheadline.weight(.medium))
                            Spacer()
                            Picker("Update channel", selection: Binding(
                                get: { updateService.updateChannel },
                                set: { updateService.setUpdateChannel($0) }
                            )) {
                                ForEach(UpdateChannel.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 140)
                            .accessibilityIdentifier("settings-updates-channel-picker")
                        }
                    }
                    Button(updateService.usesManualDownloads ? "Download Update…" : "Check for Updates…") {
                        updateService.checkForUpdates()
                    }
                    .settingsAction()
                    .disabled(!updateService.canCheckForUpdates)
                    .accessibilityIdentifier("settings-updates-check-button")
                    if let error = updateService.preparationError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-updates-preparation-error")
                    }
                }
            }
        }
    }
}
