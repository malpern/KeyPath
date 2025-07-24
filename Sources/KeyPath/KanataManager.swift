import Foundation
import SwiftUI
import IOKit.hidsystem
import ApplicationServices

/// Manages the Kanata process lifecycle and configuration via the PrivilegedHelperManager.
@MainActor
class KanataManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    
    private let helperManager = PrivilegedHelperManager.shared
    private let configDirectory = "\(NSHomeDirectory())/Library/Application Support/KeyPath"
    private let configFileName = "keypath.kbd"
    
    var configPath: String {
        "\(configDirectory)/\(configFileName)"
    }
    
    init() {
        Task {
            await updateStatus()
            // Try to start Kanata automatically on launch if everything is set up.
            if isCompletelyInstalled() && hasAllRequiredPermissions() {
                await startKanata()
            }
        }
    }
    
    // MARK: - Public Interface
    
    func startKanata() async {
        AppLogger.shared.log("🚀 [Start] Requesting helper to start Kanata...")
        let (success, error) = await helperManager.startKanata()
        if success {
            self.isRunning = true
            self.lastError = nil
            AppLogger.shared.log("✅ [Start] Helper successfully started Kanata.")
        } else {
            self.isRunning = false
            self.lastError = error ?? "An unknown error occurred while starting Kanata."
            AppLogger.shared.log("❌ [Start] Helper failed to start Kanata: \(self.lastError ?? "nil")")
        }
        await updateStatus()
    }
    
    func stopKanata() async {
        AppLogger.shared.log("🛑 [Stop] Requesting helper to stop Kanata...")
        let (success, error) = await helperManager.stopKanata()
        if success {
            self.isRunning = false
            self.lastError = nil
            AppLogger.shared.log("✅ [Stop] Helper successfully stopped Kanata.")
        } else {
            // Even if stopping fails, the process might already be dead.
            self.isRunning = false
            self.lastError = error
            AppLogger.shared.log("❌ [Stop] Helper failed to stop Kanata: \(self.lastError ?? "nil")")
        }
        await updateStatus()
    }
    
    func restartKanata() async {
        AppLogger.shared.log("🔄 [Restart] Requesting helper to restart Kanata...")
        // The helper's startKanata function handles killing the old process.
        await startKanata()
    }
    
    func saveConfiguration(input: String, output: String) async throws {
        let config = "// Simplified config for testing\n(defcfg process-unmapped-keys yes)\n(defsrc caps)\n(deflayer base esc)"
        
        let configDir = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        let configURL = URL(fileURLWithPath: configPath)
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        
        AppLogger.shared.log("💾 [Config] Configuration saved successfully to \(configPath)")
        AppLogger.shared.log("🔄 [Config] Restarting Kanata service to apply changes...")
        await restartKanata()
    }
    
    func updateStatus() async {
        // With the new model, isRunning is set directly by the start/stop commands.
        // We can still use pgrep as a secondary check if needed, but for now, we trust our state.
        let pgrepRunning = false // Simplified for testing
        if self.isRunning != pgrepRunning {
            AppLogger.shared.log("⚠️ [Status] Internal running state (\(self.isRunning)) differs from pgrep (\(pgrepRunning)). Synchronizing.")
            self.isRunning = pgrepRunning
        }
    }

    /// Stop Kanata when the app is terminating.
    func cleanup() async {
        await stopKanata()
    }

    // MARK: - Installation and Permissions

    func isInstalled() -> Bool {
        let kanataPath = "/usr/local/bin/kanata-cmd"
        return FileManager.default.fileExists(atPath: kanataPath)
    }

    func isHelperInstalled() -> Bool {
        return helperManager.isHelperInstalled()
    }

    func isCompletelyInstalled() -> Bool {
        return isInstalled() && isHelperInstalled()
    }

    func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let hasAccess = accessType == kIOHIDAccessTypeGranted
            AppLogger.shared.log("🔍 [Permission] IOHIDCheckAccess returned: \(accessType), hasAccess: \(hasAccess)")
            return hasAccess
        } else {
            let hasAccess = AXIsProcessTrusted()
            AppLogger.shared.log("🔍 [Permission] AXIsProcessTrusted (fallback) returned: \(hasAccess)")
            return hasAccess
        }
    }

    func hasAccessibilityPermission() -> Bool {
        let hasAccess = AXIsProcessTrusted()
        AppLogger.shared.log("🔍 [Permission] AXIsProcessTrusted returned: \(hasAccess)")
        return hasAccess
    }
    
    func checkAccessibilityForPath(_ path: String) -> Bool {
        // Check if a specific binary path has accessibility permissions
        // This is done by checking the TCC database for the specific path
        let _ = path.split(separator: "/").last ?? ""
        
        // First try to check using TCC database
        let tccCheck = checkTCCForAccessibility(path: path)
        if tccCheck {
            return true
        }
        
        // If the path is kanata-cmd, we can also check if it's listed in the TCC database
        if path.contains("kanata-cmd") {
            let process = Process()
            process.launchPath = "/usr/bin/sqlite3"
            process.arguments = ["/Library/Application Support/com.apple.TCC/TCC.db",
                               "SELECT client FROM access WHERE service='kTCCServiceAccessibility' AND auth_value=2 AND client LIKE '%kanata%';"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8) ?? ""
                return result.contains("kanata")
            } catch {
                return false
            }
        }
        
        return false
    }
    
    private func checkTCCForAccessibility(path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = ["/Library/Application Support/com.apple.TCC/TCC.db",
                         ".mode column",
                         "SELECT client, auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%\(path.split(separator: "/").last ?? "")%';"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Check if any line contains auth_value=2 (allowed)
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("2") { // auth_value=2 means allowed
                    return true
                }
            }
            return false
        } catch {
            AppLogger.shared.log("❌ [TCC] Error checking accessibility for \(path): \(error)")
            return false
        }
    }
    
    func checkBothAppsHavePermissions() -> (keyPathHasPermission: Bool, kanataHasPermission: Bool, permissionDetails: String) {
        let keyPathPath = Bundle.main.bundlePath
        let kanataPath = "/usr/local/bin/kanata-cmd"
        
        let keyPathHasInputMonitoring = hasInputMonitoringPermission()
        let keyPathHasAccessibility = hasAccessibilityPermission()
        
        let kanataHasInputMonitoring = checkTCCForInputMonitoring(path: kanataPath)
        let kanataHasAccessibility = checkAccessibilityForPath(kanataPath)
        
        let keyPathOverall = keyPathHasInputMonitoring && keyPathHasAccessibility
        let kanataOverall = kanataHasInputMonitoring && kanataHasAccessibility
        
        let details = """
        KeyPath.app (\(keyPathPath)):
        - Input Monitoring: \(keyPathHasInputMonitoring ? "✅" : "❌")
        - Accessibility: \(keyPathHasAccessibility ? "✅" : "❌")
        
        kanata-cmd (\(kanataPath)):
        - Input Monitoring: \(kanataHasInputMonitoring ? "✅" : "❌") 
        - Accessibility: \(kanataHasAccessibility ? "✅" : "❌")
        """
        
        return (keyPathOverall, kanataOverall, details)
    }
    
    private func checkTCCForInputMonitoring(path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = ["/Library/Application Support/com.apple.TCC/TCC.db",
                         ".mode column", 
                         "SELECT client, auth_value FROM access WHERE service='kTCCServiceListenEvent' AND client LIKE '%\(path.split(separator: "/").last ?? "")%';"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Check if any line contains auth_value=2 (allowed)
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("2") { // auth_value=2 means allowed
                    return true
                }
            }
            return false
        } catch {
            AppLogger.shared.log("❌ [TCC] Error checking input monitoring for \(path): \(error)")
            return false
        }
    }
    

    func hasAllRequiredPermissions() -> Bool {
        return hasInputMonitoringPermission() && hasAccessibilityPermission()
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
            }
        }
    }

    func isKarabinerDriverInstalled() -> Bool {
        // Check if Karabiner VirtualHID driver is installed
        let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
        return FileManager.default.fileExists(atPath: driverPath)
    }


    func performTransparentInstallation() async -> Bool {
        AppLogger.shared.log("🔧 [Installation] Starting transparent installation...")
        
        // Modern approach: Install PrivilegedHelper instead of LaunchDaemon
        let helperManager = PrivilegedHelperManager.shared
        
        do {
            // 1. Install the privileged helper
            AppLogger.shared.log("🔧 [Installation] Installing privileged helper...")
            let helperSuccess = await helperManager.installHelper()
            
            if !helperSuccess {
                AppLogger.shared.log("❌ [Installation] Failed to install privileged helper")
                return false
            }
            
            AppLogger.shared.log("✅ [Installation] Privileged helper installed successfully")
            
            // 2. Ensure Kanata binary exists (should already be checked)
            let kanataBinaryPath = "/usr/local/bin/kanata-cmd"
            if !FileManager.default.fileExists(atPath: kanataBinaryPath) {
                AppLogger.shared.log("❌ [Installation] Kanata binary not found at \(kanataBinaryPath)")
                return false
            }
            
            AppLogger.shared.log("✅ [Installation] Kanata binary verified at \(kanataBinaryPath)")
            
            // 3. Check if Karabiner driver is installed
            let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
            if !FileManager.default.fileExists(atPath: driverPath) {
                AppLogger.shared.log("⚠️ [Installation] Karabiner driver not found at \(driverPath)")
                AppLogger.shared.log("ℹ️ [Installation] User should install Karabiner-Elements first")
                // Don't fail installation for this - just warn
            } else {
                AppLogger.shared.log("✅ [Installation] Karabiner driver verified at \(driverPath)")
            }
            
            // 4. Create initial config if needed
            await createInitialConfigIfNeeded()
            
            AppLogger.shared.log("✅ [Installation] Installation completed successfully")
            return true
            
        } catch {
            AppLogger.shared.log("❌ [Installation] Installation failed: \(error)")
            return false
        }
    }
    
    private func createInitialConfigIfNeeded() async {
        let configDir = "\(NSHomeDirectory())/.config/kanata"
        let configFile = "\(configDir)/keypath.kbd"
        
        // Create config directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
            AppLogger.shared.log("✅ [Config] Config directory created at \(configDir)")
        } catch {
            AppLogger.shared.log("❌ [Config] Failed to create config directory: \(error)")
            return
        }
        
        // Create initial config if it doesn't exist
        if !FileManager.default.fileExists(atPath: configFile) {
            let initialConfig = """
;; KeyPath Configuration
;; This file is managed by KeyPath.app

(defcfg
  process-unmapped-keys yes
)

(defsrc
  caps
)

(deflayer base
  esc
)
"""
            
            do {
                try initialConfig.write(toFile: configFile, atomically: true, encoding: .utf8)
                AppLogger.shared.log("✅ [Config] Initial config created at \(configFile)")
            } catch {
                AppLogger.shared.log("❌ [Config] Failed to create initial config: \(error)")
            }
        }
    }
}
