import Foundation

/// Manages LaunchDaemon installation and configuration for KeyPath services
/// Implements the production-ready LaunchDaemon architecture identified in the installer improvement analysis
class LaunchDaemonInstaller {
    // MARK: - Dependencies

    private let packageManager: PackageManager

    // MARK: - Constants

    private static let launchDaemonsPath = "/Library/LaunchDaemons"
    private static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    // Static paths for components that don't vary by system
    private static let kanataConfigPath = "/usr/local/etc/kanata/keypath.kbd"
    private static let vhidDaemonPath = "/Library/Application Support/org.pqrs/Karabiner-VirtualHIDDevice/bin/karabiner_vhid_daemon"
    private static let vhidManagerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    // MARK: - Initialization

    init(packageManager: PackageManager = PackageManager()) {
        self.packageManager = packageManager
    }

    // MARK: - Path Detection Methods

    /// Gets the detected Kanata binary path or returns fallback
    private func getKanataBinaryPath() -> String {
        let kanataInfo = packageManager.detectKanataInstallation()

        if kanataInfo.isInstalled, let path = kanataInfo.path {
            AppLogger.shared.log("✅ [LaunchDaemon] Using detected Kanata path: \(path)")
            return path
        } else {
            // Fallback to Intel Homebrew path for backward compatibility
            let fallbackPath = "/usr/local/bin/kanata"
            AppLogger.shared.log("⚠️ [LaunchDaemon] Kanata not detected, using fallback path: \(fallbackPath)")
            return fallbackPath
        }
    }

    // MARK: - Installation Methods

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

        return installPlist(content: plistContent, path: plistPath, serviceID: Self.vhidManagerServiceID)
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
                AppLogger.shared.log("⚠️ [LaunchDaemon] Service \(serviceID) may not have been loaded: \(output)")
                return true // Not an error if it wasn't loaded
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error unloading service \(serviceID): \(error)")
            return false
        }
    }

    /// Checks if a LaunchDaemon service is currently loaded
    func isServiceLoaded(serviceID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", serviceID]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let isLoaded = task.terminationStatus == 0
            AppLogger.shared.log("🔍 [LaunchDaemon] Service \(serviceID) loaded: \(isLoaded)")
            return isLoaded
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking service \(serviceID): \(error)")
            return false
        }
    }

    // MARK: - Plist Generation

    private func generateKanataPlist(binaryPath: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.kanataServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>--cfg</string>
                <string>\(Self.kanataConfigPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/kanata.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/kanata.log</string>
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
        return """
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
        return """
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

        // Ensure LaunchDaemons directory exists
        let launchDaemonsPath = Self.launchDaemonsPath
        if !FileManager.default.fileExists(atPath: launchDaemonsPath) {
            do {
                try FileManager.default.createDirectory(atPath: launchDaemonsPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to create LaunchDaemons directory: \(error)")
                return false
            }
        }

        // Write plist content to file
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)

            // Set proper ownership (root:wheel) and permissions
            let success = setProperPermissions(path: path)
            if success {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed plist: \(serviceID)")
            } else {
                AppLogger.shared.log("⚠️ [LaunchDaemon] Plist installed but permissions may be incorrect: \(serviceID)")
            }

            return true
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to write plist \(serviceID): \(error)")
            return false
        }
    }

    private func setProperPermissions(path: String) -> Bool {
        // Set ownership to root:wheel and permissions to 644
        let chownTask = Process()
        chownTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        chownTask.arguments = ["chown", "root:wheel", path]

        let chmodTask = Process()
        chmodTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        chmodTask.arguments = ["chmod", "644", path]

        do {
            try chownTask.run()
            chownTask.waitUntilExit()

            try chmodTask.run()
            chmodTask.waitUntilExit()

            let success = chownTask.terminationStatus == 0 && chmodTask.terminationStatus == 0
            if success {
                AppLogger.shared.log("✅ [LaunchDaemon] Set proper permissions for: \(path)")
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to set permissions for: \(path)")
            }

            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error setting permissions for \(path): \(error)")
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
        task.arguments = ["rm", "-f", path]

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

        return LaunchDaemonStatus(
            kanataServiceLoaded: kanataLoaded,
            vhidDaemonServiceLoaded: vhidDaemonLoaded,
            vhidManagerServiceLoaded: vhidManagerLoaded
        )
    }
}

// MARK: - Supporting Types

/// Status information for LaunchDaemon services
struct LaunchDaemonStatus {
    let kanataServiceLoaded: Bool
    let vhidDaemonServiceLoaded: Bool
    let vhidManagerServiceLoaded: Bool

    /// True if all required services are loaded
    var allServicesLoaded: Bool {
        kanataServiceLoaded && vhidDaemonServiceLoaded && vhidManagerServiceLoaded
    }

    /// Description of current status for logging/debugging
    var description: String {
        """
        LaunchDaemon Status:
        - Kanata Service: \(kanataServiceLoaded)
        - VHIDDevice Daemon: \(vhidDaemonServiceLoaded)
        - VHIDDevice Manager: \(vhidManagerServiceLoaded)
        - All Services Loaded: \(allServicesLoaded)
        """
    }
}
