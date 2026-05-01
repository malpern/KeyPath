import AppKit
import KeyPathCore

/// Shared utility for revealing kanata-launcher in Finder during permission setup.
/// Used by both WizardAccessibilityPage and WizardInputMonitoringPage.
@MainActor
enum WizardPermissionFinderHelper {
    private static var hiddenPaths: [String] = []

    /// Reveals kanata-launcher in Finder with sibling files hidden.
    /// Hides other files in the same directory so the user sees only kanata-launcher.
    /// Call `restoreHiddenFiles()` when the wizard closes to unhide them.
    static func revealKanataLauncher() {
        let launcherPath = WizardSystemPaths.bundledKanataLauncherPath
        let dir = (launcherPath as NSString).deletingLastPathComponent

        // Hide sibling files so only kanata-launcher is visible
        hideOtherFiles(in: dir, except: "kanata-launcher")

        // Set KeyPath icon on the launcher so it's recognizable
        if let appIcon = NSApp.applicationIconImage {
            NSWorkspace.shared.setIcon(appIcon, forFile: launcherPath)
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: launcherPath)])
        WizardWindowManager.shared.markFinderWindowOpened(forPath: launcherPath)
        AppLogger.shared.log("📂 [PermissionFinder] Revealed kanata-launcher: \(launcherPath)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            positionSettingsAndFinderSideBySide()
        }
    }

    /// Restores all files hidden by `revealKanataLauncher()`.
    /// Call on wizard close or app launch to clean up.
    static func restoreHiddenFiles() {
        for path in hiddenPaths {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
            process.arguments = ["nohidden", path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
        if !hiddenPaths.isEmpty {
            AppLogger.shared.log("📂 [PermissionFinder] Restored \(hiddenPaths.count) hidden files")
        }
        hiddenPaths.removeAll()
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

    // MARK: - Private

    private static func hideOtherFiles(in directory: String, except keepName: String) {
        restoreHiddenFiles()

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        for name in contents where name != keepName && !name.hasPrefix(".") {
            let path = (directory as NSString).appendingPathComponent(name)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
            process.arguments = ["hidden", path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                hiddenPaths.append(path)
            }
        }
        AppLogger.shared.log("📂 [PermissionFinder] Hidden \(hiddenPaths.count) sibling files in \(directory)")
    }

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
