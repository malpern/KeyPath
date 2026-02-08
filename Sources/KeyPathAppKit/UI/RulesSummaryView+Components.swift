import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Helper view for home row key button - extracted to reduce view body complexity
struct HomeRowKeyButton: View {
    let key: String
    let modSymbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-home-row-key-button-\(key)")
        .accessibilityLabel("Customize \(key.uppercased()) key")
    }
}

// MARK: - Toast View (shared with ContentView)

struct ToastView: View {
    let message: String
    let type: KanataViewModel.ToastType

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)

            Text(message)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }

    private var iconName: String {
        switch type {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch type {
        case .success: .green
        case .error: .red
        case .info: .blue
        case .warning: .orange
        }
    }
}

// MARK: - Keycap Style

/// View modifier that applies overlay-style keycap appearance
struct KeycapStyle: ViewModifier {
    /// Text color matching overlay keycaps (light blue-white)
    static let textColor = Color(red: 0.88, green: 0.93, blue: 1.0)

    /// Background color matching overlay keycaps (dark gray)
    static let backgroundColor = Color(white: 0.12)

    /// Corner radius matching overlay keycaps
    static let cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Self.backgroundColor)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - App Launch Chip

/// Displays an app icon and name in a keycap style for app launch actions
struct RulesSummaryAppLaunchChip: View {
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
                    .foregroundColor(KeycapStyle.textColor.opacity(0.6))
                    .frame(width: 16, height: 16)
            }

            // App name
            Text(appName ?? appIdentifier)
                .font(.body.monospaced().weight(.semibold))
                .foregroundColor(KeycapStyle.textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .fill(Color.accentColor.opacity(0.25))
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KeycapStyle.cornerRadius)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 0.5)
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

// MARK: - Rules Section Headers for Custom Rules

/// Compact section header for rule groups (e.g., "Everywhere")
struct RulesSectionHeaderCompact: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.bottom, 4)
    }
}

/// Compact section header for app-specific rules with app icon
struct AppRulesSectionHeaderCompact: View {
    let keymap: AppKeymap

    @State private var appIcon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            // App icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }

            Text(keymap.mapping.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.bottom, 4)
        .onAppear {
            loadAppIcon()
        }
    }

    private func loadAppIcon() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: keymap.mapping.bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 28, height: 28)
            appIcon = icon
        }
    }
}

/// Compact row for displaying an app-specific rule override
struct AppRuleRowCompact: View {
    let keymap: AppKeymap
    let override: AppKeyOverride
    let onEdit: () -> Void
    let onDelete: () -> Void
    let prettyKeyName: (String) -> String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Mapping content
                HStack(spacing: 8) {
                    // Input key
                    Text(prettyKeyName(override.inputKey))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())

                    Image(systemName: "arrow.right")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)

                    // Output key
                    Text(prettyKeyName(override.outputAction))
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundColor(KeycapStyle.textColor)
                        .modifier(KeycapStyle())

                    Spacer(minLength: 0)
                }

                Spacer()

                // Action buttons - subtle icons that appear on hover (matching MappingRowView)
                HStack(spacing: 4) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary.opacity(isHovered ? 1 : 0.5))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Spacer for alignment
                    Spacer()
                        .frame(width: 0)
                }
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            onEdit()
        }
    }
}
