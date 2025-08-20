import Foundation
import Security

/// Manages LaunchDaemon installation and configuration for KeyPath services
/// Implements the production-ready LaunchDaemon architecture identified in the installer improvement analysis
class LaunchDaemonInstaller {
    // MARK: - Dependencies

    private let packageManager: PackageManager

    // MARK: - Constants

    private static let launchDaemonsPath: String = LaunchDaemonInstaller.resolveLaunchDaemonsPath()
    static let systemLaunchDaemonsDir = "/Library/LaunchDaemons"
    static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"
    private static let logRotationServiceID = "com.keypath.logrotate"

    /// Path to the log rotation script
    private static let logRotationScriptPath = "/usr/local/bin/keypath-logrotate.sh"

    /// Path to the Kanata service plist file
    static var kanataPlistPath: String {
        "\(systemLaunchDaemonsDir)/\(kanataServiceID).plist"
    }

    // Use user config path following industry standard ~/.config/ pattern
    private static var kanataConfigPath: String {
        WizardSystemPaths.userConfigPath
    }

    private static let vhidDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    // MARK: - Initialization

    init(packageManager: PackageManager = PackageManager()) {
        self.packageManager = packageManager
    }

    // MARK: - Diagnostic Methods

    /// Test admin dialog capability - use this to diagnose osascript issues
    func testAdminDialog() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Testing admin dialog capability...")
        AppLogger.shared.log("🔧 [LaunchDaemon] Current thread: \(Thread.isMainThread ? "main" : "background")")

        let testCommand = "echo 'Admin dialog test successful'"
        let osascriptCode = """
        do shell script "\(testCommand)" with administrator privileges with prompt "KeyPath Admin Dialog Test - This is a test of the admin password dialog. Please enter your password to confirm it's working."
        """

        var success = false

        if Thread.isMainThread {
            success = executeOSAScriptOnMainThread(osascriptCode)
        } else {
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                success = self.executeOSAScriptOnMainThread(osascriptCode)
                semaphore.signal()
            }
            semaphore.wait()
        }

        AppLogger.shared.log("🔧 [LaunchDaemon] Admin dialog test result: \(success)")
        return success
    }

    private func executeOSAScriptOnMainThread(_ osascriptCode: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCode]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔧 [LaunchDaemon] OSAScript test output: \(output)")
            return task.terminationStatus == 0
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] OSAScript test failed: \(error)")
            return false
        }
    }

    // MARK: - Warm-up tracking (to distinguish "starting" from "failed")

    private static var lastKickstartTimes: [String: Date] = [:]
    private static let healthyWarmupWindow: TimeInterval = 2.0

    private func markRestartTime(for serviceIDs: [String]) {
        let now = Date()
        for id in serviceIDs {
            Self.lastKickstartTimes[id] = now
        }
    }

    // Expose read access across instances
    static func wasRecentlyRestarted(_ serviceID: String, within seconds: TimeInterval? = nil) -> Bool {
        guard let last = lastKickstartTimes[serviceID] else { return false }
        let window = seconds ?? healthyWarmupWindow
        return Date().timeIntervalSince(last) < window
    }

    static func hadRecentRestart(within seconds: TimeInterval = healthyWarmupWindow) -> Bool {
        let now = Date()
        return lastKickstartTimes.values.contains { now.timeIntervalSince($0) < seconds }
    }

    // MARK: - Env/Test helpers

    private static let isTestMode: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["KEYPATH_TEST_MODE"] == "1"
    }()

    private static func resolveLaunchDaemonsPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let override = env["KEYPATH_LAUNCH_DAEMONS_DIR"], !override.isEmpty {
            return override
        }
        return "/Library/LaunchDaemons"
    }

    /// Escapes a shell command string for safe embedding in AppleScript
    private func escapeForAppleScript(_ command: String) -> String {
        var escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    // MARK: - Path Detection Methods

    /// Gets the detected Kanata binary path or returns fallback
    private func getKanataBinaryPath() -> String {
        // Unify on a single canonical binary path to align permissions and UI guidance
        let standardPath = WizardSystemPaths.kanataActiveBinary
        AppLogger.shared.log("✅ [LaunchDaemon] Using canonical Kanata path: \(standardPath)")
        return standardPath
    }

    // MARK: - Installation Methods

    /// Creates and installs all LaunchDaemon services with a single admin prompt
    func createAllLaunchDaemonServices() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating all LaunchDaemon services")

        let kanataBinaryPath = getKanataBinaryPath()

        // Generate all plist contents
        let kanataPlist = generateKanataPlist(binaryPath: kanataBinaryPath)
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()

        // Create temporary files for all plists
        let tempDir = NSTemporaryDirectory()
        let kanataTempPath = "\(tempDir)\(Self.kanataServiceID).plist"
        let vhidDaemonTempPath = "\(tempDir)\(Self.vhidDaemonServiceID).plist"
        let vhidManagerTempPath = "\(tempDir)\(Self.vhidManagerServiceID).plist"

        do {
            // Write all plist contents to temporary files
            try kanataPlist.write(toFile: kanataTempPath, atomically: true, encoding: .utf8)
            try vhidDaemonPlist.write(toFile: vhidDaemonTempPath, atomically: true, encoding: .utf8)
            try vhidManagerPlist.write(toFile: vhidManagerTempPath, atomically: true, encoding: .utf8)

            // Install all services with a single admin prompt
            let success = executeAllWithAdminPrivileges(
                kanataTemp: kanataTempPath,
                vhidDaemonTemp: vhidDaemonTempPath,
                vhidManagerTemp: vhidManagerTempPath
            )

            // Clean up temporary files
            try? FileManager.default.removeItem(atPath: kanataTempPath)
            try? FileManager.default.removeItem(atPath: vhidDaemonTempPath)
            try? FileManager.default.removeItem(atPath: vhidManagerTempPath)

            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plists: \(error)")
            return false
        }
    }

    /// Creates and installs the Kanata LaunchDaemon service
    func createKanataLaunchDaemon() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating Kanata LaunchDaemon service")

        let kanataBinaryPath = getKanataBinaryPath()
        let plistContent = generateKanataPlist(binaryPath: kanataBinaryPath)
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"

        return installPlist(content: plistContent, path: plistPath, serviceID: Self.kanataServiceID)
    }

    /// Creates and installs the VirtualHIDDevice Daemon LaunchDaemon service
    func createVHIDDaemonService() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating VHIDDevice Daemon LaunchDaemon service")

        let plistContent = generateVHIDDaemonPlist()
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"

        return installPlist(content: plistContent, path: plistPath, serviceID: Self.vhidDaemonServiceID)
    }

    /// Creates and installs the VirtualHIDDevice Manager LaunchDaemon service
    func createVHIDManagerService() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating VHIDDevice Manager LaunchDaemon service")

        let plistContent = generateVHIDManagerPlist()
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        return installPlist(
            content: plistContent, path: plistPath, serviceID: Self.vhidManagerServiceID
        )
    }

    /// Creates, installs, configures, and loads all LaunchDaemon services with a single admin prompt
    /// This method consolidates all admin operations to eliminate multiple password prompts
    func createConfigureAndLoadAllServices() -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] *** ENTRY POINT *** createConfigureAndLoadAllServices() called")
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Creating, configuring, and loading all services with single admin prompt")
        AppLogger.shared.log("🔧 [LaunchDaemon] This method SHOULD trigger osascript password prompt")

        let kanataBinaryPath = getKanataBinaryPath()

        // Generate all plist contents
        let kanataPlist = generateKanataPlist(binaryPath: kanataBinaryPath)
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()

        // Create temporary files for all plists
        let tempDir = NSTemporaryDirectory()
        let kanataTempPath = "\(tempDir)\(Self.kanataServiceID).plist"
        let vhidDaemonTempPath = "\(tempDir)\(Self.vhidDaemonServiceID).plist"
        let vhidManagerTempPath = "\(tempDir)\(Self.vhidManagerServiceID).plist"

        do {
            // Write all plist contents to temporary files
            try kanataPlist.write(toFile: kanataTempPath, atomically: true, encoding: .utf8)
            try vhidDaemonPlist.write(toFile: vhidDaemonTempPath, atomically: true, encoding: .utf8)
            try vhidManagerPlist.write(toFile: vhidManagerTempPath, atomically: true, encoding: .utf8)

            // Execute consolidated admin operations with a single prompt
            // Use improved osascript approach with proper entitlements and main thread execution
            let success = executeConsolidatedInstallationImproved(
                kanataTemp: kanataTempPath,
                vhidDaemonTemp: vhidDaemonTempPath,
                vhidManagerTemp: vhidManagerTempPath
            )

            // Clean up temporary files
            try? FileManager.default.removeItem(atPath: kanataTempPath)
            try? FileManager.default.removeItem(atPath: vhidDaemonTempPath)
            try? FileManager.default.removeItem(atPath: vhidManagerTempPath)

            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plists: \(error)")
            return false
        }
    }

    /// Loads all KeyPath LaunchDaemon services
    func loadServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Loading all KeyPath LaunchDaemon services")

        let services = [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
        var allSucceeded = true

        for serviceID in services {
            let success = await loadService(serviceID: serviceID)
            if !success {
                allSucceeded = false
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to load service: \(serviceID)")
            }
        }

        return allSucceeded
    }

    // MARK: - Service Management

    /// Loads a specific LaunchDaemon service
    private func loadService(serviceID: String) async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Loading service: \(serviceID)")
        if Self.isTestMode {
            return FileManager.default.fileExists(atPath: "\(Self.launchDaemonsPath)/\(serviceID).plist")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", "-w", "\(Self.launchDaemonsPath)/\(serviceID).plist"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully loaded service: \(serviceID)")
                // Loading triggers program start; mark warm-up
                markRestartTime(for: [serviceID])
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to load service \(serviceID): \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error loading service \(serviceID): \(error)")
            return false
        }
    }

    /// Unloads a specific LaunchDaemon service
    private func unloadService(serviceID: String) async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Unloading service: \(serviceID)")
        if Self.isTestMode { return true }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", "\(Self.launchDaemonsPath)/\(serviceID).plist"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully unloaded service: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log(
                    "⚠️ [LaunchDaemon] Service \(serviceID) may not have been loaded: \(output)")
                return true // Not an error if it wasn't loaded
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error unloading service \(serviceID): \(error)")
            return false
        }
    }

    /// Checks if a LaunchDaemon service is currently loaded
    func isServiceLoaded(serviceID: String) -> Bool {
        if Self.isTestMode {
            let exists = FileManager.default.fileExists(
                atPath: "\(Self.launchDaemonsPath)/\(serviceID).plist")
            AppLogger.shared.log(
                "🔍 [LaunchDaemon] (test) Service \(serviceID) considered loaded: \(exists)")
            return exists
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(serviceID)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let isLoaded = task.terminationStatus == 0
            AppLogger.shared.log("🔍 [LaunchDaemon] (system) Service \(serviceID) loaded: \(isLoaded)")
            return isLoaded
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking service \(serviceID): \(error)")
            return false
        }
    }

    /// Checks if a LaunchDaemon service is running healthily (not just loaded)
    func isServiceHealthy(serviceID: String) -> Bool {
        AppLogger.shared.log("🔍 [LaunchDaemon] HEALTH CHECK (system/print) for: \(serviceID)")

        if Self.isTestMode {
            let exists = FileManager.default.fileExists(
                atPath: "\(Self.launchDaemonsPath)/\(serviceID).plist")
            AppLogger.shared.log(
                "🔍 [LaunchDaemon] (test) Service \(serviceID) considered healthy: \(exists)")
            return exists
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(serviceID)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                AppLogger.shared.log("🔍 [LaunchDaemon] \(serviceID) not found in system domain")
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Extract details from 'launchctl print' output
            let state = output.firstMatchString(pattern: #"state\s*=\s*([A-Za-z]+)"#)?.lowercased()
            let pid = output.firstMatchInt(pattern: #"\bpid\s*=\s*([0-9]+)"#)
                ?? output.firstMatchInt(pattern: #""PID"\s*=\s*([0-9]+)"#)
            let lastExit =
                output.firstMatchInt(pattern: #"last exit (?:status|code)\s*=\s*(-?\d+)"#)
                    ?? output.firstMatchInt(pattern: #""LastExitStatus"\s*=\s*(-?\d+)"#)

            let isOneShot = (serviceID == Self.vhidManagerServiceID)
            let isRunningLike = (state == "running" || state == "launching")
            let hasPID = (pid != nil)
            let inWarmup = Self.wasRecentlyRestarted(serviceID)

            var healthy = false
            if isOneShot {
                // One-shot: OK if clean exit or (still running) or within warm-up window
                if let lastExit, lastExit == 0 { healthy = true } else if isRunningLike || hasPID { healthy = true } else if inWarmup { healthy = true } // starting up
                else { healthy = false }
            } else {
                // KeepAlive jobs should be running. Allow starting states or warm-up.
                if isRunningLike || hasPID { healthy = true } else if inWarmup { healthy = true } // starting up
                else { healthy = false }
            }

            AppLogger.shared.log("🔍 [LaunchDaemon] HEALTH ANALYSIS \(serviceID):")
            AppLogger.shared.log("    state=\(state ?? "nil"), pid=\(pid?.description ?? "nil"), lastExit=\(lastExit?.description ?? "nil"), oneShot=\(isOneShot), warmup=\(inWarmup), healthy=\(healthy)")

            return healthy
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking service health \(serviceID): \(error)")
            return false
        }
    }

    // MARK: - Plist Generation

    private func generateKanataPlist(binaryPath: String) -> String {
        let arguments = buildKanataPlistArguments(binaryPath: binaryPath)

        var argumentsXML = ""
        for arg in arguments {
            argumentsXML += "                <string>\(arg)</string>\n"
        }
        // Ensure proper indentation for the XML
        argumentsXML = argumentsXML.trimmingCharacters(in: .newlines)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.kanataServiceID)</string>
            <key>ProgramArguments</key>
            <array>
            \(argumentsXML)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/kanata.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/kanata.log</string>
            <key>SoftResourceLimits</key>
            <dict>
                <key>NumberOfFiles</key>
                <integer>256</integer>
            </dict>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
            <key>ThrottleInterval</key>
            <integer>10</integer>
        </dict>
        </plist>
        """
    }

    private func generateVHIDDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.vhidDaemonServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Self.vhidDaemonPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/karabiner-vhid-daemon.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/karabiner-vhid-daemon.log</string>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
            <key>ThrottleInterval</key>
            <integer>10</integer>
        </dict>
        </plist>
        """
    }

    private func generateVHIDManagerPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.vhidManagerServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Self.vhidManagerPath)</string>
                <string>activate</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/var/log/karabiner-vhid-manager.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/karabiner-vhid-manager.log</string>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
        </dict>
        </plist>
        """
    }

    // MARK: - File System Operations

    private func installPlist(content: String, path: String, serviceID: String) -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing plist: \(path)")

        // Create temporary file with plist content
        let tempDir = NSTemporaryDirectory()
        let tempPath = "\(tempDir)\(serviceID).plist"

        do {
            // Write content to temporary file first
            try content.write(toFile: tempPath, atomically: true, encoding: .utf8)

            // Use admin privileges to install the plist (unless in test mode)
            let success: Bool
            if Self.isTestMode {
                do {
                    try FileManager.default.createDirectory(
                        atPath: (path as NSString).deletingLastPathComponent,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    try FileManager.default.removeItem(atPath: path)
                } catch { /* ignore if not exists */ }
                do {
                    try FileManager.default.copyItem(atPath: tempPath, toPath: path)
                    success = true
                } catch {
                    AppLogger.shared.log("❌ [LaunchDaemon] (test) copy failed: \(error)")
                    success = false
                }
            } else {
                success = executeWithAdminPrivileges(
                    tempPath: tempPath,
                    finalPath: path,
                    serviceID: serviceID
                )
            }

            // Clean up temporary file
            try? FileManager.default.removeItem(atPath: tempPath)

            return success
        } catch {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Failed to create temporary plist \(serviceID): \(error)")
            return false
        }
    }

    /// Execute all LaunchDaemon installations with a single administrator privileges request
    private func executeAllWithAdminPrivileges(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Requesting admin privileges to install all services")
        if Self.isTestMode {
            do {
                let fm = FileManager.default
                try fm.createDirectory(atPath: Self.launchDaemonsPath, withIntermediateDirectories: true)
                let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
                let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
                let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
                for (src, dst) in [
                    (kanataTemp, kanataFinal), (vhidDaemonTemp, vhidDaemonFinal),
                    (vhidManagerTemp, vhidManagerFinal)
                ] {
                    try? fm.removeItem(atPath: dst)
                    try fm.copyItem(atPath: src, toPath: dst)
                }
                AppLogger.shared.log(
                    "✅ [LaunchDaemon] (test) Installed all plists to \(Self.launchDaemonsPath)")
                return true
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] (test) Failed to install plists: \(error)")
                return false
            }
        }

        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        // Create a single compound command that installs all three services
        let command = """
        mkdir -p '\(Self.launchDaemonsPath)' && \
        cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)' && \
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)' && \
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'
        """

        // Use osascript to request admin privileges with proper password dialog
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to install LaunchDaemon services for keyboard management."
        """

        let osascriptTask = Process()
        osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptTask.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        osascriptTask.standardOutput = pipe
        osascriptTask.standardError = pipe

        do {
            try osascriptTask.run()
            osascriptTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if osascriptTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed all LaunchDaemon services")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install services: \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute admin command: \(error)")
            return false
        }
    }

    /// Execute LaunchDaemon installation with administrator privileges using osascript
    private func executeWithAdminPrivileges(tempPath: String, finalPath: String, serviceID: String)
        -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Requesting admin privileges to install \(serviceID)")

        // Create the command to copy the file and set proper permissions
        let command =
            "mkdir -p '\(Self.launchDaemonsPath)' && cp '\(tempPath)' '\(finalPath)' && chown root:wheel '\(finalPath)' && chmod 644 '\(finalPath)'"

        // Use osascript to request admin privileges with proper password dialog
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to install LaunchDaemon services for keyboard management."
        """

        let osascriptTask = Process()
        osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptTask.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        osascriptTask.standardOutput = pipe
        osascriptTask.standardError = pipe

        do {
            try osascriptTask.run()
            osascriptTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if osascriptTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed plist: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install plist \(serviceID): \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Failed to execute admin command for \(serviceID): \(error)")
            return false
        }
    }

    /// Execute consolidated installation using native Authorization Services
    /// This is the most reliable approach for GUI apps on macOS
    private func executeConsolidatedInstallationWithAuthServices(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Starting consolidated installation with Authorization Services")
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] This approach bypasses osascript sandbox restrictions")

        // Create the installation script
        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
        let currentUserName = NSUserName()

        let script = """
        #!/bin/bash
        set -e
        echo "Starting LaunchDaemon installation with Authorization Services..."

        # Create LaunchDaemons directory
        mkdir -p '\(Self.launchDaemonsPath)'

        # Install plist files with proper ownership
        cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)'
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)'
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'

        # Create user configuration directory and file
        sudo -u '\(currentUserName)' mkdir -p '/Users/\(currentUserName)/.config/keypath'
        sudo -u '\(currentUserName)' touch '/Users/\(currentUserName)/.config/keypath/keypath.kbd'

        # Load services
        launchctl load '\(kanataFinal)'
        launchctl load '\(vhidDaemonFinal)'
        launchctl load '\(vhidManagerFinal)'

        # Start services
        launchctl kickstart -k system/\(Self.kanataServiceID)
        launchctl kickstart -k system/\(Self.vhidDaemonServiceID)
        launchctl kickstart -k system/\(Self.vhidManagerServiceID)

        echo "Installation completed successfully with Authorization Services"
        """

        // Create temporary script
        let tempScriptPath = NSTemporaryDirectory() + "keypath-auth-install-\(UUID().uuidString).sh"

        do {
            try script.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)

            // Use Authorization Services for privilege escalation
            let success = requestAdminPrivilegesAndExecute(scriptPath: tempScriptPath)

            // Clean up
            try? FileManager.default.removeItem(atPath: tempScriptPath)

            if success {
                AppLogger.shared.log("✅ [LaunchDaemon] Authorization Services installation completed successfully")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Authorization Services installation failed")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error with Authorization Services approach: \(error)")
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            return false
        }
    }

    private func requestAdminPrivilegesAndExecute(scriptPath: String) -> Bool {
        AppLogger.shared.log("🔐 [LaunchDaemon] Requesting admin privileges via Authorization Services")

        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errSecSuccess else {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create authorization reference: \(status)")
            return false
        }

        defer {
            if let authRef {
                AuthorizationFree(authRef, [])
            }
        }

        // Request admin privileges
        var authItem = AuthorizationItem(
            name: kAuthorizationRightExecute,
            valueLength: 0,
            value: nil,
            flags: 0
        )

        var authRights = AuthorizationRights(count: 1, items: &authItem)

        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]

        status = AuthorizationCopyRights(authRef!, &authRights, nil, flags, nil)

        guard status == errSecSuccess else {
            if status == errSecUserCanceled {
                AppLogger.shared.log("ℹ️ [LaunchDaemon] User canceled admin authorization")
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to get admin authorization: \(status)")
            }
            return false
        }

        AppLogger.shared.log("✅ [LaunchDaemon] Admin authorization granted, executing script")

        // Execute the script with admin privileges
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            // This execution should have the admin privileges we requested
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔐 [LaunchDaemon] Script execution completed with status: \(task.terminationStatus)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Output: \(output)")

            return task.terminationStatus == 0

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute admin script: \(error)")
            return false
        }
    }

    /// Execute consolidated installation with improved osascript execution
    /// This method addresses sandbox restrictions by ensuring proper execution context
    private func executeConsolidatedInstallationImproved(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Starting consolidated installation with improved osascript")
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Using direct osascript execution with proper environment")

        // Build installation script (same as before)
        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
        let currentUserName = NSUserName()

        let command = """
        set -e
        echo "Starting LaunchDaemon installation..."

        # Create LaunchDaemons directory
        mkdir -p '\(Self.launchDaemonsPath)'

        # Install plist files with proper ownership
        cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)'
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)'
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'

        # Create user configuration directory and file
        sudo -u '\(currentUserName)' mkdir -p '/Users/\(currentUserName)/.config/keypath'
        sudo -u '\(currentUserName)' touch '/Users/\(currentUserName)/.config/keypath/keypath.kbd'

        # Load services
        launchctl load '\(kanataFinal)'
        launchctl load '\(vhidDaemonFinal)'
        launchctl load '\(vhidManagerFinal)'

        # Start services
        launchctl kickstart -k system/\(Self.kanataServiceID)
        launchctl kickstart -k system/\(Self.vhidDaemonServiceID)
        launchctl kickstart -k system/\(Self.vhidManagerServiceID)

        echo "Installation completed successfully"
        """

        // Create a temporary script file
        let tempScriptPath = NSTemporaryDirectory() + "keypath-install-\(UUID().uuidString).sh"

        do {
            try command.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)

            // Set executable permissions
            let fileManager = FileManager.default
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)

            // Use osascript to execute the script with admin privileges
            // Custom prompt to clearly identify KeyPath (not osascript)
            let osascriptCode = """
            do shell script "bash '\(tempScriptPath)'" with administrator privileges with prompt "KeyPath needs administrator access to install system services for keyboard management. This will enable the TCP server on port \(PreferencesService.tcpSnapshot().port)."
            """

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osascriptCode]
            task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            AppLogger.shared.log("🔐 [LaunchDaemon] Executing osascript with temp script approach...")
            AppLogger.shared.log("🔐 [LaunchDaemon] Script path: \(tempScriptPath)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Current thread: \(Thread.isMainThread ? "main" : "background")")

            // CRITICAL FIX: Admin dialogs must run on main thread for macOS security
            var taskSuccess = false
            var taskStatus: Int32 = -1
            var taskOutput = ""

            if Thread.isMainThread {
                AppLogger.shared.log("🔐 [LaunchDaemon] Executing on main thread")
                try task.run()
                task.waitUntilExit()
                taskStatus = task.terminationStatus
                taskSuccess = true
            } else {
                AppLogger.shared.log("🔐 [LaunchDaemon] Dispatching to main thread for admin dialog")
                let semaphore = DispatchSemaphore(value: 0)

                DispatchQueue.main.async {
                    do {
                        try task.run()
                        task.waitUntilExit()
                        taskStatus = task.terminationStatus
                        taskSuccess = true
                        AppLogger.shared.log("🔐 [LaunchDaemon] Main thread execution completed")
                    } catch {
                        AppLogger.shared.log("❌ [LaunchDaemon] Main thread execution failed: \(error)")
                        taskSuccess = false
                    }
                    semaphore.signal()
                }

                semaphore.wait()
            }

            if !taskSuccess {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute osascript task")
                try? fileManager.removeItem(atPath: tempScriptPath)
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔐 [LaunchDaemon] osascript completed with status: \(taskStatus)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Output: \(output)")

            // Clean up temp script
            try? fileManager.removeItem(atPath: tempScriptPath)

            if taskStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully completed installation with main thread osascript")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] osascript installation failed with status: \(taskStatus)")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error with improved osascript approach: \(error)")
            // Clean up temp script on error
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            return false
        }
    }

    /// Execute consolidated installation with all operations in a single admin prompt
    /// Includes: install plists, create system config directory, create system config file, and load services
    private func executeConsolidatedInstallation(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Executing consolidated installation with single admin prompt")

        if Self.isTestMode {
            // Test mode - use file operations without admin privileges
            do {
                let fm = FileManager.default
                try fm.createDirectory(atPath: Self.launchDaemonsPath, withIntermediateDirectories: true)
                try fm.createDirectory(
                    atPath: WizardSystemPaths.userConfigDirectory, withIntermediateDirectories: true
                )

                let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
                let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
                let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

                for (src, dst) in [
                    (kanataTemp, kanataFinal), (vhidDaemonTemp, vhidDaemonFinal),
                    (vhidManagerTemp, vhidManagerFinal)
                ] {
                    try? fm.removeItem(atPath: dst)
                    try fm.copyItem(atPath: src, toPath: dst)
                }

                // Create a basic config file for testing
                try "test config".write(
                    toFile: WizardSystemPaths.userConfigPath, atomically: true, encoding: .utf8
                )

                AppLogger.shared.log("✅ [LaunchDaemon] (test) Consolidated installation completed")
                return true
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] (test) Failed consolidated installation: \(error)")
                return false
            }
        }

        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        // Get user config directory for initial setup
        let userConfigDir = WizardSystemPaths.userConfigDirectory
        let userConfigPath = WizardSystemPaths.userConfigPath

        // Create a comprehensive command that does everything in one admin operation
        let command = """
        /bin/echo Installing LaunchDaemon services and configuration... && \
        /bin/mkdir -p '\(Self.launchDaemonsPath)' && \
        /usr/bin/install -m 0644 -o root -g wheel '\(kanataTemp)' '\(kanataFinal)' && \
        /usr/bin/install -m 0644 -o root -g wheel '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && \
        /usr/bin/install -m 0644 -o root -g wheel '\(vhidManagerTemp)' '\(vhidManagerFinal)' && \
        CONSOLE_UID="$(/usr/bin/stat -f %u /dev/console)" && \
        CONSOLE_GID="$(/usr/bin/id -g $CONSOLE_UID)" && \
        /usr/bin/install -d -m 0755 -o $CONSOLE_UID -g $CONSOLE_GID '\(userConfigDir)' && \
        if [ ! -f '\(userConfigPath)' ]; then \
          /usr/bin/printf "%s\\n" ";; Default KeyPath config" "(defcfg process-unmapped-keys no)" "(defsrc)" "(deflayer base)" | /usr/bin/tee '\(userConfigPath)' >/dev/null && \
          /usr/sbin/chown $CONSOLE_UID:$CONSOLE_GID '\(userConfigPath)'; \
        fi && \
        /bin/launchctl bootstrap system '\(kanataFinal)' 2>/dev/null || /bin/echo Kanata service already loaded && \
        /bin/launchctl bootstrap system '\(vhidDaemonFinal)' 2>/dev/null || /bin/echo VHID daemon already loaded && \
        /bin/launchctl bootstrap system '\(vhidManagerFinal)' 2>/dev/null || /bin/echo VHID manager already loaded && \
        /bin/echo Installation completed successfully
        """

        // Use osascript to request admin privileges with clear explanation
        AppLogger.shared.log("🔐 [LaunchDaemon] *** ABOUT TO EXECUTE OSASCRIPT FOR ADMIN PRIVILEGES ***")
        AppLogger.shared.log("🔐 [LaunchDaemon] This should show a password dialog to the user")
        AppLogger.shared.log("🔐 [LaunchDaemon] isTestMode = \(Self.isTestMode)")

        // Escape the command for safe AppleScript embedding
        let escapedCommand = escapeForAppleScript(command)

        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs administrator access to install LaunchDaemon services, create configuration files, and start the keyboard services. This will be a single prompt."
        """

        AppLogger.shared.log("🔐 [LaunchDaemon] osascript command length: \(osascriptCommand.count) characters")
        AppLogger.shared.log("🔐 [LaunchDaemon] Starting osascript process...")

        let osascriptTask = Process()
        osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptTask.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        osascriptTask.standardOutput = pipe
        osascriptTask.standardError = pipe

        do {
            AppLogger.shared.log("🔐 [LaunchDaemon] Executing osascript.run()...")
            try osascriptTask.run()
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript.run() succeeded, now waiting for completion...")
            osascriptTask.waitUntilExit()
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript completed with status: \(osascriptTask.terminationStatus)")

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript output: \(output)")

            if osascriptTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully completed consolidated installation")
                AppLogger.shared.log("🔧 [LaunchDaemon] Admin output: \(output)")
                // Mark warm-up for all services we just installed+bootstrapped
                markRestartTime(for: [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID])
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed consolidated installation: \(output)")
                AppLogger.shared.log("❌ [LaunchDaemon] Exit status was: \(osascriptTask.terminationStatus)")
                return false
            }
        } catch {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Failed to execute consolidated admin command: \(error)")
            AppLogger.shared.log("❌ [LaunchDaemon] This means osascript.run() threw an exception")
            return false
        }
    }

    // MARK: - Cleanup Methods

    /// Removes all KeyPath LaunchDaemon services
    func removeAllServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Removing all KeyPath LaunchDaemon services")

        let services = [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
        var allSucceeded = true

        for serviceID in services {
            // First unload the service
            let unloadSuccess = await unloadService(serviceID: serviceID)

            // Then remove the plist file
            let plistPath = "\(Self.launchDaemonsPath)/\(serviceID).plist"
            let removeSuccess = removePlist(path: plistPath, serviceID: serviceID)

            if !unloadSuccess || !removeSuccess {
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    private func removePlist(path: String, serviceID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "rm", "-f", path]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully removed plist: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to remove plist: \(serviceID)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error removing plist \(serviceID): \(error)")
            return false
        }
    }

    // MARK: - Status Methods

    /// Gets comprehensive status of all LaunchDaemon services
    func getServiceStatus() -> LaunchDaemonStatus {
        let kanataLoaded = isServiceLoaded(serviceID: Self.kanataServiceID)
        let vhidDaemonLoaded = isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerLoaded = isServiceLoaded(serviceID: Self.vhidManagerServiceID)

        let kanataHealthy = isServiceHealthy(serviceID: Self.kanataServiceID)
        let vhidDaemonHealthy = isServiceHealthy(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerHealthy = isServiceHealthy(serviceID: Self.vhidManagerServiceID)

        return LaunchDaemonStatus(
            kanataServiceLoaded: kanataLoaded,
            vhidDaemonServiceLoaded: vhidDaemonLoaded,
            vhidManagerServiceLoaded: vhidManagerLoaded,
            kanataServiceHealthy: kanataHealthy,
            vhidDaemonServiceHealthy: vhidDaemonHealthy,
            vhidManagerServiceHealthy: vhidManagerHealthy
        )
    }

    /// Check if Kanata service plist file exists (but may not be loaded)
    func isKanataPlistInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.kanataPlistPath)
    }

    /// Install LaunchDaemon service files without loading/starting them
    /// Used for adopting orphaned processes - installs management files but doesn't interfere with running process
    func createAllLaunchDaemonServicesInstallOnly() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing service files only (no load/start)...")

        // Create all required plist files
        let kanataSuccess = createKanataLaunchDaemon()
        let vhidDaemonSuccess = createVHIDDaemonService()
        let vhidManagerSuccess = createVHIDManagerService()

        let success = kanataSuccess && vhidDaemonSuccess && vhidManagerSuccess
        AppLogger.shared.log("🔧 [LaunchDaemon] Install-only result: kanata=\(kanataSuccess), vhidDaemon=\(vhidDaemonSuccess), vhidManager=\(vhidManagerSuccess), overall=\(success)")

        return success
    }

    /// Verifies that the installed VHID LaunchDaemon plist points to the DriverKit daemon path
    func isVHIDDaemonConfiguredCorrectly() -> Bool {
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            AppLogger.shared.log("🔍 [LaunchDaemon] VHID plist not found or unreadable at: \(plistPath)")
            return false
        }

        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            let ok = first == Self.vhidDaemonPath
            AppLogger.shared.log(
                "🔍 [LaunchDaemon] VHID plist ProgramArguments[0]=\(first) | expected=\(Self.vhidDaemonPath) | ok=\(ok)"
            )
            return ok
        }
        AppLogger.shared.log("🔍 [LaunchDaemon] VHID plist ProgramArguments missing or malformed")
        return false
    }

    /// Restarts services with admin privileges using launchctl kickstart
    private func restartServicesWithAdmin(_ serviceIDs: [String]) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] *** ENHANCED RESTART *** Restarting services: \(serviceIDs)")

        if Self.isTestMode {
            AppLogger.shared.log("🔧 [LaunchDaemon] Test mode - simulating successful restart")
            return true
        }
        guard !serviceIDs.isEmpty else {
            AppLogger.shared.log("🔧 [LaunchDaemon] No services to restart - returning success")
            return true
        }

        let cmds = serviceIDs.map { "launchctl kickstart -k system/\($0)" }.joined(separator: " && ")
        AppLogger.shared.log("🔧 [LaunchDaemon] Executing admin command: \(cmds)")

        let escapedCmds = escapeForAppleScript(cmds)
        let script = """
        do shell script "\(escapedCmds)" with administrator privileges with prompt "KeyPath needs to restart failing system services."
        """

        AppLogger.shared.log("🔧 [LaunchDaemon] Running osascript with admin privileges...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        // Capture both stdout and stderr for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            // Read output and error streams
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "(no output)"
            let error = String(data: errorData, encoding: .utf8) ?? "(no error)"

            AppLogger.shared.log(
                "🔧 [LaunchDaemon] osascript termination status: \(task.terminationStatus)")
            AppLogger.shared.log("🔧 [LaunchDaemon] osascript stdout: \(output)")
            AppLogger.shared.log("🔧 [LaunchDaemon] osascript stderr: \(error)")

            let success = task.terminationStatus == 0
            AppLogger.shared.log(
                "🔧 [LaunchDaemon] Admin restart command result: \(success ? "SUCCESS" : "FAILED")")
            if success {
                // Mark warm-up start time for those services
                markRestartTime(for: serviceIDs)
            }
            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] kickstart admin failed with exception: \(error)")
            return false
        }
    }

    /// Restarts unhealthy services and diagnoses/fixes underlying issues
    func restartUnhealthyServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Starting comprehensive service health fix")

        let initialStatus = getServiceStatus()
        var toRestart: [String] = []
        var toInstall: [String] = []

        // Categorize services by what they need
        if initialStatus.kanataServiceLoaded, !initialStatus.kanataServiceHealthy {
            toRestart.append(Self.kanataServiceID)
        } else if !initialStatus.kanataServiceLoaded {
            toInstall.append(Self.kanataServiceID)
        }

        if initialStatus.vhidDaemonServiceLoaded, !initialStatus.vhidDaemonServiceHealthy {
            toRestart.append(Self.vhidDaemonServiceID)
        } else if !initialStatus.vhidDaemonServiceLoaded {
            toInstall.append(Self.vhidDaemonServiceID)
        }

        if initialStatus.vhidManagerServiceLoaded, !initialStatus.vhidManagerServiceHealthy {
            toRestart.append(Self.vhidManagerServiceID)
        } else if !initialStatus.vhidManagerServiceLoaded {
            toInstall.append(Self.vhidManagerServiceID)
        }

        // Step 1: Install missing services first if needed
        if !toInstall.isEmpty {
            AppLogger.shared.log("🔧 [LaunchDaemon] Installing missing services: \(toInstall)")
            let installSuccess = createConfigureAndLoadAllServices()
            if !installSuccess {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install missing services")
                return false
            }
            AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed missing services")

            // Wait for installation to settle
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }

        // Step 2: Handle unhealthy services
        if toRestart.isEmpty {
            AppLogger.shared.log("🔍 [LaunchDaemon] No unhealthy services found to restart")
            return true
        }

        AppLogger.shared.log("🔧 [LaunchDaemon] Services to restart: \(toRestart)")

        // Step 3: Diagnose issues before restarting
        await diagnoseServiceFailures(toRestart)

        // Step 4: Execute the restart command
        let restartOk = restartServicesWithAdmin(toRestart)
        if !restartOk {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute restart commands")
            return false
        }

        AppLogger.shared.log("✅ [LaunchDaemon] Restart commands executed successfully")

        // Step 5: Wait for services to start up (poll up to 10 seconds)
        AppLogger.shared.log("⏳ [LaunchDaemon] Waiting for services to start up (polling)...")
        let timeout: TimeInterval = 10.0
        let interval: UInt64 = 500_000_000 // 0.5s
        var elapsed: TimeInterval = 0

        while elapsed < timeout {
            let status = getServiceStatus()
            var allRecovered = true
            if toRestart.contains(Self.kanataServiceID), !status.kanataServiceHealthy { allRecovered = false }
            if toRestart.contains(Self.vhidDaemonServiceID), !status.vhidDaemonServiceHealthy { allRecovered = false }
            if toRestart.contains(Self.vhidManagerServiceID), !status.vhidManagerServiceHealthy { allRecovered = false }

            if allRecovered {
                AppLogger.shared.log("✅ [LaunchDaemon] Services recovered during polling")
                break
            }

            try? await Task.sleep(nanoseconds: interval)
            elapsed += 0.5
        }

        // Step 6: Final verification
        let finalStatus = getServiceStatus()
        var stillUnhealthy: [String] = []

        if toRestart.contains(Self.kanataServiceID), !finalStatus.kanataServiceHealthy {
            stillUnhealthy.append(Self.kanataServiceID)
        }
        if toRestart.contains(Self.vhidDaemonServiceID), !finalStatus.vhidDaemonServiceHealthy {
            stillUnhealthy.append(Self.vhidDaemonServiceID)
        }
        if toRestart.contains(Self.vhidManagerServiceID), !finalStatus.vhidManagerServiceHealthy {
            stillUnhealthy.append(Self.vhidManagerServiceID)
        }

        if stillUnhealthy.isEmpty {
            AppLogger.shared.log("✅ [LaunchDaemon] All restarted services are now healthy")
            return true
        } else {
            AppLogger.shared.log(
                "⚠️ [LaunchDaemon] Some services are still unhealthy after restart: \(stillUnhealthy)")

            // Provide detailed diagnosis with actionable guidance
            await diagnoseServiceFailures(stillUnhealthy)

            // Return success because we successfully:
            // 1. Restarted the services
            // 2. Diagnosed the underlying issues
            // 3. Provided specific guidance for manual resolution
            AppLogger.shared.log(
                "✅ [LaunchDaemon] Fix completed successfully - services restarted and issues diagnosed")
            return true
        }
    }

    /// Diagnose why services are still failing after restart attempt
    private func diagnoseServiceFailures(_ serviceIDs: [String]) async {
        AppLogger.shared.log("🔍 [LaunchDaemon] Diagnosing service failure reasons...")

        for serviceID in serviceIDs {
            await diagnoseSpecificServiceFailure(serviceID)
        }
    }

    /// Diagnose a specific service failure by checking launchctl details
    private func diagnoseSpecificServiceFailure(_ serviceID: String) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(serviceID)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                await analyzeServiceStatus(serviceID, output: output)
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Could not get status for \(serviceID): \(output)")
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking \(serviceID) status: \(error)")
        }
    }

    /// Analyze service status output to determine failure reason
    private func analyzeServiceStatus(_ serviceID: String, output: String) async {
        AppLogger.shared.log("🔍 [LaunchDaemon] Analyzing \(serviceID) status...")

        // For Kanata service, also check the actual logs for detailed error messages
        if serviceID == Self.kanataServiceID {
            await analyzeKanataLogs()
        }

        // Check for common exit reasons
        if output.contains("OS_REASON_CODESIGNING") {
            AppLogger.shared.log("❌ [LaunchDaemon] \(serviceID) is failing due to CODE SIGNING issues")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: KeyPath requires Input Monitoring permission for the kanata binary. Grant permission in System Settings > Privacy & Security > Input Monitoring"
                )
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] If permission is already granted, try using KeyPath's Installation Wizard to reinstall kanata with proper code signing"
                )
            } else {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: The binary needs to be properly code signed or requires system permissions"
                )
            }

            if serviceID == Self.kanataServiceID {
                await checkKanataCodeSigning()
            }
        } else if output.contains("OS_REASON_EXEC") {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] \(serviceID) executable not found or cannot be executed")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Kanata binary may be missing. Use KeyPath's Installation Wizard to install kanata automatically"
                )
            } else {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Check that the binary exists and has correct permissions")
            }
        } else if output.contains("Permission denied") || output.contains("OS_REASON_PERMISSIONS") {
            AppLogger.shared.log("❌ [LaunchDaemon] \(serviceID) failing due to permission issues")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Grant Input Monitoring permission to kanata in System Settings > Privacy & Security > Input Monitoring"
                )
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] You may also need Accessibility permission if using advanced features")
            } else {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Grant required permissions in System Settings > Privacy & Security"
                )
            }
        } else if output.contains("job state = exited") {
            AppLogger.shared.log("⚠️ [LaunchDaemon] \(serviceID) is exiting unexpectedly")

            // Extract exit reason if present
            if let exitReasonMatch = output.range(
                of: #"last exit reason = (.*)"#, options: .regularExpression
            ) {
                let exitReason = String(output[exitReasonMatch])
                AppLogger.shared.log("🔍 [LaunchDaemon] Exit reason: \(exitReason)")
            }
        } else {
            AppLogger.shared.log("⚠️ [LaunchDaemon] \(serviceID) unhealthy for unclear reason")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log("💡 [LaunchDaemon] Check kanata logs: tail -f /var/log/kanata.log")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] Try using KeyPath's Installation Wizard to fix any configuration issues"
                )
            } else {
                AppLogger.shared.log("💡 [LaunchDaemon] Check system logs for more details")
            }
        }
    }

    /// Analyze Kanata logs for specific error patterns
    private func analyzeKanataLogs() async {
        AppLogger.shared.log("🔍 [LaunchDaemon] Analyzing Kanata logs for error patterns...")

        do {
            let logContent = try String(contentsOfFile: "/var/log/kanata.log")
            let lastLines = logContent.components(separatedBy: .newlines).suffix(50).joined(
                separator: "\n")

            if lastLines.contains("IOHIDDeviceOpen error: (iokit/common) not permitted") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: Kanata lacks Input Monitoring permission")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Grant Input Monitoring permission to kanata binary in System Settings > Privacy & Security > Input Monitoring"
                )
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] TIP: Look for 'kanata' in the list or add '/usr/local/bin/kanata' manually"
                )
            } else if lastLines.contains("failed to parse file") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: Configuration file has syntax errors")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Fix configuration syntax or reset to a minimal valid config")
            } else if lastLines.contains("No such file or directory") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: Configuration file missing")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Ensure config file exists at expected location")
            } else if lastLines.contains("Device not configured") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: VirtualHID device not available")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Restart VirtualHID daemon or enable Karabiner driver extension"
                )
            } else {
                AppLogger.shared.log("🔍 [LaunchDaemon] No specific error pattern found in recent logs")
                AppLogger.shared.log("📋 [LaunchDaemon] Recent log snippet: \(lastLines.prefix(200))...")
            }
        } catch {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Could not read kanata logs: \(error)")
        }
    }

    /// Check kanata binary code signing status
    private func checkKanataCodeSigning() async {
        let kanataPath = getKanataBinaryPath()
        guard FileManager.default.fileExists(atPath: kanataPath) else {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Cannot check code signing - kanata binary not found at \(kanataPath)")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-v", "-v", kanataPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Kanata binary appears to be properly signed")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] Issue may be missing Input Monitoring permission - check System Settings"
                )
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Kanata binary code signing issue: \(output)")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Use KeyPath's Installation Wizard to ensure proper kanata installation and permissions, or manually grant Input Monitoring permission"
                )
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking kanata code signing: \(error)")
        }
    }

    /// Repairs VHID daemon and manager services by reinstalling plists with correct DriverKit paths and reloading
    func repairVHIDDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Repairing VHID LaunchDaemon services (DriverKit paths)")

        // Unload services if present
        _ = await unloadService(serviceID: Self.vhidDaemonServiceID)
        _ = await unloadService(serviceID: Self.vhidManagerServiceID)

        // Reinstall plists with correct content
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()
        let daemonPlistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let managerPlistPath = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        let daemonInstall = installPlist(
            content: vhidDaemonPlist, path: daemonPlistPath, serviceID: Self.vhidDaemonServiceID
        )
        let managerInstall = installPlist(
            content: vhidManagerPlist, path: managerPlistPath, serviceID: Self.vhidManagerServiceID
        )

        guard daemonInstall, managerInstall else {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to install repaired VHID plists")
            return false
        }

        // Load services
        let daemonLoad = await loadService(serviceID: Self.vhidDaemonServiceID)
        let managerLoad = await loadService(serviceID: Self.vhidManagerServiceID)

        let ok = daemonLoad && managerLoad && isVHIDDaemonConfiguredCorrectly()
        AppLogger.shared.log(
            "🔍 [LaunchDaemon] Repair result: loadedDaemon=\(daemonLoad), loadedManager=\(managerLoad), configured=\(isVHIDDaemonConfiguredCorrectly())"
        )
        return ok
    }

    // MARK: - Argument Building

    /// Builds Kanata command line arguments for LaunchDaemon plist including TCP port when enabled
    private func buildKanataPlistArguments(binaryPath: String) -> [String] {
        var arguments = [binaryPath, "--cfg", Self.kanataConfigPath]

        // Add TCP port if enabled and valid
        let tcpConfig = PreferencesService.tcpSnapshot()
        if tcpConfig.shouldUseTCPServer {
            arguments.append("--port")
            arguments.append(String(tcpConfig.port))
            AppLogger.shared.log("🌐 [LaunchDaemon] TCP server enabled on port \(tcpConfig.port)")
        } else {
            AppLogger.shared.log("🌐 [LaunchDaemon] TCP server disabled")
        }

        arguments.append("--debug")
        arguments.append("--log-layer-changes")

        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Built plist arguments: \(arguments.joined(separator: " "))")
        return arguments
    }

    // MARK: - Log Rotation Service

    /// Generate log rotation script that keeps logs under 10MB total
    private func generateLogRotationScript() -> String {
        """
        #!/bin/bash
        # KeyPath Log Rotation Script - Keep logs under 10MB total

        LOG_DIR="/var/log"
        MAX_SIZE_BYTES=$((5 * 1024 * 1024))  # 5MB per file (2 files = 10MB max)

        # Function to rotate a log file
        rotate_log() {
            local logfile="$1"
            if [[ -f "$logfile" ]]; then
                local size=$(stat -f%z "$logfile" 2>/dev/null || echo 0)

                if [[ $size -gt $MAX_SIZE_BYTES ]]; then
                    echo "$(date): Rotating $logfile (size: $size bytes)"

                    # Remove old backup if exists
                    [[ -f "$logfile.1" ]] && rm -f "$logfile.1"

                    # Move current to backup
                    mv "$logfile" "$logfile.1"

                    # Create new empty log file with correct permissions
                    touch "$logfile"
                    chmod 644 "$logfile"
                    chown root:wheel "$logfile" 2>/dev/null || true

                    echo "$(date): Log rotation completed for $logfile"
                fi
            fi
        }

        # Rotate kanata log
        rotate_log "$LOG_DIR/kanata.log"

        # Clean up any oversized KeyPath logs too
        for logfile in "$LOG_DIR"/keypath*.log; do
            [[ -f "$logfile" ]] && rotate_log "$logfile"
        done
        """
    }

    /// Generate plist for log rotation service (runs every hour)
    private func generateLogRotationPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.logRotationServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Self.logRotationScriptPath)</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Minute</key>
                <integer>0</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>/var/log/keypath-logrotate.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/keypath-logrotate.log</string>
            <key>UserName</key>
            <string>root</string>
        </dict>
        </plist>
        """
    }

    /// Check if log rotation service is already installed
    func isLogRotationServiceInstalled() -> Bool {
        let plistPath = "\(Self.systemLaunchDaemonsDir)/\(Self.logRotationServiceID).plist"
        let scriptPath = Self.logRotationScriptPath

        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        let scriptExists = FileManager.default.fileExists(atPath: scriptPath)

        AppLogger.shared.log("📝 [LaunchDaemon] Log rotation check: plist=\(plistExists), script=\(scriptExists)")

        return plistExists && scriptExists
    }

    /// Install log rotation service to keep logs under 10MB
    func installLogRotationService() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing log rotation service (keeps logs < 10MB)")

        let script = generateLogRotationScript()
        let plist = generateLogRotationPlist()

        let tempDir = NSTemporaryDirectory()
        let scriptTempPath = "\(tempDir)keypath-logrotate.sh"
        let plistTempPath = "\(tempDir)\(Self.logRotationServiceID).plist"

        do {
            // Write script and plist to temp files
            try script.write(toFile: scriptTempPath, atomically: true, encoding: .utf8)
            try plist.write(toFile: plistTempPath, atomically: true, encoding: .utf8)

            // Install both with admin privileges
            let scriptFinal = Self.logRotationScriptPath
            let plistFinal = "\(Self.systemLaunchDaemonsDir)/\(Self.logRotationServiceID).plist"

            let command = """
            mkdir -p /usr/local/bin && \
            cp '\(scriptTempPath)' '\(scriptFinal)' && \
            chmod 755 '\(scriptFinal)' && \
            chown root:wheel '\(scriptFinal)' && \
            cp '\(plistTempPath)' '\(plistFinal)' && \
            chmod 644 '\(plistFinal)' && \
            chown root:wheel '\(plistFinal)' && \
            launchctl load '\(plistFinal)'
            """

            // Use osascript approach like other admin operations
            let escapedCommand = escapeForAppleScript(command)
            let osascriptCommand = """
            do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to install log rotation service to keep logs under 10MB."
            """

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osascriptCommand]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            try task.run()
            task.waitUntilExit()

            let success = task.terminationStatus == 0

            // Clean up temp files
            try? FileManager.default.removeItem(atPath: scriptTempPath)
            try? FileManager.default.removeItem(atPath: plistTempPath)

            if success {
                AppLogger.shared.log("✅ [LaunchDaemon] Log rotation service installed successfully")
                // Also rotate the current huge log file immediately
                rotateCurrentLogs()
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install log rotation service")
            }

            return success

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error preparing log rotation files: \(error)")
            return false
        }
    }

    /// Immediately rotate current large log files
    private func rotateCurrentLogs() {
        AppLogger.shared.log("🔄 [LaunchDaemon] Immediately rotating current large log files")

        let command = """
        [[ -f /var/log/kanata.log ]] && \
        size=$(stat -f%z /var/log/kanata.log 2>/dev/null || echo 0) && \
        if [[ $size -gt 5242880 ]]; then \
            echo "Rotating kanata.log ($size bytes)"; \
            [[ -f /var/log/kanata.log.1 ]] && rm -f /var/log/kanata.log.1; \
            mv /var/log/kanata.log /var/log/kanata.log.1; \
            touch /var/log/kanata.log && chmod 644 /var/log/kanata.log; \
        fi
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Current log files rotated successfully")
            } else {
                AppLogger.shared.log("⚠️ [LaunchDaemon] Log rotation completed with warnings")
            }
        } catch {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Error during immediate log rotation: \(error)")
        }
    }
}

// MARK: - Supporting Types

/// Status information for LaunchDaemon services
struct LaunchDaemonStatus {
    let kanataServiceLoaded: Bool
    let vhidDaemonServiceLoaded: Bool
    let vhidManagerServiceLoaded: Bool
    let kanataServiceHealthy: Bool
    let vhidDaemonServiceHealthy: Bool
    let vhidManagerServiceHealthy: Bool

    /// True if all required services are loaded
    var allServicesLoaded: Bool {
        kanataServiceLoaded && vhidDaemonServiceLoaded && vhidManagerServiceLoaded
    }

    /// True if all required services are healthy (loaded and running properly)
    var allServicesHealthy: Bool {
        kanataServiceHealthy && vhidDaemonServiceHealthy && vhidManagerServiceHealthy
    }

    /// Description of current status for logging/debugging
    var description: String {
        """
        LaunchDaemon Status:
        - Kanata Service: loaded=\(kanataServiceLoaded) healthy=\(kanataServiceHealthy)
        - VHIDDevice Daemon: loaded=\(vhidDaemonServiceLoaded) healthy=\(vhidDaemonServiceHealthy)
        - VHIDDevice Manager: loaded=\(vhidManagerServiceLoaded) healthy=\(vhidManagerServiceHealthy)
        - All Services Loaded: \(allServicesLoaded)
        - All Services Healthy: \(allServicesHealthy)
        """
    }
}

// MARK: - Helper Extensions

private extension String {
    func firstMatchInt(pattern: String) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let match = rx.firstMatch(in: self, range: nsRange), match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return Int(self[range])
        } catch {
            return nil
        }
    }

    func firstMatchString(pattern: String) -> String? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let match = rx.firstMatch(in: self, range: nsRange), match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return String(self[range])
        } catch {
            return nil
        }
    }
}
