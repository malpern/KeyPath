import AppKit
import Foundation

/// Defines where Neovim Terminal reference content is allowed to appear.
@MainActor
enum NeovimTerminalScope {
    struct AppDescriptor: Identifiable, Hashable {
        let bundleIdentifier: String
        let displayName: String

        var id: String { bundleIdentifier }
    }

    /// Approved terminal apps for the Neovim reference experience.
    static let approvedApps: [AppDescriptor] = [
        .init(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal"),
        .init(bundleIdentifier: "com.googlecode.iterm2", displayName: "iTerm"),
        .init(bundleIdentifier: "dev.warp.Warp", displayName: "Warp"),
        .init(bundleIdentifier: "com.github.wez.wezterm", displayName: "WezTerm"),
        .init(bundleIdentifier: "com.mitchellh.ghostty", displayName: "Ghostty"),
        .init(bundleIdentifier: "org.alacritty", displayName: "Alacritty"),
        .init(bundleIdentifier: "net.kovidgoyal.kitty", displayName: "Kitty"),
        .init(bundleIdentifier: "com.raphaelamorim.rio", displayName: "Rio"),
        .init(bundleIdentifier: "co.zeit.hyper", displayName: "Hyper"),
        .init(bundleIdentifier: "org.tabby", displayName: "Tabby"),
    ]

    static func isApprovedTerminal(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return approvedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    static func installedApprovedApps() -> [AppDescriptor] {
        approvedApps.filter { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) != nil
        }
    }

    static func frontmostApprovedTerminal() -> AppDescriptor? {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return approvedApps.first { $0.bundleIdentifier == bundle }
    }
}
