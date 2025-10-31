import Foundation
import os
import SystemConfiguration

/// Implementation of privileged operations for KeyPath
///
/// This service runs as root and executes privileged operations requested by KeyPath.app.
/// All operations are logged to the system log for audit purposes.
class HelperService: NSObject, HelperProtocol {

    // MARK: - Constants

    /// Helper version (must match app version for compatibility)
    private static let version = "1.0.0"
    private let logger = Logger(subsystem: "com.keypath.helper", category: "service")

    // MARK: - Version Management

    func getVersion(reply: @escaping (String?, String?) -> Void) {
        NSLog("[KeyPathHelper] getVersion requested")
        logger.info("getVersion requested")
        reply(Self.version, nil)
    }

    // MARK: - LaunchDaemon Operations

    func installLaunchDaemon(plistPath: String, serviceID: String, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installLaunchDaemon requested: \(serviceID)")
        executePrivilegedOperation(
            name: "installLaunchDaemon",
            operation: {
                let fm = FileManager.default
                let dest = "/Library/LaunchDaemons/\(serviceID).plist"

                guard fm.fileExists(atPath: plistPath) else {
                    throw HelperError.invalidArgument("plist not found: \(plistPath)")
                }

                // Ensure destination dir exists
                try fm.createDirectory(atPath: "/Library/LaunchDaemons", withIntermediateDirectories: true)

                // Copy into place (overwrite if exists)
                if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
                try fm.copyItem(atPath: plistPath, toPath: dest)

                // Permissions and ownership
                _ = Self.run("/bin/chmod", ["644", dest])
                _ = Self.run("/usr/sbin/chown", ["root:wheel", dest])

                // Bootstrap (idempotent), then enable and kickstart
                _ = Self.run("/bin/launchctl", ["bootout", "system/\(serviceID)"]) // ignore failure
                let bs = Self.run("/bin/launchctl", ["bootstrap", "system", dest])
                if bs.status != 0 {
                    throw HelperError.operationFailed("launchctl bootstrap failed (status=\(bs.status)): \(bs.out)")
                }
                _ = Self.run("/bin/launchctl", ["enable", "system/\(serviceID)"])
                _ = Self.run("/bin/launchctl", ["kickstart", "-k", "system/\(serviceID)"])
            },
            reply: reply
        )
    }

    func installAllLaunchDaemonServices(kanataBinaryPath: String, kanataConfigPath: String, tcpPort: Int, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installAllLaunchDaemonServices requested (binary: \(kanataBinaryPath), cfg: \(kanataConfigPath), port: \(tcpPort))")
        executePrivilegedOperation(
            name: "installAllLaunchDaemonServices",
            operation: {
                try Self.installAllServices(kanataBinaryPath: kanataBinaryPath, kanataConfigPath: kanataConfigPath, tcpPort: tcpPort)
            },
            reply: reply
        )
    }

    func installAllLaunchDaemonServicesWithPreferences(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installAllLaunchDaemonServicesWithPreferences requested")
        executePrivilegedOperation(
            name: "installAllLaunchDaemonServicesWithPreferences",
            operation: {
                let appBundle = Self.appBundlePathFromHelper()
                let bundledKanata = (appBundle as NSString).appendingPathComponent("Contents/Library/KeyPath/kanata")
                let consoleHome = Self.consoleUserHomeDirectory() ?? "/var/root" // fallback
                let cfgPath = "\(consoleHome)/.config/keypath/keypath.kbd"
                let tcpPort = 37001
                try Self.installAllServices(kanataBinaryPath: bundledKanata, kanataConfigPath: cfgPath, tcpPort: tcpPort)
            },
            reply: reply
        )
    }

    func restartUnhealthyServices(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] restartUnhealthyServices requested")
        executePrivilegedOperation(
            name: "restartUnhealthyServices",
            operation: {
                // TODO: Implement service health checking and restart
                throw HelperError.notImplemented("restartUnhealthyServices")
            },
            reply: reply
        )
    }

    func regenerateServiceConfiguration(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] regenerateServiceConfiguration requested")
        executePrivilegedOperation(
            name: "regenerateServiceConfiguration",
            operation: {
                // TODO: Implement service configuration regeneration
                throw HelperError.notImplemented("regenerateServiceConfiguration")
            },
            reply: reply
        )
    }

    func installLogRotation(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installLogRotation requested")
        executePrivilegedOperation(
            name: "installLogRotation",
            operation: {
                let scriptPath = "/usr/local/bin/keypath-logrotate.sh"
                let plistPath = "/Library/LaunchDaemons/com.keypath.logrotate.plist"

                let script = Self.generateLogRotationScript()
                let plist = Self.generateLogRotationPlist(scriptPath: scriptPath)

                // Write temp files then install atomically
                let tmpDir = NSTemporaryDirectory()
                let tmpScript = (tmpDir as NSString).appendingPathComponent("keypath-logrotate.sh")
                let tmpPlist = (tmpDir as NSString).appendingPathComponent("com.keypath.logrotate.plist")
                try script.write(toFile: tmpScript, atomically: true, encoding: .utf8)
                try plist.write(toFile: tmpPlist, atomically: true, encoding: .utf8)

                _ = Self.run("/bin/mkdir", ["-p", "/usr/local/bin"])
                _ = Self.run("/bin/cp", [tmpScript, scriptPath])
                _ = Self.run("/bin/chmod", ["755", scriptPath])
                _ = Self.run("/usr/sbin/chown", ["root:wheel", scriptPath])

                _ = Self.run("/bin/cp", [tmpPlist, plistPath])
                _ = Self.run("/bin/chmod", ["644", plistPath])
                _ = Self.run("/usr/sbin/chown", ["root:wheel", plistPath])

                _ = Self.run("/bin/launchctl", ["bootout", "system/com.keypath.logrotate"]) // ignore failures
                let bs = Self.run("/bin/launchctl", ["bootstrap", "system", plistPath])
                if bs.status != 0 {
                    throw HelperError.operationFailed("bootstrap logrotate failed (status=\(bs.status)): \(bs.out)")
                }
            },
            reply: reply
        )
    }

    func repairVHIDDaemonServices(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] repairVHIDDaemonServices requested")
        executePrivilegedOperation(
            name: "repairVHIDDaemonServices",
            operation: {
                // TODO: Implement VHID daemon repair
                throw HelperError.notImplemented("repairVHIDDaemonServices")
            },
            reply: reply
        )
    }

    func installLaunchDaemonServicesWithoutLoading(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installLaunchDaemonServicesWithoutLoading requested")
        executePrivilegedOperation(
            name: "installLaunchDaemonServicesWithoutLoading",
            operation: {
                // TODO: Implement LaunchDaemon installation without loading
                throw HelperError.notImplemented("installLaunchDaemonServicesWithoutLoading")
            },
            reply: reply
        )
    }

    // MARK: - VirtualHID Operations

    func activateVirtualHIDManager(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] activateVirtualHIDManager requested")
        executePrivilegedOperation(
            name: "activateVirtualHIDManager",
            operation: {
                // TODO: Implement VHID Manager activation
                throw HelperError.notImplemented("activateVirtualHIDManager")
            },
            reply: reply
        )
    }

    func uninstallVirtualHIDDrivers(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] uninstallVirtualHIDDrivers requested")
        executePrivilegedOperation(
            name: "uninstallVirtualHIDDrivers",
            operation: {
                // TODO: Implement VHID driver uninstallation
                throw HelperError.notImplemented("uninstallVirtualHIDDrivers")
            },
            reply: reply
        )
    }

    func installVirtualHIDDriver(version: String, downloadURL: String, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installVirtualHIDDriver requested: v\(version) from \(downloadURL)")
        executePrivilegedOperation(
            name: "installVirtualHIDDriver",
            operation: {
                // TODO: Implement VHID driver installation
                throw HelperError.notImplemented("installVirtualHIDDriver")
            },
            reply: reply
        )
    }

    func downloadAndInstallCorrectVHIDDriver(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] downloadAndInstallCorrectVHIDDriver requested")
        executePrivilegedOperation(
            name: "downloadAndInstallCorrectVHIDDriver",
            operation: {
                // TODO: Implement auto-detection and installation of correct VHID driver
                throw HelperError.notImplemented("downloadAndInstallCorrectVHIDDriver")
            },
            reply: reply
        )
    }

    // MARK: - Process Management

    func terminateProcess(_ pid: Int32, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] terminateProcess(\(pid)) requested")
        executePrivilegedOperation(
            name: "terminateProcess",
            operation: {
                // Implement process termination
                let result = kill(pid, SIGTERM)
                if result != 0 {
                    throw HelperError.operationFailed("Failed to terminate process \(pid): \(String(cString: strerror(errno)))")
                }
                NSLog("[KeyPathHelper] Successfully terminated process \(pid)")
            },
            reply: reply
        )
    }

    func killAllKanataProcesses(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] killAllKanataProcesses requested")
        executePrivilegedOperation(
            name: "killAllKanataProcesses",
            operation: {
                // TODO: Implement killing all Kanata processes
                throw HelperError.notImplemented("killAllKanataProcesses")
            },
            reply: reply
        )
    }

    func restartKarabinerDaemon(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] restartKarabinerDaemon requested")
        executePrivilegedOperation(
            name: "restartKarabinerDaemon",
            operation: {
                // TODO: Implement Karabiner daemon restart
                throw HelperError.notImplemented("restartKarabinerDaemon")
            },
            reply: reply
        )
    }

    // Note: executeCommand removed for security. Use explicit operations only.

    // MARK: - Helper Methods

    /// Execute a privileged operation with error handling
    /// - Parameters:
    ///   - name: Operation name for logging
    ///   - operation: The operation to execute (can throw)
    ///   - reply: Completion handler to call with result
    private func executePrivilegedOperation(
        name: String,
        operation: () throws -> Void,
        reply: @escaping (Bool, String?) -> Void
    ) {
        do {
            try operation()
            NSLog("[KeyPathHelper] ✅ \(name) succeeded")
            logger.info("\(name, privacy: .public) succeeded")
            reply(true, nil)
        } catch let error as HelperError {
            NSLog("[KeyPathHelper] ❌ \(name) failed: \(error.localizedDescription)")
            logger.error("\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        } catch {
            NSLog("[KeyPathHelper] ❌ \(name) failed: \(error.localizedDescription)")
            logger.error("\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during privileged operations
enum HelperError: Error, LocalizedError {
    case notImplemented(String)
    case operationFailed(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let operation):
            return "Operation not yet implemented: \(operation)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        case .invalidArgument(let reason):
            return "Invalid argument: \(reason)"
        }
    }
}

// MARK: - Helpers
extension HelperService {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = args
        let outPipe = Pipe(); p.standardOutput = outPipe; p.standardError = outPipe
        do { try p.run() } catch { return (127, "run failed: \(error)") }
        p.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, s)
    }

    static func generateLogRotationScript() -> String {
        return """
        #!/bin/bash
        set -euo pipefail
        LOG_DIR="/Library/Logs/KeyPath"
        mkdir -p "$LOG_DIR"
        MAX_SIZE_BYTES=$((10 * 1024 * 1024))

        rotate_log() {
            local logfile="$1"
            if [[ -f "$logfile" ]]; then
                local size=$(stat -f%z "$logfile" 2>/dev/null || echo 0)
                if [[ $size -gt $MAX_SIZE_BYTES ]]; then
                    echo "$(date): Rotating $logfile (size: $size bytes)"
                    [[ -f "$logfile.1" ]] && rm -f "$logfile.1"
                    mv "$logfile" "$logfile.1"
                    touch "$logfile" && chmod 644 "$logfile" && chown root:wheel "$logfile" 2>/dev/null || true
                    echo "$(date): Log rotation completed for $logfile"
                fi
            fi
        }

        rotate_log "$LOG_DIR/kanata.log"
        for logfile in "$LOG_DIR"/keypath*.log; do
            [[ -f "$logfile" ]] && rotate_log "$logfile"
        done
        """
    }

    static func generateLogRotationPlist(scriptPath: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.keypath.logrotate</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(scriptPath)</string>
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

    // MARK: - LaunchDaemon service helpers
    private static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"
    private static let vhidDaemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private static let vhidManagerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    private static func appBundlePathFromHelper() -> String {
        let exe = CommandLine.arguments.first ?? "/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper"
        if let range = exe.range(of: "/Contents/Library/HelperTools/KeyPathHelper") {
            return String(exe[..<range.lowerBound])
        }
        // Fallback to /Applications
        return "/Applications/KeyPath.app"
    }

    private static func consoleUserHomeDirectory() -> String? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        if let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String? {
            return "/Users/\(name)"
        }
        return nil
    }

    private static func kanataArguments(binaryPath: String, cfgPath: String, tcpPort: Int) -> [String] {
        return [binaryPath, "--cfg", cfgPath, "--port", String(tcpPort), "--debug", "--log-layer-changes"]
    }

    private static func generateKanataPlist(binaryPath: String, cfgPath: String, tcpPort: Int) -> String {
        let args = kanataArguments(binaryPath: binaryPath, cfgPath: cfgPath, tcpPort: tcpPort)
        let argsXML = args.map { "                <string>\($0)</string>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(kanataServiceID)</string>
            <key>ProgramArguments</key>
            <array>
            \(argsXML)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
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
            <key>AssociatedBundleIdentifiers</key>
            <array>
                <string>com.keypath.KeyPath</string>
            </array>
        </dict>
        </plist>
        """
    }

    private static func generateVHIDDaemonPlist() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(vhidDaemonServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(vhidDaemonPath)</string>
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

    private static func generateVHIDManagerPlist() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(vhidManagerServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(vhidManagerPath)</string>
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

    static func installAllServices(kanataBinaryPath: String, kanataConfigPath: String, tcpPort: Int) throws {
        // Write temp plists
        let tmp = NSTemporaryDirectory()
        let kanataPlist = generateKanataPlist(binaryPath: kanataBinaryPath, cfgPath: kanataConfigPath, tcpPort: tcpPort)
        let vhidDPlist = generateVHIDDaemonPlist()
        let vhidMPlist = generateVHIDManagerPlist()

        let tKanata = (tmp as NSString).appendingPathComponent("\(kanataServiceID).plist")
        let tVhidD = (tmp as NSString).appendingPathComponent("\(vhidDaemonServiceID).plist")
        let tVhidM = (tmp as NSString).appendingPathComponent("\(vhidManagerServiceID).plist")
        try kanataPlist.write(toFile: tKanata, atomically: true, encoding: .utf8)
        try vhidDPlist.write(toFile: tVhidD, atomically: true, encoding: .utf8)
        try vhidMPlist.write(toFile: tVhidM, atomically: true, encoding: .utf8)

        let dstDir = "/Library/LaunchDaemons"
        _ = run("/bin/mkdir", ["-p", dstDir])

        let dKanata = (dstDir as NSString).appendingPathComponent("\(kanataServiceID).plist")
        let dVhidD = (dstDir as NSString).appendingPathComponent("\(vhidDaemonServiceID).plist")
        let dVhidM = (dstDir as NSString).appendingPathComponent("\(vhidManagerServiceID).plist")

        for (src, dst) in [(tKanata, dKanata), (tVhidD, dVhidD), (tVhidM, dVhidM)] {
            _ = run("/bin/rm", ["-f", dst])
            let cp = run("/bin/cp", [src, dst])
            if cp.status != 0 { throw HelperError.operationFailed("copy failed for \(dst): \(cp.out)") }
            _ = run("/usr/sbin/chown", ["root:wheel", dst])
            _ = run("/bin/chmod", ["644", dst])
        }

        // Register in dependency order
        _ = run("/bin/launchctl", ["bootout", "system/\(vhidDaemonServiceID)"]) // ignore
        _ = run("/bin/launchctl", ["bootout", "system/\(vhidManagerServiceID)"]) // ignore
        _ = run("/bin/launchctl", ["bootout", "system/\(kanataServiceID)"]) // ignore

        let bs1 = run("/bin/launchctl", ["bootstrap", "system", dVhidD])
        if bs1.status != 0 { throw HelperError.operationFailed("bootstrap vhid-daemon failed: \(bs1.out)") }
        let bs2 = run("/bin/launchctl", ["bootstrap", "system", dVhidM])
        if bs2.status != 0 { throw HelperError.operationFailed("bootstrap vhid-manager failed: \(bs2.out)") }
        let bs3 = run("/bin/launchctl", ["bootstrap", "system", dKanata])
        if bs3.status != 0 { throw HelperError.operationFailed("bootstrap kanata failed: \(bs3.out)") }

        _ = run("/bin/launchctl", ["enable", "system/\(vhidDaemonServiceID)"])
        _ = run("/bin/launchctl", ["enable", "system/\(vhidManagerServiceID)"])
        _ = run("/bin/launchctl", ["enable", "system/\(kanataServiceID)"])

        _ = run("/bin/launchctl", ["kickstart", "-k", "system/\(vhidDaemonServiceID)"])
        _ = run("/bin/launchctl", ["kickstart", "-k", "system/\(vhidManagerServiceID)"])
        _ = run("/bin/launchctl", ["kickstart", "-k", "system/\(kanataServiceID)"])
    }
}
