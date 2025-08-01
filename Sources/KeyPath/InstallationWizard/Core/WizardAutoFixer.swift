import Foundation

/// Handles automatic fixing of detected issues - pure action logic
class WizardAutoFixer: AutoFixCapable {
    private let kanataManager: KanataManager
    
    init(kanataManager: KanataManager) {
        self.kanataManager = kanataManager
    }
    
    // MARK: - AutoFixCapable Protocol
    
    func canAutoFix(_ action: AutoFixAction) -> Bool {
        switch action {
        case .terminateConflictingProcesses:
            return true // We can always attempt to terminate processes
        case .startKarabinerDaemon:
            return true // We can attempt to start the daemon
        case .restartVirtualHIDDaemon:
            return true // We can attempt to restart VirtualHID daemon
        case .installMissingComponents:
            return true // We can run the installation script
        case .createConfigDirectories:
            return true // We can create directories
        }
    }
    
    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Attempting auto-fix: \(action)")
        
        switch action {
        case .terminateConflictingProcesses:
            return await terminateConflictingProcesses()
        case .startKarabinerDaemon:
            return await startKarabinerDaemon()
        case .restartVirtualHIDDaemon:
            return await restartVirtualHIDDaemon()
        case .installMissingComponents:
            return await installMissingComponents()
        case .createConfigDirectories:
            return await createConfigDirectories()
        }
    }
    
    // MARK: - Individual Auto-Fix Actions
    
    private func terminateConflictingProcesses() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Terminating conflicting processes")
        
        // First try temporary fix (just killing processes)
        let temporarySuccess = await kanataManager.killKarabinerGrabber()
        
        if temporarySuccess {
            AppLogger.shared.log("✅ [AutoFixer] Successfully terminated conflicting processes (temporary)")
            
            // Wait for processes to fully terminate
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Check if Karabiner Elements is installed and offer permanent disable
            if await isKarabinerElementsInstalled() {
                let permanentSuccess = await kanataManager.disableKarabinerElementsPermanently()
                if permanentSuccess {
                    AppLogger.shared.log("✅ [AutoFixer] Successfully disabled Karabiner Elements permanently - effective immediately")
                    AppLogger.shared.log("ℹ️ [AutoFixer] No restart required - conflicts resolved permanently")
                } else {
                    AppLogger.shared.log("⚠️ [AutoFixer] Temporary fix applied, but permanent disable was declined or failed")
                }
            }
            
            return true
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to terminate conflicting processes")
            return false
        }
    }
    
    /// Check if Karabiner Elements is installed on the system
    private func isKarabinerElementsInstalled() async -> Bool {
        let karabinerAppPath = "/Applications/Karabiner-Elements.app"
        return FileManager.default.fileExists(atPath: karabinerAppPath)
    }
    
    private func startKarabinerDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Starting Karabiner daemon")
        
        let success = await kanataManager.startKarabinerDaemon()
        
        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully started Karabiner daemon")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to start Karabiner daemon")
        }
        
        return success
    }
    
    private func restartVirtualHIDDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Restarting VirtualHID daemon")
        
        // Kill existing daemon
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "Karabiner-VirtualHIDDevice-Daemon"]
        
        do {
            try killTask.run()
            killTask.waitUntilExit()
            
            // Wait for process to terminate
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Start daemon again
            let startSuccess = await startKarabinerDaemon()
            
            if startSuccess {
                AppLogger.shared.log("✅ [AutoFixer] Successfully restarted VirtualHID daemon")
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to restart VirtualHID daemon")
            }
            
            return startSuccess
            
        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error restarting VirtualHID daemon: \(error)")
            return false
        }
    }
    
    private func installMissingComponents() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing missing components")
        
        let success = await kanataManager.performTransparentInstallation()
        
        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully installed missing components")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to install missing components")
        }
        
        return success
    }
    
    private func createConfigDirectories() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Creating config directories")
        
        let configDirectory = "\(NSHomeDirectory())/Library/Application Support/KeyPath"
        
        do {
            try FileManager.default.createDirectory(
                atPath: configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            AppLogger.shared.log("✅ [AutoFixer] Successfully created config directories")
            return true
            
        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Failed to create config directories: \(error)")
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    /// Attempts to gracefully terminate a specific process by PID
    private func terminateProcess(pid: Int) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Terminating process PID: \(pid)")
        
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
        killTask.arguments = ["-TERM", String(pid)]
        
        do {
            try killTask.run()
            killTask.waitUntilExit()
            
            if killTask.terminationStatus == 0 {
                // Wait a bit for graceful termination
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Check if process is still running
                let checkTask = Process()
                checkTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                checkTask.arguments = ["-0", String(pid)]
                
                try checkTask.run()
                checkTask.waitUntilExit()
                
                if checkTask.terminationStatus != 0 {
                    // Process is gone
                    AppLogger.shared.log("✅ [AutoFixer] Process \(pid) terminated gracefully")
                    return true
                } else {
                    // Process still running, try SIGKILL
                    AppLogger.shared.log("⚠️ [AutoFixer] Process \(pid) still running, using SIGKILL")
                    return await forceTerminateProcess(pid: pid)
                }
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to send SIGTERM to process \(pid)")
                return await forceTerminateProcess(pid: pid)
            }
        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error terminating process \(pid): \(error)")
            return false
        }
    }
    
    /// Force terminates a process using SIGKILL
    private func forceTerminateProcess(pid: Int) async -> Bool {
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
        killTask.arguments = ["-9", String(pid)]
        
        do {
            try killTask.run()
            killTask.waitUntilExit()
            
            let success = killTask.terminationStatus == 0
            if success {
                AppLogger.shared.log("✅ [AutoFixer] Force terminated process \(pid)")
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to force terminate process \(pid)")
            }
            return success
            
        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error force terminating process \(pid): \(error)")
            return false
        }
    }
}