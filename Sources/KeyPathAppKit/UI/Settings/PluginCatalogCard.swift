import AppKit
import KeyPathCore
import KeyPathPluginKit
import SwiftUI

/// Shows available (not yet installed) plugins with a download/install action.
///
/// When no plugins are loaded, this card appears in Settings > Experimental
/// to let users discover and install optional add-ons like Activity Insights.
struct PluginCatalogCard: View {
    let entry: PluginCatalogEntry
    private var pluginManager: PluginManager {
        PluginManager.shared
    }

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

            // Install button / progress
            HStack(spacing: 10) {
                if pluginManager.isInstalling {
                    if let progress = pluginManager.installProgress {
                        ProgressView(value: progress)
                            .frame(maxWidth: 140)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(pluginManager.installProgressMessage ?? "Installing\u{2026}")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Cancel") {
                        pluginManager.cancelInstall()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("plugin-cancel-\(entry.id)")
                } else {
                    Button {
                        pluginManager.beginInstall(from: entry.downloadURL)
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

            if let installError = pluginManager.installError, !pluginManager.isInstalling {
                Text(installError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plugin-install-error-\(entry.id)")
            }

            // Learn more link
            Button("Learn more\u{2026}") {
                if let url = URL(string: "https://keypath-app.com/docs/plugins") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.caption)
            .accessibilityIdentifier("plugin-learn-more-\(entry.id)")
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

/// Wraps an `NSViewController` (from a plugin's `makeSettingsViewController()`)
/// for embedding in SwiftUI.
struct PluginSettingsViewWrapper: NSViewControllerRepresentable {
    let plugin: any KeyPathPlugin

    func makeNSViewController(context _: Context) -> NSViewController {
        plugin.makeSettingsViewController()
    }

    func updateNSViewController(_: NSViewController, context _: Context) {}
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

            // Plugin's own settings view (via NSViewControllerRepresentable)
            PluginSettingsViewWrapper(plugin: plugin)

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
                _ = PluginManager.shared.removePlugin(identifier: type(of: plugin).identifier)
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
