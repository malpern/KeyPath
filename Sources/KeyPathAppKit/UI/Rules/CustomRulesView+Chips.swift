import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Inline Key Field

struct InlineKeyField: View {
    let title: String
    @Binding var text: String
    let options: [String]
    let fieldWidth: CGFloat
    let textFieldIdentifier: String
    let menuIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .accessibilityIdentifier(textFieldIdentifier)

                Menu {
                    ForEach(options, id: \.self) { key in
                        Button(key) {
                            text = key
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier(menuIdentifier)
            }
        }
    }
}

// MARK: - App Launch Chip

/// Displays an app icon and name in a chip style for app launch actions
struct AppLaunchChip: View {
    let appIdentifier: String

    @State private var appIcon: NSImage?
    @State private var appName: String?

    var body: some View {
        HStack(spacing: 6) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }

            // App name
            Text(appName ?? appIdentifier)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
        .onAppear {
            loadAppInfo()
        }
    }

    private func loadAppInfo() {
        let workspace = NSWorkspace.shared

        // Try to find app by bundle identifier first
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appIdentifier) {
            loadFromURL(appURL)
            return
        }

        // Try common paths
        let appName = appIdentifier.hasSuffix(".app") ? appIdentifier : "\(appIdentifier).app"
        let commonPaths = [
            "/Applications/\(appName)",
            "/System/Applications/\(appName)",
            "\(NSHomeDirectory())/Applications/\(appName)"
        ]

        for path in commonPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                loadFromURL(url)
                return
            }
        }

        // Fallback: use identifier as name (capitalize it)
        let parts = appIdentifier.replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map(\.capitalized)
        self.appName = parts.last.map { String($0) } ?? appIdentifier
    }

    private func loadFromURL(_ url: URL) {
        // Get icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32) // Request appropriate size
        appIcon = icon

        // Get app name from bundle
        if let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        {
            appName = name
        } else {
            // Use filename without extension
            appName = url.deletingPathExtension().lastPathComponent
        }
    }
}

// MARK: - URL Chip

/// Displays a favicon and domain in a chip style for URL actions
struct URLChip: View {
    let urlString: String

    @State private var favicon: NSImage?

    private var domain: String {
        KeyMappingFormatter.extractDomain(from: urlString)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }

            Text(domain)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .onAppear {
            Task { @MainActor in
                favicon = await FaviconFetcher.shared.fetchFavicon(for: urlString)
            }
        }
    }
}

// MARK: - System Action Chip

/// Displays an SF Symbol icon and action name in a chip style for system actions
struct SystemActionChip: View {
    let actionIdentifier: String

    /// Get action info from SystemActionInfo (single source of truth)
    private var actionInfo: (icon: String, name: String) {
        // Use SystemActionInfo as the single source of truth
        if let action = SystemActionInfo.find(byOutput: actionIdentifier) {
            return (action.sfSymbol, action.name)
        }
        // Fallback for unknown actions
        return ("gearshape.fill", actionIdentifier.capitalized)
    }

    var body: some View {
        HStack(spacing: 6) {
            // System action SF Symbol
            Image(systemName: actionInfo.icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)

            // Action name
            Text(actionInfo.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Layer Switch Chip

/// Displays a layer icon and "X Layer" name for layer-switch actions
struct LayerSwitchChip: View {
    let layerName: String

    /// The SF Symbol icon for this layer
    private var layerIcon: String {
        LayerInfo.iconName(for: layerName)
    }

    /// Human-readable display name with "Layer" suffix
    private var displayName: String {
        "\(LayerInfo.displayName(for: layerName)) Layer"
    }

    var body: some View {
        HStack(spacing: 5) {
            // Layer icon
            Image(systemName: layerIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)

            // Layer name (e.g., "Nav Layer")
            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Section Headers

/// Section header for rule groups (e.g., "Everywhere")
struct RulesSectionHeader: View {
    let title: String
    let systemImage: String
    let subtitle: String?

    init(title: String, systemImage: String, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Section header for app-specific rules with app icon
struct AppRulesSectionHeader: View {
    let keymap: AppKeymap

    @State private var appIcon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // App icon
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }

                Text(keymap.mapping.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            Text("Only applies when \(keymap.mapping.displayName) is active")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onAppear {
            loadAppIcon()
        }
    }

    private func loadAppIcon() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: keymap.mapping.bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 40, height: 40)
            appIcon = icon
        }
    }
}

// MARK: - App Rule Row

/// A row displaying an app-specific rule override
struct AppRuleRow: View {
    let keymap: AppKeymap
    let override: AppKeyOverride
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Key mapping display
            HStack(spacing: 8) {
                KeyCapChip(text: override.inputKey.uppercased())

                Text("→")
                    .font(.caption)
                    .foregroundColor(.secondary)

                KeyCapChip(text: override.outputAction.uppercased())
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("app-rule-delete-\(override.id)")
            .accessibilityLabel("Delete rule \(override.inputKey) to \(override.outputAction)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-rule-row-\(override.id)")
    }
}
