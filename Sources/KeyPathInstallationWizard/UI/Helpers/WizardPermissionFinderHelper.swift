import AppKit
import KeyPathCore

/// Finder and clipboard actions for KeyPath.app permission setup.
@MainActor
enum WizardPermissionFinderHelper {
    static func revealKeyPathApp() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
        WizardWindowManager.shared.markFinderWindowOpened(forPath: appURL.path)
    }

    static func copyPathToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Bundle.main.bundlePath, forType: .string)
    }

    /// Opens System Settings to the Accessibility pane.
    static func openAccessibilitySettings() {
        let url = URL(string: KeyPathConstants.URLs.accessibilityPrivacy)!
        NSWorkspace.shared.open(url)
    }

    /// Opens System Settings to the Input Monitoring pane.
    static func openInputMonitoringSettings() {
        let url = URL(string: KeyPathConstants.URLs.inputMonitoringPrivacy)!
        NSWorkspace.shared.open(url)
    }
}
