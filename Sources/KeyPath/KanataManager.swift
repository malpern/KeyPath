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
        await executeCommand(["kickstart", "-k", "system/\(launchDaemonLabel)"])
        await updateStatus()
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
        
        // Restart Kanata to apply new config
        await restartKanata()
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
    
    private func generateKanataConfig(input: String, output: String) -> String {
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
            "cmd": "cmd",
            "command": "cmd",
            "lcmd": "lcmd",
            "rcmd": "rcmd"
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
}

// MARK: - Installation Check

extension KanataManager {
    func isInstalled() -> Bool {
        // Check if Kanata binary exists
        let kanataPath = "/usr/local/bin/kanata"
        return FileManager.default.fileExists(atPath: kanataPath)
    }
    
    func isServiceInstalled() -> Bool {
        // Check if LaunchDaemon is installed
        let plistPath = "/Library/LaunchDaemons/\(launchDaemonLabel).plist"
        return FileManager.default.fileExists(atPath: plistPath)
    }
    
    func getInstallationStatus() -> String {
        let kanataInstalled = isInstalled()
        let serviceInstalled = isServiceInstalled()
        
        if kanataInstalled && serviceInstalled {
            return "✅ Fully installed"
        } else if kanataInstalled {
            return "⚠️ Kanata installed, service missing"
        } else if serviceInstalled {
            return "⚠️ Service installed, Kanata missing"
        } else {
            return "❌ Not installed"
        }
    }
}