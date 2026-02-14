import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

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
