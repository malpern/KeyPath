import AppKit
import KeyPathCore

/// Shared utility for revealing kanata-launcher in Finder during permission setup.
/// Used by both WizardAccessibilityPage and WizardInputMonitoringPage.
@MainActor
enum WizardPermissionFinderHelper {
    private static let stagingDir: String = {
        let path = NSHomeDirectory() + "/Library/Application Support/KeyPath/Permissions"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    /// Reveals kanata-launcher in a clean Finder folder with the KeyPath icon.
    /// Creates a hard link in a staging directory so users see only one file.
    static func revealKanataLauncher() {
        let sourcePath = WizardSystemPaths.bundledKanataLauncherPath
        let linkPath = (stagingDir as NSString).appendingPathComponent("kanata-launcher")

        let fm = FileManager.default
        try? fm.removeItem(atPath: linkPath)
        do {
            try fm.linkItem(atPath: sourcePath, toPath: linkPath)
        } catch {
            AppLogger.shared.warn("⚠️ [PermissionFinder] Hard link failed, falling back: \(error.localizedDescription)")
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: sourcePath)])
            return
        }

        if let appIcon = NSApp.applicationIconImage {
            NSWorkspace.shared.setIcon(appIcon, forFile: linkPath)
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: linkPath)])
        WizardWindowManager.shared.markFinderWindowOpened(forPath: linkPath)
        AppLogger.shared.log("📂 [PermissionFinder] Revealed kanata-launcher in clean folder: \(linkPath)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            positionSettingsAndFinderSideBySide()
        }
    }

    /// Copies the kanata-launcher path to the clipboard.
    static func copyPathToClipboard() {
        let path = WizardSystemPaths.bundledKanataLauncherPath
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path, forType: .string)
        AppLogger.shared.log("📋 [PermissionFinder] Copied kanata-launcher path to clipboard: \(path)")
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

    /// Position System Settings and Finder windows side-by-side for easy drag-and-drop.
    private static func positionSettingsAndFinderSideBySide() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let windowWidth = screenFrame.width / 2
        let windowHeight = screenFrame.height * 0.8
        let yPosition = screenFrame.minY + (screenFrame.height - windowHeight) / 2

        let settingsFrame = NSRect(
            x: screenFrame.minX,
            y: yPosition,
            width: windowWidth,
            height: windowHeight
        )
        let finderFrame = NSRect(
            x: screenFrame.minX + windowWidth,
            y: yPosition,
            width: windowWidth,
            height: windowHeight
        )

        for window in NSApp.windows where window.title.contains("Settings") || window.title.contains("Preferences") {
            window.setFrame(settingsFrame, display: true, animate: true)
        }

        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        if !finderApp.isEmpty {
            for window in CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [] {
                if let ownerName = window[kCGWindowOwnerName as String] as? String,
                   ownerName == "Finder",
                   let windowNumber = window[kCGWindowNumber as String] as? Int
                {
                    if let nsWindow = NSApp.window(withWindowNumber: windowNumber) {
                        nsWindow.setFrame(finderFrame, display: true, animate: true)
                    }
                }
            }
        }

        AppLogger.shared.log("📐 [PermissionFinder] Positioned Settings and Finder side-by-side")
    }
}
