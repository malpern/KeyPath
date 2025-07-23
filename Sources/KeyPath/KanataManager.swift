import Foundation
import SwiftUI

/// Simplified Kanata management using launchctl - inspired by Karabiner-Elements
@MainActor
class KanataManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?
    
    private let launchDaemonLabel = "com.keypath.kanata"
    private let configDirectory = "/usr/local/etc/kanata"
    private let configFileName = "keypath.kbd"
    
    var configPath: String {
        "\(configDirectory)/\(configFileName)"
    }
    
    init() {
        Task {
            await updateStatus()
            await autoStartKanata()
        }
    }
    
    // MARK: - Auto Management
    
    /// Automatically start Kanata if fully installed and not running
    private func autoStartKanata() async {
        // Check for complete installation (binary + LaunchDaemon)
        guard isCompletelyInstalled() else {
            let status = getInstallationStatus()
            await MainActor.run {
                if !self.isInstalled() {
                    self.lastError = "Kanata not installed. Please run: sudo ./install-system.sh"
                } else if !self.isServiceInstalled() {
                    self.lastError = "LaunchDaemon missing. Please run: sudo ./install-system.sh"
                } else {
                    self.lastError = "Installation incomplete: \(status)"
                }
            }
            return
        }
        
        // Check if already running
        if await isKanataRunning() {
            await MainActor.run {
                self.lastError = nil // Clear any previous errors
            }
            await verifyRootExecution() // Verify it's running as root
            return
        }
        
        // Try to start Kanata (LaunchDaemon automatically handles root privileges)
        await MainActor.run {
            self.lastError = "Starting Kanata with root privileges..."
        }
        
        await startKanata()
        
        // Verify it started successfully with proper privileges
        try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
        await updateStatus()
        
        if !isRunning {
            await MainActor.run {
                self.lastError = "Failed to auto-start Kanata. LaunchDaemon may need reinstallation."
            }
        } else {
            await MainActor.run {
                self.lastError = nil
            }
        }
    }
    
    /// Stop Kanata when app is terminating
    func cleanup() async {
        if isRunning {
            await stopKanata()
        }
    }
    
    // MARK: - Public Interface
    
    func isKanataRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["print", "system/\(launchDaemonLabel)"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Check if service is running (state = running)
                let isRunning = output.contains("state = running")
                continuation.resume(returning: isRunning)
            }
            
            do {
                try task.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    func startKanata() async {
        // IMPORTANT: Ensure Karabiner daemon is running first
        await ensureDaemonRunning()
        
        // LaunchDaemon automatically runs Kanata as root - no manual privilege escalation needed
        await executeCommand(["kickstart", "-k", "system/\(launchDaemonLabel)"])
        
        // Verify Kanata started with root privileges
        try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
        await updateStatus()
        
        // Check if running as root
        await verifyRootExecution()
    }
    
    func stopKanata() async {
        await executeCommand(["kill", "TERM", "system/\(launchDaemonLabel)"])
        await updateStatus()
    }
    
    func restartKanata() async {
        await executeCommand(["kickstart", "-k", "system/\(launchDaemonLabel)"])
        await updateStatus()
    }
    
    // SAFETY: Emergency stop function
    func emergencyStop() async {
        await executeCommand(["kill", "TERM", "system/\(launchDaemonLabel)"])
        await updateStatus()
    }
    
    func saveConfiguration(input: String, output: String) async throws {
        let config = generateKanataConfig(input: input, output: output)
        
        // SAFETY: Validate configuration before saving
        try await validateConfiguration(config)
        
        // Create config directory if it doesn't exist
        let configDir = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Write config file
        let configURL = URL(fileURLWithPath: configPath)
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        
        // Auto-reload Kanata with new config (seamless like Karabiner-Elements)
        await autoReloadKanata()
    }
    
    /// Seamlessly reload Kanata with new configuration
    private func autoReloadKanata() async {
        guard isCompletelyInstalled() else {
            // If not installed, just update status
            await updateStatus()
            return
        }
        
        if isRunning {
            // Restart Kanata to pick up new config
            await restartKanata()
        } else {
            // Start Kanata if not running
            await startKanata()
        }
        
        // Update status after reload
        await updateStatus()
    }
    
    // SAFETY: Validate configuration using kanata --check
    private func validateConfiguration(_ config: String) async throws {
        // Write config to temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keypath-test.kbd")
        try config.write(to: tempURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Validate using kanata --check
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/kanata-cmd")
            task.arguments = ["--cfg", tempURL.path, "--check"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus != 0 {
                    Task { @MainActor in
                        self.lastError = "Invalid configuration: \(output)"
                    }
                }
                continuation.resume()
            }
            
            do {
                try task.run()
            } catch {
                Task { @MainActor in
                    self.lastError = "Failed to validate config: \(error.localizedDescription)"
                }
                continuation.resume()
            }
        }
        
        if lastError != nil {
            throw NSError(domain: "KanataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: lastError ?? "Config validation failed"])
        }
    }
    
    func updateStatus() async {
        let running = await isKanataRunning()
        isRunning = running
    }
    
    // MARK: - Private Implementation
    
    private func executeCommand(_ arguments: [String]) async {
        await withCheckedContinuation { continuation in
            // Try to use osascript to run sudo commands with GUI authorization
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            
            // Create AppleScript that prompts for password
            let script = """
            do shell script "/bin/launchctl \(arguments.joined(separator: " "))" with administrator privileges
            """
            
            task.arguments = ["-e", script]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus != 0 {
                    Task { @MainActor in
                        // Check if user cancelled
                        if output.contains("User canceled") {
                            self.lastError = "Authorization cancelled by user"
                        } else {
                            self.lastError = "Command failed: \(output)"
                        }
                    }
                } else {
                    Task { @MainActor in
                        self.lastError = nil
                    }
                }
                
                continuation.resume()
            }
            
            do {
                try task.run()
            } catch {
                Task { @MainActor in
                    self.lastError = "Failed to execute command: \(error.localizedDescription)"
                }
                continuation.resume()
            }
        }
    }
    
    func generateKanataConfig(input: String, output: String) -> String {
        // Convert input key to Kanata format
        let kanataInput = convertToKanataKey(input)
        let kanataOutput = convertToKanataSequence(output)
        
        return """
        ;; KeyPath Generated Configuration
        ;; Input: \(input) -> Output: \(output)
        ;; Generated: \(Date())
        ;; 
        ;; SAFETY FEATURES:
        ;; - Only specified keys are intercepted
        ;; - All other keys pass through normally
        ;; - Emergency stop: Use KeyPath app or Terminal
        
        (defcfg
          ;; SAFETY: Only process explicitly mapped keys
          process-unmapped-keys no
          
          ;; SAFETY: Allow cmd for system shortcuts
          danger-enable-cmd yes
        )
        
        (defsrc
          \(kanataInput)
        )
        
        (deflayer base
          \(kanataOutput)
        )
        """
    }
    
    private func convertToKanataKey(_ key: String) -> String {
        // Simple key conversion - expand this based on needs
        let keyMap: [String: String] = [
            "caps": "caps",
            "capslock": "caps",
            "space": "spc",
            "enter": "ret",
            "return": "ret",
            "tab": "tab",
            "escape": "esc",
            "backspace": "bspc",
            "delete": "del",
            "cmd": "lmet",
            "command": "lmet",
            "lcmd": "lmet",
            "rcmd": "rmet",
            "lcommand": "lmet",
            "rcommand": "rmet",
            "leftcmd": "lmet",
            "rightcmd": "rmet"
        ]
        
        let lowercaseKey = key.lowercased()
        return keyMap[lowercaseKey] ?? lowercaseKey
    }
    
    private func convertToKanataSequence(_ sequence: String) -> String {
        // For simple single keys, convert them directly
        if sequence.count == 1 {
            return convertToKanataKey(sequence)
        } else {
            // For multi-character sequences, treat as a key name first
            let converted = convertToKanataKey(sequence)
            if converted != sequence.lowercased() {
                // It was a known key name
                return converted
            } else {
                // It's a sequence of characters, create a macro
                let keys = sequence.map { convertToKanataKey(String($0)) }
                return "(\(keys.joined(separator: " ")))"
            }
        }
    }
    
    // MARK: - Daemon Management
    
    /// Ensures the Karabiner VirtualHID daemon is running
    /// This is required for Kanata to work on macOS Sequoia
    private func ensureDaemonRunning() async {
        let daemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
        
        // Check if daemon is already running
        if await isDaemonRunning() {
            return // Already running
        }
        
        // Start the daemon
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            
            let script = """
            do shell script "sudo '\(daemonPath)' &" with administrator privileges
            """
            
            task.arguments = ["-e", script]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus != 0 {
                    Task { @MainActor in
                        if output.contains("User canceled") {
                            self.lastError = "Daemon startup cancelled by user"
                        } else {
                            self.lastError = "Failed to start daemon: \(output)"
                        }
                    }
                }
                continuation.resume()
            }
            
            do {
                try task.run()
            } catch {
                Task { @MainActor in
                    self.lastError = "Failed to start daemon: \(error.localizedDescription)"
                }
                continuation.resume()
            }
        }
        
        // Wait a moment for daemon to start
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    }
    
    /// Check if the Karabiner daemon is running
    private func isDaemonRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["aux"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                let isRunning = output.contains("Karabiner-VirtualHIDDevice-Daemon")
                continuation.resume(returning: isRunning)
            }
            
            do {
                try task.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Installation Check

extension KanataManager {
    func isInstalled() -> Bool {
        // Check if CMD-enabled Kanata binary exists
        let kanataPath = "/usr/local/bin/kanata-cmd"
        return FileManager.default.fileExists(atPath: kanataPath)
    }
    
    /// Check if both Kanata binary and LaunchDaemon are installed
    func isCompletelyInstalled() -> Bool {
        return isInstalled() && isServiceInstalled() && isKarabinerDriverInstalled()
    }
    
    func isServiceInstalled() -> Bool {
        // Check if LaunchDaemon is installed
        let plistPath = "/Library/LaunchDaemons/\(launchDaemonLabel).plist"
        return FileManager.default.fileExists(atPath: plistPath)
    }
    
    func isKarabinerDriverInstalled() -> Bool {
        // Check if Karabiner VirtualHID driver is installed
        let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
        return FileManager.default.fileExists(atPath: driverPath)
    }
    
    func getInstallationStatus() -> String {
        let kanataInstalled = isInstalled()
        let serviceInstalled = isServiceInstalled()
        let driverInstalled = isKarabinerDriverInstalled()
        
        if kanataInstalled && serviceInstalled && driverInstalled {
            return "✅ Fully installed"
        } else if kanataInstalled && serviceInstalled {
            return "⚠️ Driver missing"
        } else if kanataInstalled {
            return "⚠️ Service & driver missing"
        } else {
            return "❌ Not installed"
        }
    }
    
    /// Perform transparent installation for new users
    func performTransparentInstallation() async -> Bool {
        return await withCheckedContinuation { continuation in
            let script = """
            tell application "System Events"
                display dialog "KeyPath needs to install its keyboard engine. This requires administrator privileges." with title "KeyPath Setup" buttons {"Cancel", "Install"} default button "Install" with icon note
                if button returned of result is "Install" then
                    do shell script "cd '\(getCurrentDirectory())' && sudo ./install-system.sh" with administrator privileges
                    return "success"
                else
                    return "cancelled"
                end if
            end tell
            """
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                let success = process.terminationStatus == 0 && output.contains("success")
                continuation.resume(returning: success)
            }
            
            do {
                try task.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    private func getCurrentDirectory() -> String {
        return FileManager.default.currentDirectoryPath
    }
    
    /// Verify that Kanata is running with root privileges
    private func verifyRootExecution() async {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-axo", "pid,user,comm"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Check if kanata-cmd is running as root
                let lines = output.components(separatedBy: .newlines)
                let kanataProcess = lines.first { line in
                    line.contains("kanata-cmd") || line.contains("kanata")
                }
                
                if let process = kanataProcess {
                    if process.contains("root") {
                        Task { @MainActor in
                            // Kanata is running as root - perfect!
                            if self.lastError?.contains("root") == true {
                                self.lastError = nil // Clear root-related errors
                            }
                        }
                    } else {
                        Task { @MainActor in
                            self.lastError = "Kanata is not running as root. Keyboard access may be limited."
                        }
                    }
                } else {
                    Task { @MainActor in
                        if self.isRunning {
                            // LaunchDaemon shows as running but process not found
                            self.lastError = "Kanata service started but process verification failed."
                        }
                    }
                }
                
                continuation.resume()
            }
            
            do {
                try task.run()
            } catch {
                Task { @MainActor in
                    self.lastError = "Failed to verify root execution: \(error.localizedDescription)"
                }
                continuation.resume()
            }
        }
    }
}