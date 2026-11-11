import AppKit
import KeyPathCore
import KeyPathPluginKit
import SwiftUI

/// Wraps an `NSViewController` (from a plugin's `makeSettingsViewController()`)
/// for embedding in SwiftUI.
struct PluginSettingsViewWrapper: NSViewControllerRepresentable {
    let plugin: any KeyPathPlugin

    func makeNSViewController(context _: Context) -> NSViewController {
        plugin.makeSettingsViewController()
    }

    func updateNSViewController(_: NSViewController, context _: Context) {}
}

/// Shows a built-in plugin's own settings view.
struct InstalledPluginCard: View {
    let plugin: any KeyPathPlugin

    var body: some View {
        PluginSettingsViewWrapper(plugin: plugin)
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
