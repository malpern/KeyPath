import AppKit
import KeyPathCore

/// Tracks windows opened by the wizard and provides cleanup utilities.
/// This ensures we only close windows we opened, not ones the user had open independently.
@MainActor
public final class WizardWindowManager {
    public static let shared = WizardWindowManager()

    private init() {}

    // MARK: - Window Tracking

    /// Track whether we opened System Settings during this wizard session
    public private(set) var didOpenSystemSettings = false

    /// Track whether we opened a Finder window during this wizard session
    public private(set) var didOpenFinderWindow = false

    /// Track the path we revealed in Finder (to close the right window)
    public private(set) var revealedFinderPath: String?

    // MARK: - Mark Windows as Opened

    public func markSystemSettingsOpened() {
        didOpenSystemSettings = true
        AppLogger.shared.log("📝 [WizardWindowManager] Marked System Settings as wizard-opened")
    }

    public func markFinderWindowOpened(forPath path: String) {
        didOpenFinderWindow = true
        revealedFinderPath = path
        AppLogger.shared.log("📝 [WizardWindowManager] Marked Finder window as wizard-opened for: \(path)")
    }

    /// Reset tracking (call when wizard closes)
    public func resetTracking() {
        didOpenSystemSettings = false
        didOpenFinderWindow = false
        revealedFinderPath = nil
        AppLogger.shared.log("🔄 [WizardWindowManager] Reset window tracking")
    }

    // MARK: - Cleanup Actions

    /// Close System Settings if we opened it
    public func closeSystemSettingsIfWeOpenedIt() {
        guard didOpenSystemSettings else {
            AppLogger.shared.log("🧹 [WizardWindowManager] Skipping System Settings close (we didn't open it)")
            return
        }

        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.systempreferences"
        )
        guard !runningApps.isEmpty else {
            AppLogger.shared.log("🧹 [WizardWindowManager] System Settings not running")
            didOpenSystemSettings = false
            return
        }

        let script = """
        tell application "System Settings"
            quit
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                AppLogger.shared.warn("⚠️ [WizardWindowManager] Failed to close System Settings: \(error)")
            } else {
                AppLogger.shared.log("🧹 [WizardWindowManager] Closed System Settings")
                didOpenSystemSettings = false
            }
        }
    }

    /// Close Finder window if we opened it for revealing a file
    public func closeFinderWindowIfWeOpenedIt() {
        guard didOpenFinderWindow, let path = revealedFinderPath else {
            AppLogger.shared.log("🧹 [WizardWindowManager] Skipping Finder close (we didn't open it)")
            return
        }

        // Get the folder path we revealed
        let folderPath = (path as NSString).deletingLastPathComponent

        // Use AppleScript to close just the Finder window showing this folder
        let script = """
        tell application "Finder"
            set targetFolder to POSIX file "\(folderPath)" as alias
            repeat with w in windows
                try
                    if (target of w as alias) is targetFolder then
                        close w
                        exit repeat
                    end if
                end try
            end repeat
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                AppLogger.shared.warn("⚠️ [WizardWindowManager] Failed to close Finder window: \(error)")
            } else {
                AppLogger.shared.log("🧹 [WizardWindowManager] Closed Finder window for: \(folderPath)")
            }
        }

        didOpenFinderWindow = false
        revealedFinderPath = nil
    }

    /// Perform full cleanup: close windows we opened and focus KeyPath
    public func performFullCleanup() {
        closeSystemSettingsIfWeOpenedIt()
        closeFinderWindowIfWeOpenedIt()
        focusKeyPath()
    }

    /// Bring KeyPath to the front
    public func focusKeyPath() {
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.shared.log("🎯 [WizardWindowManager] Activated KeyPath window")
    }

    /// Bounce the dock icon to get user's attention
    public func bounceDocIcon() {
        NSApp.requestUserAttention(.informationalRequest)
        AppLogger.shared.log("🔔 [WizardWindowManager] Requested user attention (dock bounce)")
    }
}
