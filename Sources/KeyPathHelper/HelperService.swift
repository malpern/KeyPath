import Darwin
import Foundation
import KeyPathCore
import os
import SystemConfiguration

/// Implementation of privileged operations for KeyPath
///
/// This service runs as root and executes privileged operations requested by KeyPath.app.
/// All operations are logged to the system log for audit purposes.
class HelperService: NSObject, HelperProtocol {
    // MARK: - Constants

    /// Helper version (must match app version for compatibility)
    private static let version = "1.1.0"
    private static let vhidRootOnlyDirectory = "/Library/Application Support/org.pqrs/tmp/rootonly"
    private static let kanataOutputBridgeBaseDirectory = KeyPathConstants.OutputBridge.runDirectory
    private static let kanataOutputBridgeDirectory = KeyPathConstants.OutputBridge.socketDirectory
    private static let kanataOutputBridgeSessionDirectory = KeyPathConstants.OutputBridge.sessionDirectory
    private static let outputBridgeServiceID = KeyPathConstants.Bundle.outputBridgeID
    private let logger = Logger(subsystem: "com.keypath.helper", category: "service")

    // MARK: - Version Management

    func getVersion(reply: @escaping (String?, String?) -> Void) {
        NSLog("[KeyPathHelper] getVersion requested")
        logger.info("getVersion requested")

        // Log thread/queue info
        let threadName = Thread.current.isMainThread ? "main" : "background"
        NSLog("[KeyPathHelper] getVersion executing on \(threadName) thread")
        logger.info("getVersion executing on \(threadName) thread")

        // Call reply and log it
        NSLog("[KeyPathHelper] Calling reply with version: \(Self.version)")
        logger.info("Calling reply with version: \(Self.version)")
        reply(Self.version, nil)
        NSLog("[KeyPathHelper] Reply callback completed")
        logger.info("Reply callback completed")
    }

    func recoverRequiredRuntimeServices(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] recoverRequiredRuntimeServices requested")
        executePrivilegedOperation(
            name: "recoverRequiredRuntimeServices",
            operation: {
                // Assess VirtualHID health and restart as needed; Kanata is SMAppService-managed
                let services = [Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
                var needsInstall = false
                var toRestart: [String] = []

                for id in services {
                    if !Self.isServiceLoaded(id) {
                        needsInstall = true
                        continue
                    }
                    if !Self.isServiceHealthy(id) {
                        toRestart.append(id)
                    }
                }

                if needsInstall {
                    NSLog("[KeyPathHelper] VirtualHID services missing - reinstalling via helper")
                    try Self.installOrRepairVHIDServices()
                    return
                }

                // Services are loaded but unhealthy - just restart them
                for id in toRestart {
                    _ = Self.run("/bin/launchctl", ["kickstart", "-k", "system/\(id)"])
                }
            },
            reply: reply
        )
    }

    func regenerateServiceConfiguration(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] regenerateServiceConfiguration requested")
        executePrivilegedOperation(
            name: "regenerateServiceConfiguration",
            operation: {
                throw HelperError.operationFailed(
                    "Kanata configuration is managed by SMAppService. Use the main app to refresh configuration."
                )
            },
            reply: reply
        )
    }

    func installNewsyslogConfig(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installNewsyslogConfig requested")
        executePrivilegedOperation(
            name: "installNewsyslogConfig",
            operation: {
                let configPath = "/etc/newsyslog.d/com.keypath.conf"
                let config = Self.generateNewsyslogConfig()

                // Ensure directory exists
                _ = Self.run("/bin/mkdir", ["-p", "/etc/newsyslog.d"])

                // Write config file
                try config.write(toFile: configPath, atomically: true, encoding: .utf8)
                _ = Self.run("/bin/chmod", ["644", configPath])
                _ = Self.run("/usr/sbin/chown", ["root:wheel", configPath])

                // Legacy cleanup: remove old custom log rotation daemon if present
                _ = Self.run("/bin/launchctl", ["bootout", "system/com.keypath.logrotate"])
                if FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.keypath.logrotate.plist") {
                    _ = Self.run("/bin/rm", ["-f", "/Library/LaunchDaemons/com.keypath.logrotate.plist"])
                }
                if FileManager.default.fileExists(atPath: "/usr/local/bin/keypath-logrotate.sh") {
                    _ = Self.run("/bin/rm", ["-f", "/usr/local/bin/keypath-logrotate.sh"])
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
                try Self.installOrRepairVHIDServices()
            },
            reply: reply
        )
    }

    func installRequiredRuntimeServices(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installRequiredRuntimeServices requested")
        executePrivilegedOperation(
            name: "installRequiredRuntimeServices",
            operation: {
                try Self.installOrRepairVHIDServices()
                try Self.ensureOutputBridgeCompanionInstalled()
                try Self.activateOutputBridgeCompanion()
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
                let r = Self.run(Self.vhidManagerPath, ["activate"])
                if r.status != 0 {
                    throw HelperError.operationFailed("VHID Manager activation failed: \(r.out)")
                }
                // Give daemon a moment and consider success
                usleep(500_000)
            },
            reply: reply
        )
    }

    func uninstallVirtualHIDDrivers(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] uninstallVirtualHIDDrivers requested")
        executePrivilegedOperation(
            name: "uninstallVirtualHIDDrivers",
            operation: {
                // Attempt to uninstall via systemextensionsctl; ignore if not installed
                _ = Self.run("/usr/bin/systemextensionsctl", ["list"]) // warm up (informational)
                let u = Self.run(
                    "/usr/bin/systemextensionsctl",
                    [
                        "uninstall", Self.karabinerTeamID, Self.karabinerDriverBundleID
                    ]
                )
                if u.status != 0 {
                    // Not fatal; this can fail if not installed or requires user approval
                    NSLog(
                        "[KeyPathHelper] uninstallVirtualHIDDrivers non-zero status: %d: %@", u.status, u.out
                    )
                }
                usleep(500_000)
            },
            reply: reply
        )
    }

    func installVirtualHIDDriver(
        version: String, downloadURL: String, reply: @escaping (Bool, String?) -> Void
    ) {
        NSLog("[KeyPathHelper] installVirtualHIDDriver requested: v\(version) from \(downloadURL)")
        executePrivilegedOperation(
            name: "installVirtualHIDDriver",
            operation: {
                let tmp = NSTemporaryDirectory()
                let pkg = (tmp as NSString).appendingPathComponent("Karabiner-VirtualHID-\(version).pkg")
                // Download with curl to avoid async URLSession in XPC sync path
                let d = Self.run("/usr/bin/curl", ["-L", "-f", "-o", pkg, downloadURL])
                if d.status != 0 { throw HelperError.operationFailed("Download failed: \(d.out)") }
                let i = Self.run("/usr/sbin/installer", ["-pkg", pkg, "-target", "/"])
                // Clean up regardless
                _ = try? FileManager.default.removeItem(atPath: pkg)
                if i.status != 0 { throw HelperError.operationFailed("Installer failed: \(i.out)") }
                // Activate after install
                let a = Self.run(Self.vhidManagerPath, ["activate"])
                if a.status != 0 {
                    NSLog("[KeyPathHelper] Warning: activate returned %d: %@", a.status, a.out)
                }
            },
            reply: reply
        )
    }

    func downloadAndInstallCorrectVHIDDriver(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] downloadAndInstallCorrectVHIDDriver requested (deprecated - use installBundledVHIDDriver)")
        executePrivilegedOperation(
            name: "downloadAndInstallCorrectVHIDDriver",
            operation: {
                let version = Self.requiredVHIDVersion
                let url =
                    "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v\(version)/Karabiner-DriverKit-VirtualHIDDevice-\(version).pkg"
                let tmp = NSTemporaryDirectory()
                let pkg = (tmp as NSString).appendingPathComponent("Karabiner-VirtualHID-\(version).pkg")
                let d = Self.run("/usr/bin/curl", ["-L", "-f", "-o", pkg, url])
                if d.status != 0 { throw HelperError.operationFailed("Download failed: \(d.out)") }
                let i = Self.run("/usr/sbin/installer", ["-pkg", pkg, "-target", "/"])
                _ = try? FileManager.default.removeItem(atPath: pkg)
                if i.status != 0 { throw HelperError.operationFailed("Installer failed: \(i.out)") }
                let a = Self.run(Self.vhidManagerPath, ["activate"])
                if a.status != 0 {
                    NSLog("[KeyPathHelper] Warning: activate returned %d: %@", a.status, a.out)
                }
            },
            reply: reply
        )
    }

    func getKanataOutputBridgeStatus(
        reply: @escaping (String?, String?) -> Void
    ) {
        NSLog("[KeyPathHelper] getKanataOutputBridgeStatus requested")
        logger.info("getKanataOutputBridgeStatus requested")

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: Self.vhidRootOnlyDirectory)
            let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.intValue ?? -1
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            let isRootOwned = ownerID == 0
            let isRootOnly = permissions & 0o077 == 0
            let companionPlistPath = "/Library/LaunchDaemons/\(Self.outputBridgeServiceID).plist"
            let companionInstalled = FileManager.default.fileExists(atPath: companionPlistPath)
            let launchctl = Self.run("/bin/launchctl", ["print", "system/\(Self.outputBridgeServiceID)"])
            let companionHealthy = launchctl.status == 0
            let detail: String? = {
                if companionHealthy {
                    return "privileged output companion is installed and launchctl can inspect system/\(Self.outputBridgeServiceID)"
                }
                if companionInstalled {
                    let trimmed = launchctl.out.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty
                        ? "privileged output companion plist is installed but launchctl could not inspect system/\(Self.outputBridgeServiceID)"
                        : "privileged output companion is installed but unhealthy: \(trimmed)"
                }
                return "privileged output companion is not installed"
            }()
            let status = KanataOutputBridgeStatus(
                available: companionHealthy,
                companionRunning: companionHealthy,
                requiresPrivilegedBridge: isRootOwned && isRootOnly,
                socketDirectory: Self.kanataOutputBridgeDirectory,
                detail: detail
            )
            let payload = try JSONEncoder().encode(status)
            reply(String(decoding: payload, as: UTF8.self), nil)
        } catch {
            let status = KanataOutputBridgeStatus(
                available: false,
                companionRunning: false,
                requiresPrivilegedBridge: false,
                socketDirectory: Self.kanataOutputBridgeDirectory,
                detail: "failed to inspect privileged output bridge requirements: \(error.localizedDescription)"
            )
            if let payload = try? JSONEncoder().encode(status) {
                reply(String(decoding: payload, as: UTF8.self), nil)
            } else {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func prepareKanataOutputBridgeSession(
        hostPID: Int32,
        reply: @escaping (String?, String?) -> Void
    ) {
        NSLog("[KeyPathHelper] prepareKanataOutputBridgeSession requested for pid=%d", hostPID)
        logger.info("prepareKanataOutputBridgeSession requested for pid=\(hostPID)")

        guard hostPID > 0 else {
            reply(nil, "invalid host pid")
            return
        }

        do {
            try Self.ensureKanataOutputBridgeDirectory()
            try Self.retireDeadOutputBridgeSessions()
            try Self.retireOutputBridgeSessions(forHostPID: hostPID)
            try Self.ensureOutputBridgeCompanionInstalled()
            let sessionID = UUID().uuidString.lowercased()
            let socketName = "k-\(sessionID.replacingOccurrences(of: "-", with: "").prefix(12)).sock"
            let socketPath = (Self.kanataOutputBridgeDirectory as NSString)
                .appendingPathComponent(socketName)

            if FileManager.default.fileExists(atPath: socketPath) {
                try FileManager.default.removeItem(atPath: socketPath)
            }

            let hostUID = try Self.userID(for: hostPID)
            let hostGID = try Self.groupID(for: hostPID)

            let session = KanataOutputBridgeSession(
                sessionID: sessionID,
                socketPath: socketPath,
                socketDirectory: Self.kanataOutputBridgeDirectory,
                hostPID: hostPID,
                hostUID: hostUID,
                hostGID: hostGID
            )
            try Self.writePreparedOutputBridgeSession(session)
            NSLog(
                "[KeyPathHelper] prepared output bridge session %@ socket=%@ hostPID=%d uid=%u gid=%u",
                session.sessionID,
                session.socketPath,
                session.hostPID,
                session.hostUID,
                session.hostGID
            )
            logger.info(
                "prepared output bridge session \(session.sessionID) socket=\(session.socketPath) hostPID=\(session.hostPID) uid=\(session.hostUID) gid=\(session.hostGID)"
            )

            let payload = try JSONEncoder().encode(session)
            reply(String(decoding: payload, as: UTF8.self), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func activateKanataOutputBridgeSession(
        sessionID: String,
        reply: @escaping (Bool, String?) -> Void
    ) {
        NSLog("[KeyPathHelper] activateKanataOutputBridgeSession requested: %@", sessionID)
        logger.info("activateKanataOutputBridgeSession requested: \(sessionID)")

        do {
            try Self.ensureOutputBridgeCompanionInstalled()
            try Self.ensureKanataOutputBridgeDirectory()
            let session = try Self.loadPreparedOutputBridgeSession(sessionID: sessionID)
            do {
                try Self.activatePreparedOutputBridgeSession(session)
            } catch {
                NSLog(
                    "[KeyPathHelper] output bridge activation failed for %@, attempting recovery: %@",
                    sessionID,
                    error.localizedDescription
                )
                logger.error(
                    "output bridge activation failed for \(sessionID), attempting recovery: \(error.localizedDescription)"
                )
                try Self.recoverOutputBridgeCompanion(for: session)
            }
            NSLog(
                "[KeyPathHelper] activated output bridge session %@ socket=%@",
                sessionID,
                session.socketPath
            )
            logger.info("activated output bridge session \(sessionID) socket=\(session.socketPath)")
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func restartKanataOutputBridgeCompanion(
        reply: @escaping (Bool, String?) -> Void
    ) {
        NSLog("[KeyPathHelper] restartKanataOutputBridgeCompanion requested")
        logger.info("restartKanataOutputBridgeCompanion requested")
        executePrivilegedOperation(
            name: "restartKanataOutputBridgeCompanion",
            operation: {
                if Self.isServiceLoaded(Self.outputBridgeServiceID) {
                    try Self.activateOutputBridgeCompanion()
                } else {
                    try Self.ensureOutputBridgeCompanionInstalled()
                    try Self.activateOutputBridgeCompanion()
                }
            },
            reply: reply
        )
    }

    func installBundledVHIDDriver(pkgPath: String, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installBundledVHIDDriver requested: %@", pkgPath)
        executePrivilegedOperation(
            name: "installBundledVHIDDriver",
            operation: {
                // Validate the pkg path exists and is within expected app bundle location
                guard FileManager.default.fileExists(atPath: pkgPath) else {
                    throw HelperError.operationFailed("Bundled VHID driver pkg not found at: \(pkgPath)")
                }
                // Security: Only allow .pkg files from KeyPath.app bundle
                guard pkgPath.contains("/KeyPath.app/"), pkgPath.hasSuffix(".pkg") else {
                    throw HelperError.operationFailed("Invalid pkg path - must be within KeyPath.app bundle")
                }
                NSLog("[KeyPathHelper] Installing VHID driver from bundled pkg: %@", pkgPath)
                let i = Self.run("/usr/sbin/installer", ["-pkg", pkgPath, "-target", "/"])
                if i.status != 0 { throw HelperError.operationFailed("Installer failed: \(i.out)") }
                // Activate after install
                let a = Self.run(Self.vhidManagerPath, ["activate"])
                if a.status != 0 {
                    NSLog("[KeyPathHelper] Warning: activate returned %d: %@", a.status, a.out)
                }
                NSLog("[KeyPathHelper] VHID driver installed successfully from bundled pkg")
            },
            reply: reply
        )
    }

    /// Shared implementation for installing/repairing VHID services
    private static func installOrRepairVHIDServices() throws {
        try ensureConsoleUserConfigArtifacts()

        // Boot out existing jobs (ignore failures)
        _ = run("/bin/launchctl", ["bootout", "system/\(vhidDaemonServiceID)"])
        _ = run("/bin/launchctl", ["bootout", "system/\(vhidManagerServiceID)"])

        // Generate plists
        let vhidDPlist = generateVHIDDaemonPlist()
        let vhidMPlist = generateVHIDManagerPlist()

        let tmp = NSTemporaryDirectory()
        let tVhidD = (tmp as NSString).appendingPathComponent("\(vhidDaemonServiceID).plist")
        let tVhidM = (tmp as NSString).appendingPathComponent("\(vhidManagerServiceID).plist")
        try vhidDPlist.write(toFile: tVhidD, atomically: true, encoding: .utf8)
        try vhidMPlist.write(toFile: tVhidM, atomically: true, encoding: .utf8)

        // Install to LaunchDaemons
        let dstDir = "/Library/LaunchDaemons"
        _ = run("/bin/mkdir", ["-p", dstDir])
        let dVhidD = (dstDir as NSString).appendingPathComponent("\(vhidDaemonServiceID).plist")
        let dVhidM = (dstDir as NSString).appendingPathComponent("\(vhidManagerServiceID).plist")
        _ = run("/bin/cp", [tVhidD, dVhidD])
        _ = run("/bin/cp", [tVhidM, dVhidM])
        _ = run("/usr/sbin/chown", ["root:wheel", dVhidD])
        _ = run("/usr/sbin/chown", ["root:wheel", dVhidM])
        _ = run("/bin/chmod", ["644", dVhidD])
        _ = run("/bin/chmod", ["644", dVhidM])

        // Bootstrap and kickstart
        let bs1 = run("/bin/launchctl", ["bootstrap", "system", dVhidD])
        if bs1.status != 0 {
            throw HelperError.operationFailed("bootstrap vhid-daemon failed: \(bs1.out)")
        }
        let bs2 = run("/bin/launchctl", ["bootstrap", "system", dVhidM])
        if bs2.status != 0 {
            throw HelperError.operationFailed("bootstrap vhid-manager failed: \(bs2.out)")
        }
        _ = run("/bin/launchctl", ["enable", "system/\(vhidDaemonServiceID)"])
        _ = run("/bin/launchctl", ["enable", "system/\(vhidManagerServiceID)"])
        _ = run("/bin/launchctl", ["kickstart", "-k", "system/\(vhidDaemonServiceID)"])
        _ = run("/bin/launchctl", ["kickstart", "-k", "system/\(vhidManagerServiceID)"])
    }

    private static func ensureKanataOutputBridgeDirectory() throws {
        guard FileManager.default.fileExists(atPath: vhidRootOnlyDirectory) else {
            throw HelperError.operationFailed("vhid root-only directory not found at \(vhidRootOnlyDirectory)")
        }

        if !FileManager.default.fileExists(atPath: kanataOutputBridgeBaseDirectory) {
            try FileManager.default.createDirectory(
                atPath: kanataOutputBridgeBaseDirectory,
                withIntermediateDirectories: true
            )
        }

        if !FileManager.default.fileExists(atPath: kanataOutputBridgeDirectory) {
            try FileManager.default.createDirectory(
                atPath: kanataOutputBridgeDirectory,
                withIntermediateDirectories: false
            )
        }
        if !FileManager.default.fileExists(atPath: kanataOutputBridgeSessionDirectory) {
            try FileManager.default.createDirectory(
                atPath: kanataOutputBridgeSessionDirectory,
                withIntermediateDirectories: false
            )
        }

        _ = run("/usr/sbin/chown", ["root:wheel", kanataOutputBridgeBaseDirectory])
        _ = run("/bin/chmod", ["755", kanataOutputBridgeBaseDirectory])
        _ = run("/usr/sbin/chown", ["root:wheel", kanataOutputBridgeDirectory])
        _ = run("/bin/chmod", ["755", kanataOutputBridgeDirectory])
        _ = run("/usr/sbin/chown", ["root:wheel", kanataOutputBridgeSessionDirectory])
        _ = run("/bin/chmod", ["755", kanataOutputBridgeSessionDirectory])

        let attributes = try FileManager.default.attributesOfItem(atPath: kanataOutputBridgeDirectory)
        let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.intValue ?? -1
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard ownerID == 0, permissions == 0o755 else {
            throw HelperError.operationFailed(
                "output bridge directory is not host-connectable at \(kanataOutputBridgeDirectory)"
            )
        }
    }

    private static func retireOutputBridgeSessions(forHostPID hostPID: Int32) throws {
        let matchingSessionIDs = try loadPreparedOutputBridgeSessions()
            .filter { $0.hostPID == hostPID }
            .map(\.sessionID)

        for sessionID in matchingSessionIDs {
            retireOutputBridgeSession(sessionID: sessionID)
        }
    }

    private static func retireDeadOutputBridgeSessions() throws {
        let deadSessionIDs = try loadPreparedOutputBridgeSessions()
            .filter { !isProcessAlive($0.hostPID) }
            .map(\.sessionID)

        for sessionID in deadSessionIDs {
            retireOutputBridgeSession(sessionID: sessionID)
        }
    }

    private static func retireOutputBridgeSession(sessionID: String) {
        let sessionPath = preparedOutputBridgeSessionPath(sessionID: sessionID)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)),
           let session = try? JSONDecoder().decode(PreparedOutputBridgeSession.self, from: data),
           FileManager.default.fileExists(atPath: session.socketPath)
        {
            try? FileManager.default.removeItem(atPath: session.socketPath)
        }
        try? FileManager.default.removeItem(atPath: sessionPath)
    }

    private static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func loadPreparedOutputBridgeSessions() throws -> [PreparedOutputBridgeSession] {
        let directory = URL(fileURLWithPath: kanataOutputBridgeSessionDirectory, isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.compactMap { file in
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let session = try? JSONDecoder().decode(PreparedOutputBridgeSession.self, from: data)
            else {
                return nil
            }
            return session
        }
    }

    private static func preparedOutputBridgeSessionPath(sessionID: String) -> String {
        (kanataOutputBridgeSessionDirectory as NSString).appendingPathComponent("\(sessionID).json")
    }

    private static func writePreparedOutputBridgeSession(_ session: KanataOutputBridgeSession) throws {
        let prepared = PreparedOutputBridgeSession(
            sessionID: session.sessionID,
            socketPath: session.socketPath,
            hostPID: session.hostPID,
            hostUID: session.hostUID,
            hostGID: session.hostGID
        )
        let data = try JSONEncoder().encode(prepared)
        try data.write(
            to: URL(fileURLWithPath: preparedOutputBridgeSessionPath(sessionID: session.sessionID)),
            options: Data.WritingOptions.atomic
        )
    }

    private static func ensurePreparedOutputBridgeSessionExists(sessionID: String) throws {
        _ = try loadPreparedOutputBridgeSession(sessionID: sessionID)
    }

    private static func loadPreparedOutputBridgeSession(sessionID: String) throws -> PreparedOutputBridgeSession {
        let path = preparedOutputBridgeSessionPath(sessionID: sessionID)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let session = try? JSONDecoder().decode(PreparedOutputBridgeSession.self, from: data)
        else {
            throw HelperError.operationFailed("unknown output bridge session: \(sessionID)")
        }
        return session
    }

    private static func ensureOutputBridgeCompanionInstalled() throws {
        let appBundle = appBundlePathFromHelper()
        let bundledPlist = (appBundle as NSString).appendingPathComponent(
            "Contents/Library/LaunchDaemons/\(outputBridgeServiceID).plist"
        )
        guard FileManager.default.fileExists(atPath: bundledPlist) else {
            throw HelperError.operationFailed("bundled output bridge plist not found at \(bundledPlist)")
        }
        let destination = "/Library/LaunchDaemons/\(outputBridgeServiceID).plist"
        _ = run("/bin/rm", ["-f", destination])
        _ = run("/bin/cp", [bundledPlist, destination])
        _ = run("/usr/sbin/chown", ["root:wheel", destination])
        _ = run("/bin/chmod", ["644", destination])
        _ = run("/bin/launchctl", ["bootout", "system/\(outputBridgeServiceID)"])
        try bootstrapOutputBridgeCompanion(destination: destination)
        _ = run("/bin/launchctl", ["enable", "system/\(outputBridgeServiceID)"])
    }

    private static func userID(for pid: Int32) throws -> UInt32 {
        let result = run("/bin/ps", ["-o", "uid=", "-p", String(pid)])
        guard result.status == 0,
              let value = UInt32(result.out.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw HelperError.operationFailed("failed to resolve uid for pid \(pid): \(result.out)")
        }
        return value
    }

    private static func groupID(for pid: Int32) throws -> UInt32 {
        let result = run("/bin/ps", ["-o", "gid=", "-p", String(pid)])
        guard result.status == 0,
              let value = UInt32(result.out.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw HelperError.operationFailed("failed to resolve gid for pid \(pid): \(result.out)")
        }
        return value
    }

    private static func bootstrapOutputBridgeCompanion(destination: String) throws {
        var lastOutput = ""
        for attempt in 0 ..< 5 {
            if attempt > 0 {
                usleep(useconds_t(200_000 * attempt))
            }
            let bootstrap = run("/bin/launchctl", ["bootstrap", "system", destination])
            if bootstrap.status == 0 {
                return
            }
            lastOutput = bootstrap.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !lastOutput.localizedCaseInsensitiveContains("Input/output error"),
               !lastOutput.localizedCaseInsensitiveContains("i/o error")
            {
                break
            }
        }
        throw HelperError.operationFailed("bootstrap output bridge failed: \(lastOutput)")
    }

    private static func activateOutputBridgeCompanion() throws {
        let kickstart = run("/bin/launchctl", ["kickstart", "-k", "system/\(outputBridgeServiceID)"])
        guard kickstart.status == 0 else {
            throw HelperError.operationFailed("kickstart output bridge failed: \(kickstart.out)")
        }
    }

    private static func activatePreparedOutputBridgeSession(_ session: PreparedOutputBridgeSession) throws {
        if FileManager.default.fileExists(atPath: session.socketPath) {
            try? FileManager.default.removeItem(atPath: session.socketPath)
        }
        try activateOutputBridgeCompanion()
        try waitForPreparedOutputBridgeSocket(sessionID: session.sessionID, socketPath: session.socketPath)
    }

    private static func recoverOutputBridgeCompanion(for session: PreparedOutputBridgeSession) throws {
        if isServiceLoaded(outputBridgeServiceID) {
            do {
                try activateOutputBridgeCompanion()
                try waitForPreparedOutputBridgeSocket(sessionID: session.sessionID, socketPath: session.socketPath)
                return
            } catch {
                NSLog(
                    "[KeyPathHelper] output bridge service loaded but socket recovery failed; reinstalling daemon: %@",
                    error.localizedDescription
                )
            }
        }

        _ = run("/bin/launchctl", ["bootout", "system/\(outputBridgeServiceID)"])
        usleep(300_000)
        try ensureOutputBridgeCompanionInstalled()
        try activatePreparedOutputBridgeSession(session)
    }

    private static func waitForPreparedOutputBridgeSocket(sessionID: String, socketPath: String) throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) {
                return
            }
            usleep(100_000)
        }
        throw HelperError.operationFailed("output bridge companion did not bind socket for session \(sessionID)")
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
                    throw HelperError.operationFailed(
                        "Failed to terminate process \(pid): \(String(cString: strerror(errno)))"
                    )
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
                // Try graceful then force
                _ = Self.run("/usr/bin/pkill", ["-f", "kanata"]) // may return non-zero if none
                let still = Self.run("/usr/bin/pgrep", ["-f", "kanata"]).status == 0
                if still { _ = Self.run("/usr/bin/pkill", ["-9", "-f", "kanata"]) }
            },
            reply: reply
        )
    }

    func restartKarabinerDaemon(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] restartKarabinerDaemon requested")
        executePrivilegedOperation(
            name: "restartKarabinerDaemon",
            operation: {
                _ = Self.run("/usr/bin/pkill", ["-f", "Karabiner-VirtualHIDDevice-Daemon"]) // ignore status
                usleep(800_000)
            },
            reply: reply
        )
    }

    // MARK: - Karabiner Conflict Management

    func disableKarabinerGrabber(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] disableKarabinerGrabber requested")
        executePrivilegedOperation(
            name: "disableKarabinerGrabber",
            operation: {
                // Determine console user and uid for GUI launchctl domain
                var uid: uid_t = 0
                var gid: gid_t = 0
                let consoleName = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String? ?? ""

                // 1) Stop processes
                _ = Self.run("/usr/bin/pkill", ["-f", "karabiner_grabber"]) // ignore
                _ = Self.run("/usr/bin/pkill", ["-f", "VirtualHIDDevice"]) // ignore
                usleep(200_000)
                _ = Self.run("/usr/bin/pkill", ["-9", "-f", "karabiner_grabber"]) // force
                _ = Self.run("/usr/bin/pkill", ["-9", "-f", "VirtualHIDDevice"]) // force

                // 2) Disable and bootout LaunchAgent/Daemon for karabiner_grabber
                if uid != 0 {
                    _ = Self.run(
                        "/bin/launchctl", ["disable", "gui/\(uid)/org.pqrs.service.agent.karabiner_grabber"]
                    )
                    _ = Self.run(
                        "/bin/launchctl", ["bootout", "gui/\(uid)", "org.pqrs.service.agent.karabiner_grabber"]
                    ) // ignore status
                }
                _ = Self.run(
                    "/bin/launchctl", ["disable", "system/org.pqrs.service.daemon.karabiner_grabber"]
                ) // ignore
                _ = Self.run(
                    "/bin/launchctl", ["bootout", "system", "org.pqrs.service.daemon.karabiner_grabber"]
                ) // ignore

                // 3) Create marker file in console user's home to tell app to skip grabber checks
                if !consoleName.isEmpty, let home = Self.consoleUserHomeDirectory() {
                    let dir = (home as NSString).appendingPathComponent(".keypath")
                    let marker = (dir as NSString).appendingPathComponent("karabiner-grabber-disabled")
                    _ = Self.run("/bin/mkdir", ["-p", dir])
                    _ = Self.run("/usr/bin/touch", [marker])
                    // Adjust ownership to console user
                    _ = Self.run("/usr/sbin/chown", ["\(consoleName)", marker])
                }
            },
            reply: reply
        )
    }

    // Note: executeCommand removed for security. Use explicit operations only.

    // MARK: - Uninstall Operations

    func uninstallKeyPath(deleteConfig: Bool, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] uninstallKeyPath requested (deleteConfig: \(deleteConfig))")
        // Custom handling: send reply BEFORE self-destruct so XPC doesn't break
        do {
            try Self.performUninstallExceptSelfDestruct(deleteConfig: deleteConfig)
            NSLog("[KeyPathHelper] ✅ uninstallKeyPath succeeded (sending reply before self-destruct)")
            reply(true, nil)
            // Now self-destruct after reply is sent
            Self.selfDestruct()
        } catch let error as HelperError {
            NSLog("[KeyPathHelper] ❌ uninstallKeyPath failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        } catch {
            NSLog("[KeyPathHelper] ❌ uninstallKeyPath failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }

    /// Perform uninstall except for self-destruct (so we can send XPC reply first)
    private static func performUninstallExceptSelfDestruct(deleteConfig: Bool) throws {
        NSLog("[KeyPathHelper] Starting uninstall sequence...")

        // 1. Stop and unload LaunchDaemons
        NSLog("[KeyPathHelper] Step 1: Stopping LaunchDaemons...")
        stopAndUnloadDaemons()

        // 2. Remove LaunchDaemon plist files
        NSLog("[KeyPathHelper] Step 2: Removing LaunchDaemon plists...")
        removeLaunchDaemonPlists()

        // 3. Remove system kanata binary
        NSLog("[KeyPathHelper] Step 3: Removing system kanata binary...")
        removeSystemKanataBinary()

        // 4. Remove /usr/local/etc/kanata config directory (legacy)
        NSLog("[KeyPathHelper] Step 4: Removing legacy config directory...")
        removeLegacyConfigDirectory()

        // 5. Remove log files
        NSLog("[KeyPathHelper] Step 5: Removing log files...")
        removeLogFiles()

        // 6. Remove user data (preserving or deleting config based on flag)
        NSLog("[KeyPathHelper] Step 6: Removing user data (deleteConfig: \(deleteConfig))...")
        removeUserData(deleteConfig: deleteConfig)

        // 7. Remove the app bundle from /Applications
        // macOS allows deleting a running app - the binary stays in memory
        // The app will terminate itself after this helper call returns
        NSLog("[KeyPathHelper] Step 7: Removing app bundle...")
        removeAppBundle()

        NSLog("[KeyPathHelper] Uninstall steps 1-7 completed (self-destruct pending)")
    }

    /// Self-destruct: remove helper binary and boot out service
    /// Called AFTER XPC reply is sent to avoid breaking the connection
    private static func selfDestruct() {
        NSLog("[KeyPathHelper] Step 8: Self-destructing (removing privileged helper)...")
        removePrivilegedHelper()
        NSLog("[KeyPathHelper] Uninstall sequence completed successfully")
    }

    private static func stopAndUnloadDaemons() {
        let daemons = [kanataServiceID, outputBridgeServiceID, vhidDaemonServiceID, vhidManagerServiceID]
        for daemon in daemons {
            // Try to stop gracefully first
            _ = run("/bin/launchctl", ["kill", "TERM", "system/\(daemon)"])
            usleep(500_000) // 0.5 second
            // Bootout (unload)
            _ = run("/bin/launchctl", ["bootout", "system/\(daemon)"])
            NSLog("[KeyPathHelper] Stopped/unloaded: \(daemon)")
        }
        // Legacy log rotation daemon cleanup
        _ = run("/bin/launchctl", ["bootout", "system/com.keypath.logrotate"])
    }

    private static func removeLaunchDaemonPlists() {
        let plists = [
            "/Library/LaunchDaemons/\(kanataServiceID).plist",
            "/Library/LaunchDaemons/\(outputBridgeServiceID).plist",
            "/Library/LaunchDaemons/\(vhidDaemonServiceID).plist",
            "/Library/LaunchDaemons/\(vhidManagerServiceID).plist",
            "/Library/LaunchDaemons/com.keypath.logrotate.plist",
            "/Library/LaunchDaemons/com.keypath.helper.plist"
        ]
        for plist in plists {
            if FileManager.default.fileExists(atPath: plist) {
                _ = run("/bin/rm", ["-f", plist])
                NSLog("[KeyPathHelper] Removed plist: \(plist)")
            }
        }
    }

    private static func removeSystemKanataBinary() {
        let kanataPath = "/Library/KeyPath/bin/kanata"
        if FileManager.default.fileExists(atPath: kanataPath) {
            _ = run("/bin/rm", ["-f", kanataPath])
            NSLog("[KeyPathHelper] Removed: \(kanataPath)")
        }
        // Clean up empty directories
        _ = run("/bin/rmdir", ["/Library/KeyPath/bin"])
        _ = run("/bin/rmdir", ["/Library/KeyPath"])
    }

    private static func removeLegacyConfigDirectory() {
        let configDir = "/usr/local/etc/kanata"
        if FileManager.default.fileExists(atPath: configDir) {
            _ = run("/bin/rm", ["-rf", configDir])
            NSLog("[KeyPathHelper] Removed legacy config: \(configDir)")
        }
    }

    private static func removeLogFiles() {
        let logs = [
            "/var/log/com.keypath.kanata.stdout.log",
            "/var/log/com.keypath.kanata.stderr.log",
            "/var/log/kanata.log",
            "/var/log/kanata.log.1",
            "/var/log/karabiner-vhid-daemon.log",
            "/var/log/karabiner-vhid-manager.log",
            "/var/log/keypath-logrotate.log",
            "/var/log/com.keypath.helper.stdout.log",
            "/var/log/com.keypath.helper.stderr.log",
            KeyPathConstants.OutputBridge.stdoutLog,
            KeyPathConstants.OutputBridge.stderrLog
        ]
        for log in logs {
            if FileManager.default.fileExists(atPath: log) {
                _ = run("/bin/rm", ["-f", log])
                NSLog("[KeyPathHelper] Removed log: \(log)")
            }
        }
        // Remove newsyslog config
        if FileManager.default.fileExists(atPath: "/etc/newsyslog.d/com.keypath.conf") {
            _ = run("/bin/rm", ["-f", "/etc/newsyslog.d/com.keypath.conf"])
            NSLog("[KeyPathHelper] Removed newsyslog config")
        }
        // Remove legacy log rotation script
        if FileManager.default.fileExists(atPath: "/usr/local/bin/keypath-logrotate.sh") {
            _ = run("/bin/rm", ["-f", "/usr/local/bin/keypath-logrotate.sh"])
            NSLog("[KeyPathHelper] Removed legacy log rotation script")
        }
    }

    private static func removeUserData(deleteConfig: Bool) {
        guard let info = consoleUserInfo() else {
            NSLog("[KeyPathHelper] Could not determine console user; skipping user data cleanup")
            return
        }

        let home = info.home
        let user = info.name

        // User config (only if deleteConfig is true)
        if deleteConfig {
            let configPath = "\(home)/.config/keypath"
            if FileManager.default.fileExists(atPath: configPath) {
                _ = run("/bin/rm", ["-rf", configPath])
                NSLog("[KeyPathHelper] Removed user config: \(configPath)")
            }
        } else {
            NSLog("[KeyPathHelper] Preserving user config at \(home)/.config/keypath")
        }

        // Application Support and Logs
        let userPaths = [
            "\(home)/Library/Application Support/KeyPath",
            "\(home)/Library/Logs/KeyPath"
        ]
        for path in userPaths {
            if FileManager.default.fileExists(atPath: path) {
                _ = run("/bin/rm", ["-rf", path])
                NSLog("[KeyPathHelper] Removed: \(path)")
            }
        }

        // Preference plists
        let prefsDir = "\(home)/Library/Preferences"
        let prefFiles = [
            "\(prefsDir)/com.keypath.KeyPath.plist",
            "\(prefsDir)/com.keypath.app.plist"
        ]
        for pref in prefFiles {
            if FileManager.default.fileExists(atPath: pref) {
                _ = run("/bin/rm", ["-f", pref])
                NSLog("[KeyPathHelper] Removed pref: \(pref)")
            }
        }

        // Kill cfprefsd to flush preference cache for user
        _ = run("/usr/bin/killall", ["-u", user, "cfprefsd"])
    }

    private static func removeAppBundle() {
        let appPath = "/Applications/KeyPath.app"
        if FileManager.default.fileExists(atPath: appPath) {
            // Use rm -rf to remove the entire app bundle
            // macOS allows this even while the app is running - the binary stays in memory
            let result = run("/bin/rm", ["-rf", appPath])
            if result.status == 0 {
                NSLog("[KeyPathHelper] Removed app bundle: \(appPath)")
            } else {
                NSLog("[KeyPathHelper] Warning: Could not remove app bundle: \(result.out)")
            }
        } else {
            NSLog("[KeyPathHelper] App bundle not found at \(appPath)")
        }
    }

    private static func removePrivilegedHelper() {
        // Remove the helper binary and plist
        // Note: We're currently running, but macOS keeps us in memory
        let helperPaths = [
            "/Library/PrivilegedHelperTools/com.keypath.helper",
            "/Library/LaunchDaemons/com.keypath.helper.plist"
        ]
        for path in helperPaths {
            if FileManager.default.fileExists(atPath: path) {
                _ = run("/bin/rm", ["-f", path])
                NSLog("[KeyPathHelper] Removed: \(path)")
            }
        }
        // Bootout the helper service (this won't kill us immediately since we're mid-call)
        _ = run("/bin/launchctl", ["bootout", "system/com.keypath.helper"])
        NSLog("[KeyPathHelper] Helper service booted out")
    }

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
            logger.error(
                "\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            reply(false, error.localizedDescription)
        } catch {
            NSLog("[KeyPathHelper] ❌ \(name) failed: \(error.localizedDescription)")
            logger.error(
                "\(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            reply(false, error.localizedDescription)
        }
    }
}

private struct PreparedOutputBridgeSession: Codable, Sendable {
    let sessionID: String
    let socketPath: String
    let hostPID: Int32
    let hostUID: UInt32
    let hostGID: UInt32
}

// MARK: - Error Types

/// Errors that can occur during privileged operations
enum HelperError: Error, LocalizedError {
    case notImplemented(String)
    case operationFailed(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case let .notImplemented(operation):
            "Operation not yet implemented: \(operation)"
        case let .operationFailed(reason):
            "Operation failed: \(reason)"
        case let .invalidArgument(reason):
            "Invalid argument: \(reason)"
        }
    }
}

// MARK: - Helpers

extension HelperService {
    /// Copy file only if content differs (quick MD5 check). Returns true if a copy occurred.
    @discardableResult
    static func copyIfDifferent(src: String, dst: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst) {
            let srcHash = run("/sbin/md5", ["-q", src]).out.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let dstHash = run("/sbin/md5", ["-q", dst]).out.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !srcHash.isEmpty, srcHash == dstHash {
                NSLog("[KeyPathHelper] Skipping copy; kanata unchanged (")
                return false
            }
        }
        let cp = run("/bin/cp", ["-f", src, dst])
        if cp.status != 0 {
            NSLog("[KeyPathHelper] copyIfDifferent: cp failed: \(cp.out)")
        }
        return cp.status == 0
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = args
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        do { try p.run() } catch { return (127, "run failed: \(error)") }
        p.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, s)
    }

    static func verifyCodeSignatureStrict(path: String) -> Bool {
        let result = run(
            "/usr/bin/codesign",
            ["--verify", "--strict", "--verbose=2", path]
        )
        if result.status != 0 {
            NSLog(
                "[KeyPathHelper] codesign verification failed for %@: %@",
                path,
                result.out.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.status == 0
    }

    static func teamIdentifier(for path: String) -> String? {
        let result = run("/usr/bin/codesign", ["-d", "--verbose=4", path])
        let output = result.out
        return firstMatch(#"TeamIdentifier=([A-Z0-9]+)"#, in: output)
    }

    /// Basic service inspection helpers (minimal parsing of `launchctl print`)
    static func isServiceLoaded(_ serviceID: String) -> Bool {
        let r = run("/bin/launchctl", ["print", "system/\(serviceID)"])
        return r.status == 0
    }

    static func isServiceHealthy(_ serviceID: String) -> Bool {
        let r = run("/bin/launchctl", ["print", "system/\(serviceID)"])
        guard r.status == 0 else { return false }
        let out = r.out
        let state = firstMatch(#"state\s*=\s*([A-Za-z]+)"#, in: out)?.lowercased()
        let pidStr =
            firstMatch(#"\bpid\s*=\s*([0-9]+)"#, in: out) ?? firstMatch(#""PID"\s*=\s*([0-9]+)"#, in: out)
        let lastExit =
            firstInt(#"last exit (?:status|code)\s*=\s*(-?\d+)"#, in: out)
                ?? firstInt(#""LastExitStatus"\s*=\s*(-?\d+)"#, in: out)

        let isOneShot = (serviceID == Self.vhidManagerServiceID)
        let runningLike = (state == "running" || state == "launching")
        let hasPID = (pidStr != nil)

        if isOneShot {
            // one-shot is healthy if last exit was 0, or currently running/launching
            if let le = lastExit, le == 0 { return true }
            if runningLike || hasPID { return true }
            return false
        } else {
            // keepalive jobs should be running (allow launching)
            return runningLike || hasPID
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let m = r.firstMatch(in: text, options: [], range: range), m.numberOfRanges >= 2,
              let gr = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[gr])
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        firstMatch(pattern, in: text).flatMap { Int($0) }
    }

    static func generateNewsyslogConfig() -> String {
        """
        # KeyPath log rotation - managed by KeyPath installer
        # Rotate kanata logs at 10MB, keep 3 compressed archives.
        # Keep legacy /var/log/kanata.log for older installs.
        /var/log/com.keypath.kanata.stdout.log\t644  3\t10240  *\tNJ
        /var/log/com.keypath.kanata.stderr.log\t644  3\t10240  *\tNJ
        /var/log/kanata.log\t\t\t644  3\t10240  *\tNJ
        """
    }

    // MARK: - LaunchDaemon service helpers

    private static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"
    private static let vhidDaemonPath =
        "/Library/Application Support/org.pqrs/" + "Karabiner-DriverKit-VirtualHIDDevice/Applications/"
            + "Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/" + "Karabiner-VirtualHIDDevice-Daemon"
    fileprivate static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    private static let karabinerTeamID = "G43BCU2T37"
    private static let karabinerDriverBundleID =
        "org.pqrs.driver.Karabiner-DriverKit-VirtualHIDDevice"
    // IMPORTANT: Keep in sync with WizardSystemPaths.bundledVHIDDriverVersion in KeyPathCore
    // The helper doesn't have access to KeyPathCore, so we maintain a copy here
    // This is only used for the deprecated download fallback path
    private static let requiredVHIDVersion = "6.0.0"

    fileprivate static func appBundlePathFromHelper() -> String {
        let exe =
            CommandLine.arguments.first
                ?? "/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper"
        if let range = exe.range(of: "/Contents/Library/HelperTools/KeyPathHelper") {
            return String(exe[..<range.lowerBound])
        }
        // Fallback to /Applications
        return "/Applications/KeyPath.app"
    }

    private static func consoleUserInfo() -> (name: String, home: String)? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
              !name.isEmpty
        else {
            return nil
        }
        return (name, "/Users/\(name)")
    }

    private static func consoleUserHomeDirectory() -> String? {
        consoleUserInfo()?.home
    }

    private static func ensureConsoleUserConfigArtifacts() throws {
        guard let info = consoleUserInfo() else {
            NSLog("[KeyPathHelper] Unable to determine console user; skipping config scaffolding")
            return
        }

        let configDir = "\(info.home)/.config/keypath"
        let configFile = "\(configDir)/keypath.kbd"

        _ = run("/usr/bin/install", ["-d", "-o", info.name, "-g", "staff", configDir])
        _ = run("/usr/bin/touch", [configFile])
        _ = run("/usr/sbin/chown", ["\(info.name):staff", configFile])
    }

    private static func kanataArguments(binaryPath: String, cfgPath: String, tcpPort: Int) -> [String] {
        [binaryPath, "--cfg", cfgPath, "--port", String(tcpPort), "--log-layer-changes"]
    }

    private static func generateKanataPlist(binaryPath: String, cfgPath: String, tcpPort: Int)
        -> String
    {
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
            <string>/var/log/com.keypath.kanata.stdout.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/com.keypath.kanata.stderr.log</string>
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
        """
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
        """
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
}
