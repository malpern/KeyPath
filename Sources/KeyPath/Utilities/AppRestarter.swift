import AppKit
import KeyPathCore
import Foundation

/// Utility for restarting the application
enum AppRestarter {
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
        UserDefaults.standard.set(wizardPage, forKey: "KeyPath.WizardRestorePoint")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "KeyPath.WizardRestoreTime")
        UserDefaults.standard.synchronize() // Force immediate save

        AppLogger.shared.log("💾 [AppRestarter] Saved wizard state: \(wizardPage)")

        // Restart the app
        restart(afterDelay: 0.3)
    }
}
