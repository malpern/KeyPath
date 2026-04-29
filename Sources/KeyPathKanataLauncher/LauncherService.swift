import ApplicationServices
import Foundation
import KeyPathCore

// MARK: - Constants

enum LauncherConstants {
    static let retryCountPath = "/var/tmp/keypath-vhid-retry-count"
    static let startupBlockedPath = "/var/tmp/keypath-startup-blocked"
    static let maxRetries = 3
    static let retryResetSeconds: TimeInterval = 60
    static let preferencesPlistBasename = "com.keypath.KeyPath.plist"
    static let verboseLoggingPrefKey = "KeyPath.Diagnostics.VerboseKanataLogging"
}

// MARK: - LauncherService

struct LauncherService {
    func run() -> Never {
        guard isVHIDDaemonRunning() else {
            handleMissingVHID()
        }

        try? FileManager.default.removeItem(atPath: LauncherConstants.retryCountPath)
        try? FileManager.default.removeItem(atPath: LauncherConstants.startupBlockedPath)

        let user = consoleUser()
        let home = homeDirectory(for: user)
        let configPath = ensureConfigFile(for: user, home: home)
        let runtimeHost = KanataRuntimeHost.current()
        let addTrace = isVerboseLoggingEnabled(home: home)

        let launchRequest = KanataRuntimeLaunchRequest(
            configPath: configPath,
            inheritedArguments: Array(CommandLine.arguments.dropFirst()),
            addTraceLogging: addTrace
        )
        let binaryPath = launchRequest.resolvedCoreBinaryPath(using: runtimeHost)
        let commandLine = launchRequest.commandLine(binaryPath: binaryPath)

        logLine("Launching Kanata for user=\(user) config=\(configPath)")
        logLine("Runtime host path: \(runtimeHost.launcherPath)")
        logLine(KanataHostBridge.probe(runtimeHost: runtimeHost).logSummary)
        logLine(KanataHostBridge.validateConfig(runtimeHost: runtimeHost, configPath: configPath).logSummary)
        logLine(KanataHostBridge.createRuntime(runtimeHost: runtimeHost, configPath: configPath).logSummary)

        logLine("Using kanata binary: \(binaryPath)")
        if addTrace {
            logLine("Verbose logging enabled via user preference (--trace)")
        }

        execKanata(commandLine: commandLine)
    }

    // MARK: - Logging

    func logLine(_ message: String) {
        FileHandle.standardError.write(Data("[kanata-launcher] \(message)\n".utf8))
    }

    // MARK: - Retry Management

    func readRetryCount() -> Int {
        let path = LauncherConstants.retryCountPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= LauncherConstants.retryResetSeconds,
              let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            try? FileManager.default.removeItem(atPath: path)
            return 0
        }
        return value
    }

    func writeRetryCount(_ count: Int) {
        try? "\(count)".write(toFile: LauncherConstants.retryCountPath, atomically: true, encoding: .utf8)
    }

    // MARK: - VHID Detection

    func isVHIDDaemonRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "VirtualHIDDevice-Daemon"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - User / Home Directory

    func consoleUser() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
        process.arguments = ["-f%Su", "/dev/console"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let user = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return user.isEmpty ? "root" : user
        } catch {
            return "root"
        }
    }

    func homeDirectory(for user: String) -> String {
        guard user != "root", !user.isEmpty else { return "/var/root" }
        if let dir = FileManager.default.homeDirectory(forUser: user)?.path, !dir.isEmpty {
            return dir
        }
        return "/Users/\(user)"
    }

    // MARK: - Configuration

    func ensureConfigFile(for user: String, home: String) -> String {
        let configPath = "\(home)/.config/keypath/keypath.kbd"
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configPath) {
            FileManager.default.createFile(atPath: configPath, contents: Data())
        }

        if user != "root", let pw = getpwnam(user) {
            _ = chown(configDir, pw.pointee.pw_uid, pw.pointee.pw_gid)
            _ = chown(configPath, pw.pointee.pw_uid, pw.pointee.pw_gid)
        }

        return configPath
    }

    func isVerboseLoggingEnabled(home: String) -> Bool {
        let prefs = "\(home)/Library/Preferences/\(LauncherConstants.preferencesPlistBasename)"
        guard let dict = NSDictionary(contentsOfFile: prefs),
              let value = dict[LauncherConstants.verboseLoggingPrefKey]
        else {
            return false
        }

        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let string as NSString:
            return string.boolValue
        default:
            return false
        }
    }

    // MARK: - Process Execution

    func execKanata(commandLine args: [String]) -> Never {
        let binaryPath = args[0]
        let cArgs = args.map { strdup($0) } + [nil]
        defer {
            for ptr in cArgs where ptr != nil {
                free(ptr)
            }
        }

        execv(binaryPath, cArgs)
        let err = String(cString: strerror(errno))
        logLine("execv failed for \(binaryPath): \(err)")
        Foundation.exit(1)
    }

    // MARK: - Environment Helpers


    func environmentFlag(_ key: String) -> Bool {
        let value = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    func environmentUInt64(_ key: String, defaultValue: UInt64) -> UInt64 {
        guard
            let raw = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let value = UInt64(raw)
        else {
            return defaultValue
        }
        return value
    }

    func extractTCPPort(from arguments: [String]) -> UInt16 {
        guard let portFlagIndex = arguments.firstIndex(of: "--port"),
              arguments.indices.contains(portFlagIndex + 1),
              let port = UInt16(arguments[portFlagIndex + 1])
        else {
            return 0
        }
        return port
    }

    func handleMissingVHID() -> Never {
        let retryCount = readRetryCount() + 1
        writeRetryCount(retryCount)
        logLine("VirtualHID daemon not running (attempt \(retryCount)/\(LauncherConstants.maxRetries))")

        if retryCount >= LauncherConstants.maxRetries {
            let message = "\(Date()): VirtualHID daemon not available after \(LauncherConstants.maxRetries) attempts\n"
            try? message.write(toFile: LauncherConstants.startupBlockedPath, atomically: true, encoding: .utf8)
            logLine("Max retries reached. Exiting cleanly to stop restart loop.")
            Foundation.exit(0)
        }

        Foundation.exit(1)
    }
}
