import KeyPathCore
import KeyPathPluginKit
import SwiftUI

/// Shows available (not yet installed) plugins with a download/install action.
///
/// When no plugins are loaded, this card appears in Settings > Experimental
/// to let users discover and install optional add-ons like Activity Insights.
struct PluginCatalogCard: View {
    let entry: PluginCatalogEntry
    @State private var installFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("OPTIONAL ADD-ON")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .tracking(0.5)

            // Plugin name
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.cyan)
                    .font(.title3)
                Text(entry.displayName)
                    .font(.headline)
            }

            // Description
            Text("This feature is not installed.")
                .font(.subheadline)
                .foregroundColor(.primary)

            Text(entry.description)
                .font(.caption)
                .foregroundColor(.secondary)

            // Privacy bullets
            VStack(alignment: .leading, spacing: 4) {
                privacyBullet("All data stays on your device")
                privacyBullet("Nothing is collected until you install")
                privacyBullet("You can remove the plugin at any time")
            }
            .padding(.vertical, 4)

            // Install button
            HStack {
                if PluginManager.shared.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                    Text(PluginManager.shared.installProgressMessage ?? "Installing\u{2026}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        Task {
                            let success = await PluginManager.shared.installPlugin(from: entry.downloadURL)
                            if !success {
                                installFailed = true
                            }
                        }
                    } label: {
                        Text("Download & Install")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("plugin-install-\(entry.id)")

                    Text("(\(entry.estimatedSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if installFailed {
                Text("Installation failed. Check your internet connection and try again.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Learn more link
            Button("Learn more\u{2026}") {
                if let url = URL(string: "https://keypath-app.com/docs/plugins") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private func privacyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Shows a loaded plugin's settings view with an installed badge and remove option.
struct InstalledPluginCard: View {
    let plugin: any KeyPathPlugin
    @State private var showRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Installed badge
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Installed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                Spacer()
            }

            // Plugin's own settings view
            plugin.settingsView()

            Divider()

            // Remove button
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Remove Plugin", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.red)
            .accessibilityIdentifier("plugin-remove-\(type(of: plugin).identifier)")
        }
        .alert("Remove Plugin?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    _ = await PluginManager.shared.removePlugin(identifier: type(of: plugin).identifier)
                }
            }
        } message: {
            Text("This will remove \(type(of: plugin).displayName) and delete its bundle. Your logged data will be preserved.")
        }
    }
}

/// Identifiable wrapper for use in ForEach with existential KeyPathPlugin.
struct PluginWrapper: Identifiable {
    let id: String
    let plugin: any KeyPathPlugin

    init(_ plugin: any KeyPathPlugin) {
        id = type(of: plugin).identifier
        self.plugin = plugin
    }
}
