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
        private nonisolated(unsafe) static let userDefaults: UserDefaults = .standard
    #endif
    /// Restarts the application after a brief delay
    /// - Parameter afterDelay: Delay in seconds before restarting (default: 0.5)
    static func restart(afterDelay delay: TimeInterval = 0.5) {
        AppLogger.shared.log("🔄 [AppRestarter] Preparing to restart KeyPath...")

        // Get the app's path
        let appPath = Bundle.main.bundlePath

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: config) { _, error in
                if let error {
                    AppLogger.shared.log("❌ [AppRestarter] Failed to relaunch: \(error)")
                } else {
                    AppLogger.shared.log("✅ [AppRestarter] Relaunch scheduled")
                }
            }
            NSApplication.shared.terminate(nil)
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
