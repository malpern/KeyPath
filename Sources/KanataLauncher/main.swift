/// KanataLauncher - A signed Swift binary that launches Kanata with proper configuration
///
/// This replaces the shell script version to satisfy SMAppService code signing requirements.
/// It runs as root via LaunchDaemon and:
/// 1. Checks if VirtualHID daemon is running (crash loop prevention)
/// 2. Finds the console user's home directory
/// 3. Ensures config directory exists with proper ownership
/// 4. Executes kanata with the user's config file

import Foundation

// MARK: - Constants

let retryCountFile = "/var/tmp/keypath-vhid-retry-count"
let startupBlockedFile = "/var/tmp/keypath-startup-blocked"
let maxRetries = 3
let retryResetSeconds: TimeInterval = 60

// MARK: - Logging

func log(_ message: String) {
    // Use syslog via logger command for consistency with shell version
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/logger")
    task.arguments = ["-t", "kanata-launcher", message]
    try? task.run()
    task.waitUntilExit()
}

// MARK: - VirtualHID Check

func isVHIDDaemonRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "VirtualHIDDevice-Daemon"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}

// MARK: - Retry Counter

func getRetryCount() -> Int {
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: retryCountFile) else {
        return 0
    }

    // Check if file is stale
    do {
        let attrs = try fileManager.attributesOfItem(atPath: retryCountFile)
        if let modDate = attrs[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modDate)
            if age > retryResetSeconds {
                try? fileManager.removeItem(atPath: retryCountFile)
                return 0
            }
        }
    } catch {
        return 0
    }

    // Read current count
    guard let contents = fileManager.contents(atPath: retryCountFile),
          let str = String(data: contents, encoding: .utf8),
          let count = Int(str.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
        return 0
    }

    return count
}

func incrementRetryCount() -> Int {
    let count = getRetryCount() + 1
    try? "\(count)".write(toFile: retryCountFile, atomically: true, encoding: .utf8)
    return count
}

func clearRetryState() {
    try? FileManager.default.removeItem(atPath: retryCountFile)
    try? FileManager.default.removeItem(atPath: startupBlockedFile)
}

// MARK: - Console User Detection

func getConsoleUser() -> String {
    // stat -f%Su /dev/console
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
    task.arguments = ["-f%Su", "/dev/console"]
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let user = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !user.isEmpty
        {
            return user
        }
    } catch {}

    return "root"
}

func getHomeDirectory(for user: String) -> String {
    if user == "root" || user.isEmpty {
        return "/var/root"
    }

    // Use dscacheutil to get home directory
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
    task.arguments = ["-q", "user", "-a", "name", user]
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            // Parse "dir: /Users/username" line
            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("dir:") {
                    let home = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                    if !home.isEmpty {
                        return home
                    }
                }
            }
        }
    } catch {}

    return "/Users/\(user)"
}

func getPrimaryGroup(for user: String) -> String? {
    guard user != "root" && !user.isEmpty else { return nil }

    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/id")
    task.arguments = ["-gn", user]
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let group = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !group.isEmpty
            {
                return group
            }
        }
    } catch {}

    return nil
}

// MARK: - Config Directory Setup

func ensureConfigDirectory(at path: String, user: String, group: String?) {
    let fileManager = FileManager.default

    // Create directory if needed
    if !fileManager.fileExists(atPath: path) {
        // Use install command for proper ownership
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/install")

        if user != "root", let group = group {
            task.arguments = ["-d", "-m", "755", "-o", user, "-g", group, path]
        } else {
            task.arguments = ["-d", "-m", "755", path]
        }

        try? task.run()
        task.waitUntilExit()
    }
}

func ensureConfigFile(at path: String, user: String, group: String?) {
    let fileManager = FileManager.default

    // Touch the file if it doesn't exist
    if !fileManager.fileExists(atPath: path) {
        fileManager.createFile(atPath: path, contents: nil, attributes: nil)
    }

    // Set ownership for non-root users
    if user != "root" {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
        task.arguments = ["\(user):\(group ?? "staff")", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Main

func main() -> Int32 {
    // Get path to kanata binary (same directory as this launcher)
    // NOTE: SMAppService passes a relative path like "Contents/Library/KeyPath/kanata-launcher"
    // so we need to resolve it relative to the app bundle
    var launcherPath = CommandLine.arguments[0]

    // If the path is relative (doesn't start with /), prepend the app bundle location
    if !launcherPath.hasPrefix("/") {
        // SMAppService daemons are relative to app bundle
        launcherPath = "/Applications/KeyPath.app/\(launcherPath)"
    }

    let launcherDir = (launcherPath as NSString).deletingLastPathComponent
    let kanataBin = (launcherDir as NSString).appendingPathComponent("kanata")

    // Pre-flight check: ensure VirtualHID daemon is available
    if !isVHIDDaemonRunning() {
        let retryCount = incrementRetryCount()
        log("VirtualHID daemon not running (attempt \(retryCount)/\(maxRetries))")

        if retryCount >= maxRetries {
            // Too many failures - exit cleanly to stop launchd from restarting
            // (SuccessfulExit: false in plist means exit 0 = stop restarting)
            log("Max retries reached. Exiting cleanly to stop restart loop. Open KeyPath app to diagnose.")

            // Write status file for KeyPath app to detect
            let timestamp = ISO8601DateFormatter().string(from: Date())
            try? "\(timestamp): VirtualHID daemon not available after \(maxRetries) attempts"
                .write(toFile: startupBlockedFile, atomically: true, encoding: .utf8)

            return 0 // Clean exit stops restart loop
        }

        // Exit with error so launchd knows to retry (ThrottleInterval will space out attempts)
        return 1
    }

    // VirtualHID is healthy - reset retry counter and status file
    clearRetryState()

    // Get console user info
    let consoleUser = getConsoleUser()
    let consoleHome = getHomeDirectory(for: consoleUser)
    let consoleGroup = getPrimaryGroup(for: consoleUser)

    // Setup config paths
    let configPath = "\(consoleHome)/.config/keypath/keypath.kbd"
    let configDir = (configPath as NSString).deletingLastPathComponent

    // Ensure config directory and file exist with proper ownership
    ensureConfigDirectory(at: configDir, user: consoleUser, group: consoleGroup)
    ensureConfigFile(at: configPath, user: consoleUser, group: consoleGroup)

    log("Launching Kanata for user=\(consoleUser) config=\(configPath)")

    // Build arguments: kanata --cfg <config> [additional args passed to launcher]
    var kanataArgs = ["--cfg", configPath]

    // Pass through any additional arguments (skip argv[0] which is launcher path)
    if CommandLine.arguments.count > 1 {
        kanataArgs.append(contentsOf: Array(CommandLine.arguments.dropFirst()))
    }

    // Execute kanata (replaces this process)
    let argv = [kanataBin] + kanataArgs
    let cArgs = argv.map { strdup($0) } + [nil]
    execv(kanataBin, cArgs)

    // If execv returns, it failed
    log("Failed to exec kanata: \(String(cString: strerror(errno)))")
    return 1
}

exit(main())
