import Foundation

/// Manages Kanata process lifecycle and hot reload functionality
class KanataProcessManager {
    static let shared = KanataProcessManager()
    
    private init() {
        // Clean up old backup files on initialization
        cleanupOldBackupFiles()
    }
    
    /// Check if Kanata is currently running
    func isKanataRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["kanata"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // If pgrep finds processes, it returns PIDs (non-empty output)
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            DebugLogger.shared.log("🔧 DEBUG: Failed to check Kanata status: \(error)")
            return false
        }
    }
    
    /// Send hot reload signal to Kanata
    func reloadKanata() -> Bool {
        DebugLogger.shared.log("🔧 DEBUG: Attempting to reload Kanata...")
        
        // First check if Kanata is running
        guard isKanataRunning() else {
            DebugLogger.shared.log("🔧 DEBUG: Kanata not running, cannot reload")
            return false
        }
        
        // Send SIGUSR1 signal to reload configuration
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-SIGUSR1", "kanata"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let success = task.terminationStatus == 0
            DebugLogger.shared.log("🔧 DEBUG: Kanata reload \(success ? "successful" : "failed") (exit code: \(task.terminationStatus))")
            return success
        } catch {
            DebugLogger.shared.log("🔧 DEBUG: Failed to send reload signal: \(error)")
            return false
        }
    }
    
    /// Get list of Kanata process IDs (for debugging)
    func getKanataPIDs() -> [Int] {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["kanata"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.components(separatedBy: .newlines)
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        } catch {
            return []
        }
    }
    
    /// Get detailed Kanata process information
    func getKanataProcessInfo() -> String {
        let pids = getKanataPIDs()
        guard !pids.isEmpty else {
            return "Kanata is not running"
        }
        
        var info = "Kanata processes found:\n"
        for pid in pids {
            let task = Process()
            task.launchPath = "/bin/ps"
            task.arguments = ["-p", String(pid), "-o", "pid,ppid,command"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                info += output
            } catch {
                info += "PID \(pid): Error getting process info\n"
            }
        }
        
        return info
    }
}

/// Extension for SwiftUI integration
extension KanataProcessManager {
    /// Check Kanata status and return user-friendly message
    func getStatusMessage() -> String {
        if isKanataRunning() {
            let pids = getKanataPIDs()
            return "Kanata is running (PID: \(pids.map(String.init).joined(separator: ", ")))"
        } else {
            return "Kanata is not running"
        }
    }
    
    /// Clean up backup files older than 1 day
    private func cleanupOldBackupFiles() {
        let configPath = NSHomeDirectory() + "/.config/kanata"
        let fileManager = FileManager.default
        
        DebugLogger.shared.log("🔧 DEBUG: Cleaning up old backup files in \(configPath)")
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: configPath) else {
            DebugLogger.shared.log("🔧 DEBUG: Could not list files in config directory")
            return
        }
        
        let backupFiles = files.filter { $0.hasPrefix("kanata.kbd.keypath-backup-") }
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        
        var deletedCount = 0
        var errorCount = 0
        
        for backupFile in backupFiles {
            let fullPath = configPath + "/" + backupFile
            
            do {
                let attributes = try fileManager.attributesOfItem(atPath: fullPath)
                if let creationDate = attributes[.creationDate] as? Date {
                    if creationDate < oneDayAgo {
                        try fileManager.removeItem(atPath: fullPath)
                        deletedCount += 1
                        DebugLogger.shared.log("🔧 DEBUG: Deleted old backup: \(backupFile)")
                    }
                }
            } catch {
                errorCount += 1
                DebugLogger.shared.log("🔧 DEBUG: Error processing backup file \(backupFile): \(error)")
            }
        }
        
        if deletedCount > 0 || errorCount > 0 {
            DebugLogger.shared.log("🔧 DEBUG: Backup cleanup complete - deleted: \(deletedCount), errors: \(errorCount)")
        }
    }
}
