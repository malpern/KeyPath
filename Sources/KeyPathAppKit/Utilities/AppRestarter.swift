import AppKit
import Foundation
import KeyPathCore

/// Utility for restarting the application
enum AppRestarter {
    #if DEBUG
        // Allow tests to inject an isolated UserDefaults suite to avoid cross-test interference.
        private nonisolated(unsafe) static var userDefaults: UserDefaults = .standard
        static func setUserDefaults(_ defaults: UserDefaults) {
            userDefaults = defaults
        }
    #else
        private static let userDefaults: UserDefaults = .standard
    #endif
    /// Restarts the application after a brief delay
    /// - Parameter afterDelay: Delay in seconds before restarting (default: 0.5)
    static func restart(afterDelay delay: TimeInterval = 0.5) {
        AppLogger.shared.log("🔄 [AppRestarter] Preparing to restart KeyPath...")

        // Get the app's path
        let appPath = Bundle.main.bundlePath

        // Create a launch task that will run after the app quits
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", appPath]

        // Schedule the relaunch after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            do {
                try task.run()
                AppLogger.shared.log("✅ [AppRestarter] Relaunch scheduled")

                // Now quit the current instance
                NSApplication.shared.terminate(nil)
            } catch {
                AppLogger.shared.log("❌ [AppRestarter] Failed to schedule relaunch: \(error)")

                // Fallback: Just quit and let user manually restart
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Saves wizard state and restarts the application
    /// - Parameter wizardPage: The current wizard page to restore on restart
    static func restartForWizard(at wizardPage: String) {
        // Save restoration point
        userDefaults.set(wizardPage, forKey: "KeyPath.WizardRestorePoint")
        userDefaults.set(Date().timeIntervalSince1970, forKey: "KeyPath.WizardRestoreTime")
        userDefaults.synchronize() // Force immediate save

        AppLogger.shared.log("💾 [AppRestarter] Saved wizard state: \(wizardPage)")

        // Skip actual restart in test environment (UserDefaults save is what we test)
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName.lowercased().contains("xctest")
            || env["SWIFTPM_MODULECACHE_OVERRIDE"] != nil
        {
            AppLogger.shared.log("🧪 [AppRestarter] Test mode - skipping app restart")
            return
        }

        // Restart the app
        restart(afterDelay: 0.3)
    }
}
