import AppKit
import KeyPathCore
import SwiftUI

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
