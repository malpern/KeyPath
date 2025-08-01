import Foundation

/// Manages the Karabiner VirtualHIDDevice Manager component
/// This is critical for keyboard remapping functionality on macOS
class VHIDDeviceManager {
    
    // MARK: - Constants
    
    private static let vhidManagerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    private static let vhidManagerBundleID = "org.pqrs.Karabiner-VirtualHIDDevice-Manager"
    private static let vhidDeviceDaemonPath = "/Library/Application Support/org.pqrs/Karabiner-VirtualHIDDevice/bin/karabiner_vhid_daemon"
    private static let vhidDeviceRunningCheck = "karabiner_vhid"
    
    // MARK: - Detection Methods
    
    /// Checks if the VirtualHIDDevice Manager application is installed
    func detectInstallation() -> Bool {
        let fileManager = FileManager.default
        let appExists = fileManager.fileExists(atPath: Self.vhidManagerPath)
        
        AppLogger.shared.log("🔍 [VHIDManager] Manager app exists at \(Self.vhidManagerPath): \(appExists)")
        return appExists
    }
    
    /// Checks if the VirtualHIDDevice Manager has been activated
    /// This involves checking if the daemon binaries are in place
    func detectActivation() -> Bool {
        let fileManager = FileManager.default
        let daemonExists = fileManager.fileExists(atPath: Self.vhidDeviceDaemonPath)
        
        AppLogger.shared.log("🔍 [VHIDManager] Daemon exists at \(Self.vhidDeviceDaemonPath): \(daemonExists)")
        return daemonExists
    }
    
    /// Checks if VirtualHIDDevice processes are currently running
    func detectRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", Self.vhidDeviceRunningCheck]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isRunning = task.terminationStatus == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            AppLogger.shared.log("🔍 [VHIDManager] VHIDDevice processes running: \(isRunning)")
            return isRunning
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Error checking VHIDDevice processes: \(error)")
            return false
        }
    }
    
    // MARK: - Activation Methods
    
    /// Activates the VirtualHIDDevice Manager
    /// This is equivalent to running the manager app with the 'activate' command
    func activateManager() async -> Bool {
        guard detectInstallation() else {
            AppLogger.shared.log("❌ [VHIDManager] Cannot activate - manager app not installed")
            return false
        }
        
        AppLogger.shared.log("🔧 [VHIDManager] Activating VHIDDevice Manager...")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = [Self.vhidManagerPath, "activate"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [VHIDManager] VHIDDevice Manager activated successfully")
                
                // Wait a moment for the activation to take effect
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Verify activation worked
                let activated = detectActivation()
                AppLogger.shared.log("🔍 [VHIDManager] Post-activation verification: \(activated)")
                return activated
            } else {
                AppLogger.shared.log("❌ [VHIDManager] Activation failed with status \(task.terminationStatus): \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Error activating VHIDDevice Manager: \(error)")
            return false
        }
    }
    
    /// Comprehensive status check - returns detailed information about VHIDDevice state
    func getDetailedStatus() -> VHIDDeviceStatus {
        let installed = detectInstallation()
        let activated = detectActivation()
        let running = detectRunning()
        
        return VHIDDeviceStatus(
            managerInstalled: installed,
            managerActivated: activated,
            daemonRunning: running
        )
    }
}

// MARK: - Supporting Types

/// Detailed status information for VHIDDevice components
struct VHIDDeviceStatus {
    let managerInstalled: Bool
    let managerActivated: Bool
    let daemonRunning: Bool
    
    /// True if all components are ready for use
    var isFullyOperational: Bool {
        managerInstalled && managerActivated && daemonRunning
    }
    
    /// Description of current status for logging/debugging
    var description: String {
        """
        VHIDDevice Status:
        - Manager Installed: \(managerInstalled)
        - Manager Activated: \(managerActivated)
        - Daemon Running: \(daemonRunning)
        - Fully Operational: \(isFullyOperational)
        """
    }
}