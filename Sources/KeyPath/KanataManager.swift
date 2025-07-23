import Foundation
import SwiftUI
import IOKit.hidsystem
import ApplicationServices

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
        print("🔧 [AutoStart] Starting auto-start process...")
        
        // Check individual components
        let binary = isInstalled()
        let service = isServiceInstalled()
        let driver = isKarabinerDriverInstalled()
        print("🔧 [AutoStart] Component status: binary=\(binary), service=\(service), driver=\(driver)")
        
        // Check for complete installation (binary + LaunchDaemon)
        guard isCompletelyInstalled() else {
            let status = getInstallationStatus()
            print("🔧 [AutoStart] Installation incomplete: \(status)")
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
        
        print("🔧 [AutoStart] All components installed, checking if already running...")
        
        // Check if already running
        if await isKanataRunning() {
            print("🔧 [AutoStart] Kanata already running")
            await MainActor.run {
                self.lastError = nil // Clear any previous errors
            }
            await verifyRootExecution() // Verify it's running as root
            return
        }
        
        print("🔧 [AutoStart] Kanata not running, attempting to start...")
        
        // Try to start Kanata using launchctl bootstrap (non-interactive)
        await MainActor.run {
            self.lastError = "Starting Kanata service..."
        }
        
        // For auto-start, use a non-interactive approach
        await startKanataAutomatic()
        
        print("🔧 [AutoStart] Start command sent, waiting 3 seconds...")
        
        // Verify it started successfully with proper privileges
        try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
        await updateStatus()
        
        print("🔧 [AutoStart] Status updated, isRunning = \(isRunning)")
        
        if !isRunning {
            print("🔧 [AutoStart] Failed to start Kanata")
            await MainActor.run {
                self.lastError = "⚠️ Setup Required: Grant Input Monitoring permissions in System Settings → Privacy & Security"
            }
        } else {
            print("🔧 [AutoStart] Successfully started Kanata!")
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
            print("🔍 [Status] Checking if Kanata is running...")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["print", "system/\(launchDaemonLabel)"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("🔍 [Status] launchctl exit code: \(process.terminationStatus)")
                print("🔍 [Status] launchctl output: \(output)")
                
                // Check if service is running (state = running)
                let isRunning = output.contains("state = running")
                print("🔍 [Status] Service running: \(isRunning)")
                continuation.resume(returning: isRunning)
            }
            
            do {
                try task.run()
            } catch {
                print("🔍 [Status] Error running launchctl: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    func startKanata() async {
        print("🚀 [Start] Starting Kanata service...")
        
        // IMPORTANT: Ensure Karabiner daemon is running first
        print("🚀 [Start] Ensuring Karabiner daemon is running...")
        await ensureDaemonRunning()
        
        print("🚀 [Start] Executing kickstart command...")
        // LaunchDaemon automatically runs Kanata as root - no manual privilege escalation needed
        await executeCommand(["kickstart", "-k", "system/\(launchDaemonLabel)"])
        
        print("🚀 [Start] Kickstart command sent, waiting 2 seconds...")
        // Verify Kanata started with root privileges
        try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
        await updateStatus()
        
        print("🚀 [Start] Verifying root execution...")
        // Check if running as root
        await verifyRootExecution()
    }
    
    /// Auto-start version that doesn't require user interaction
    private func startKanataAutomatic() async {
        print("🚀 [AutoStart] Starting Kanata service without user interaction...")
        
        // The LaunchDaemon is already loaded, we just need to start it
        // Since the daemon runs as root, we use the system domain
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = ["kickstart", "system/\(launchDaemonLabel)"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("🚀 [AutoStart] launchctl kickstart result: exit=\(process.terminationStatus), output=\(output)")
                
                if process.terminationStatus != 0 && !output.contains("already running") {
                    Task { @MainActor in
                        self.lastError = "Auto-start failed: \(output)"
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
                print("🚀 [AutoStart] Error starting launchctl: \(error)")
                Task { @MainActor in
                    self.lastError = "Failed to auto-start: \(error.localizedDescription)"
                }
                continuation.resume()
            }
        }
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
        print("💻 [Execute] Running command: launchctl \(arguments.joined(separator: " "))")
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
                
                print("💻 [Execute] Command exit code: \(process.terminationStatus)")
                print("💻 [Execute] Command output: \(output)")
                
                if process.terminationStatus != 0 {
                    Task { @MainActor in
                        // Check if user cancelled
                        if output.contains("User canceled") {
                            print("💻 [Execute] User cancelled authorization")
                            self.lastError = "Authorization cancelled by user"
                        } else {
                            print("💻 [Execute] Command failed with error")
                            self.lastError = "Command failed: \(output)"
                        }
                    }
                } else {
                    print("💻 [Execute] Command succeeded")
                    Task { @MainActor in
                        self.lastError = nil
                    }
                }
                
                continuation.resume()
            }
            
            do {
                try task.run()
            } catch {
                print("💻 [Execute] Failed to start command: \(error)")
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
                    set logOutput to ""
                    try
                        -- Check prerequisites first
                        set logOutput to logOutput & "Checking Kanata binary..." & return
                        try
                            do shell script "test -f /usr/local/bin/kanata-cmd"
                            set logOutput to logOutput & "✓ Kanata binary found" & return
                        on error
                            set logOutput to logOutput & "✗ ERROR: Kanata binary not found at /usr/local/bin/kanata-cmd" & return
                            return "error: " & logOutput
                        end try
                        
                        -- Create config directory
                        set logOutput to logOutput & "Creating config directory..." & return
                        try
                            do shell script "mkdir -p /usr/local/etc/kanata" with administrator privileges
                            do shell script "chown root:wheel /usr/local/etc/kanata" with administrator privileges
                            do shell script "chmod 755 /usr/local/etc/kanata" with administrator privileges
                            set logOutput to logOutput & "✓ Config directory created" & return
                        on error dirError
                            set logOutput to logOutput & "✗ ERROR creating config directory: " & dirError & return
                            return "error: " & logOutput
                        end try
                        
                        -- Create default config
                        set logOutput to logOutput & "Creating default config..." & return
                        try
                            do shell script "cat > /usr/local/etc/kanata/keypath.kbd << 'KBDEOF'
                            ;; KeyPath System Configuration
                            ;; This file will be updated by the KeyPath app
                            
                            (defcfg
                              process-unmapped-keys yes
                            )
                            
                            (defsrc
                              caps
                            )
                            
                            (deflayer base
                              esc
                            )
                            KBDEOF" with administrator privileges
                            
                            do shell script "chown root:wheel /usr/local/etc/kanata/keypath.kbd" with administrator privileges
                            do shell script "chmod 644 /usr/local/etc/kanata/keypath.kbd" with administrator privileges
                            set logOutput to logOutput & "✓ Default config created" & return
                        on error configError
                            set logOutput to logOutput & "✗ ERROR creating config: " & configError & return
                            return "error: " & logOutput
                        end try
                        
                        -- Create LaunchDaemon plist
                        set logOutput to logOutput & "Creating LaunchDaemon..." & return
                        try
                            do shell script "cat > /Library/LaunchDaemons/com.keypath.kanata.plist << 'PLISTEOF'
                            <?xml version=\"1.0\" encoding=\"UTF-8\"?>
                            <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
                            <plist version=\"1.0\">
                            <dict>
                                <key>Label</key>
                                <string>com.keypath.kanata</string>
                                <key>ProgramArguments</key>
                                <array>
                                    <string>/usr/local/bin/kanata-cmd</string>
                                    <string>--cfg</string>
                                    <string>/usr/local/etc/kanata/keypath.kbd</string>
                                </array>
                                <key>UserName</key>
                                <string>root</string>
                                <key>GroupName</key>
                                <string>wheel</string>
                                <key>RunAtLoad</key>
                                <false/>
                                <key>KeepAlive</key>
                                <false/>
                                <key>StandardOutPath</key>
                                <string>/var/log/kanata.log</string>
                                <key>StandardErrorPath</key>
                                <string>/var/log/kanata.log</string>
                                <key>ThrottleInterval</key>
                                <integer>1</integer>
                                <key>ProcessType</key>
                                <string>Interactive</string>
                            </dict>
                            </plist>
                            PLISTEOF" with administrator privileges
                            
                            do shell script "chown root:wheel /Library/LaunchDaemons/com.keypath.kanata.plist" with administrator privileges
                            do shell script "chmod 644 /Library/LaunchDaemons/com.keypath.kanata.plist" with administrator privileges
                            set logOutput to logOutput & "✓ LaunchDaemon plist created" & return
                        on error plistError
                            set logOutput to logOutput & "✗ ERROR creating LaunchDaemon: " & plistError & return
                            return "error: " & logOutput
                        end try
                        
                        -- Load the LaunchDaemon
                        set logOutput to logOutput & "Loading LaunchDaemon..." & return
                        try
                            do shell script "launchctl load -w /Library/LaunchDaemons/com.keypath.kanata.plist" with administrator privileges
                            set logOutput to logOutput & "✓ LaunchDaemon loaded" & return
                        on error loadError
                            set logOutput to logOutput & "✗ ERROR loading LaunchDaemon: " & loadError & return
                            return "error: " & logOutput
                        end try
                        
                        -- Test config file
                        set logOutput to logOutput & "Testing config file..." & return
                        try
                            do shell script "/usr/local/bin/kanata-cmd --cfg /usr/local/etc/kanata/keypath.kbd --check" with administrator privileges
                            set logOutput to logOutput & "✓ Config file is valid" & return
                        on error testError
                            set logOutput to logOutput & "✗ ERROR testing config: " & testError & return
                            return "error: " & logOutput
                        end try
                        
                        -- Check if Karabiner driver is installed and start daemon
                        set logOutput to logOutput & "Checking Karabiner driver..." & return
                        try
                            do shell script "test -d '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'"
                            set logOutput to logOutput & "✓ Karabiner driver found" & return
                            
                            -- Start Karabiner daemon
                            set logOutput to logOutput & "Starting Karabiner daemon..." & return
                            try
                                set daemonPath to "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
                                do shell script "sudo '" & daemonPath & "' &" with administrator privileges
                                set logOutput to logOutput & "✓ Karabiner daemon started" & return
                            on error daemonError
                                set logOutput to logOutput & "⚠ WARNING starting daemon: " & daemonError & return
                            end try
                            
                        on error
                            set logOutput to logOutput & "⚠ WARNING: Karabiner driver not found" & return
                            display dialog "Karabiner VirtualHID driver is required but not installed. Please install Karabiner-Elements first, or KeyPath may not work properly." with title "KeyPath Setup" buttons {"Continue Anyway", "Cancel"} default button "Continue Anyway" with icon caution
                            if button returned of result is "Cancel" then
                                return "cancelled"
                            end if
                        end try
                        
                        -- Try to auto-start Kanata service
                        set logOutput to logOutput & "Starting Kanata service..." & return
                        try
                            do shell script "sudo launchctl kickstart system/com.keypath.kanata" with administrator privileges
                            set logOutput to logOutput & "✓ Kanata service started" & return
                        on error startError
                            set logOutput to logOutput & "⚠ Service start issue: " & startError & return
                        end try
                        
                        -- Show permissions reminder
                        display dialog "✅ KeyPath installation complete!" & return & return & "IMPORTANT: Grant Input Monitoring permission to KeyPath in:" & return & "System Settings → Privacy & Security → Input Monitoring" & return & return & "This allows KeyPath to capture keyboard events." with title "Installation Complete" buttons {"Open System Settings", "OK"} default button "Open System Settings" with icon note
                        
                        if button returned of result is "Open System Settings" then
                            try
                                do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'"
                            on error
                                -- Fallback for different macOS versions
                                do shell script "open '/System/Library/PreferencePanes/Security.prefPane'"
                            end try
                        end if
                        
                        set logOutput to logOutput & "✅ Installation completed successfully!" & return
                        return "success: " & logOutput
                    on error errMsg
                        set logOutput to logOutput & "✗ FATAL ERROR: " & errMsg & return
                        return "error: " & logOutput
                    end try
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
                
                print("=== INSTALLATION DEBUG OUTPUT ===")
                print("Exit code: \(process.terminationStatus)")
                print("Output: \(output)")
                print("================================")
                
                if process.terminationStatus == 0 {
                    let success = output.contains("success:")
                    if success {
                        Task { @MainActor in
                            self.lastError = nil
                        }
                        continuation.resume(returning: true)
                    } else if output.contains("cancelled") {
                        Task { @MainActor in
                            self.lastError = "Installation cancelled by user"
                        }
                        continuation.resume(returning: false)
                    } else {
                        Task { @MainActor in
                            self.lastError = "Installation failed - see console for details: \(output)"
                        }
                        continuation.resume(returning: false)
                    }
                } else {
                    Task { @MainActor in
                        if output.contains("User canceled") {
                            self.lastError = "Installation cancelled by user"
                        } else {
                            self.lastError = "Installation process failed (exit \(process.terminationStatus)): \(output)"
                        }
                    }
                    continuation.resume(returning: false)
                }
            }
            
            do {
                try task.run()
            } catch {
                Task { @MainActor in
                    self.lastError = "Failed to start installation process: \(error.localizedDescription)"
                }
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
    
    // MARK: - Service Crash Detection
    
    /// Check if the service has successive crashes indicating permission issues
    private func checkServiceCrashStatus() -> Bool {
        // Use Process to run launchctl synchronously
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["print", "system/\(launchDaemonLabel)"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Look for successive crashes in the output
            if let successiveCrashesLine = output.components(separatedBy: CharacterSet.newlines)
                .first(where: { $0.contains("successive crashes") }) {
                
                // Extract the number of successive crashes
                let components = successiveCrashesLine.components(separatedBy: " ")
                if let crashIndex = components.firstIndex(of: "crashes"),
                   crashIndex > 1,
                   let crashCount = Int(components[crashIndex - 1]) {
                    print("🔐 [Permissions] Found \(crashCount) successive crashes")
                    return crashCount > 5 // Consider 5+ crashes as a problem
                }
            }
            
            // Check for recent "IOHIDDeviceOpen error" in logs (only last 50 lines)
            if let logContent = try? String(contentsOfFile: "/var/log/kanata.log") {
                let recentLines = logContent.components(separatedBy: CharacterSet.newlines).suffix(50)
                let recentContent = recentLines.joined(separator: "\n")
                
                if recentContent.contains("IOHIDDeviceOpen error: (iokit/common) not permitted") {
                    // Check if we also have recent success indicators
                    if recentContent.contains("Starting kanata proper") || recentContent.contains("connected") {
                        print("🔐 [Permissions] Found recent success indicators - permission likely granted")
                        return false
                    } else {
                        print("🔐 [Permissions] Found recent IOHIDDeviceOpen permission error in logs")
                        return true
                    }
                }
            }
            
        } catch {
            print("🔐 [Permissions] Could not check service status: \(error)")
        }
        
        return false
    }
    
    // MARK: - Input Monitoring Permissions
    
    /// Check if Input Monitoring permission is granted
    func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let apiSaysGranted = accessType == kIOHIDAccessTypeGranted
            print("🔐 [Permissions] Input Monitoring API says: \(accessType), granted: \(apiSaysGranted)")
            
            // Check if service is experiencing successive crashes (indicates permission issues)
            let hasSuccessiveCrashes = checkServiceCrashStatus()
            if hasSuccessiveCrashes {
                print("🔐 [Permissions] Service has successive crashes - treating as permission denied")
                return false
            }
            
            // Practical check: if Kanata service is failing with permission errors, 
            // then permissions aren't effectively working
            let serviceFailingWithPermissions = !isRunning && (lastError?.contains("Setup Required") == true)
            
            if serviceFailingWithPermissions {
                print("🔐 [Permissions] Service failing with permission errors - treating as not granted")
                return false
            }
            
            // If service is running successfully, permissions are definitely working
            if isRunning {
                print("🔐 [Permissions] Service running successfully - permissions confirmed")
                return true
            }
            
            // Check if service is not running and we have crashes - likely permission issue
            if !isRunning && hasSuccessiveCrashes {
                print("🔐 [Permissions] Service not running with crashes - treating as permission denied")
                return false
            }
            
            // Fall back to API check if service state is unclear
            print("🔐 [Permissions] Using API result: \(apiSaysGranted)")
            return apiSaysGranted
        } else {
            // For older macOS versions, Input Monitoring was part of Accessibility
            let hasPermission = AXIsProcessTrusted()
            print("🔐 [Permissions] Accessibility permission: \(hasPermission)")
            return hasPermission
        }
    }
    
    /// Request Input Monitoring permission (shows system dialog on first call)
    func requestInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        } else {
            // For older macOS versions, request Accessibility permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }
    
    /// Open System Settings to Input Monitoring preferences
    func openInputMonitoringSettings() {
        if #available(macOS 13.0, *) {
            // macOS Ventura and later use the new Settings app
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Fallback for older macOS versions
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            } else {
                // Ultimate fallback - open Security & Privacy preferences
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
            }
        }
    }
}