import Foundation

/// System paths and configuration constants for the Installation Wizard
/// Centralizes hardcoded paths to improve maintainability and testing
public enum WizardSystemPaths {
    // MARK: - Test Overrides

    private static func currentTestRoot() -> String? {
        guard let raw = ProcessInfo.processInfo.environment["KEYPATH_TEST_ROOT"],
              !raw.isEmpty
        else {
            return nil
        }
        if raw.hasSuffix("/") {
            return String(raw.dropLast())
        }
        return raw
    }

    public static func remapSystemPath(_ path: String) -> String {
        guard let root = currentTestRoot(), path.hasPrefix("/") else {
            return path
        }
        if path.hasPrefix(root) {
            return path
        }
        return root + path
    }

    private static func resolvedHomeDirectory() -> String {
        if let override = ProcessInfo.processInfo.environment["KEYPATH_HOME_DIR_OVERRIDE"],
           !override.isEmpty {
            return override
        }
        return NSHomeDirectory()
    }

    public static var userHomeDirectory: String {
        resolvedHomeDirectory()
    }

    // MARK: - Binary Paths

    /// System-installed kanata binary location (avoids Gatekeeper issues)
    /// This is where the LaunchDaemon installer copies the bundled binary
    public static var kanataSystemInstallPath: String {
        remapSystemPath("/Library/KeyPath/bin/kanata")
    }

    /// Standard kanata binary location - used for both homebrew and experimental versions
    /// Using a single standard location simplifies permission management
    public static var kanataStandardLocation: String {
        remapSystemPath("/usr/local/bin/kanata")
    }

    /// Primary kanata binary location (ARM Macs with Homebrew)
    public static var kanataBinaryARM: String {
        remapSystemPath("/opt/homebrew/bin/kanata")
    }

    /// Default kanata binary path for most operations (same as standard)
    public static var kanataBinaryDefault: String {
        remapSystemPath("/usr/local/bin/kanata")
    }

    private nonisolated(unsafe) static var bundledKanataPathOverride: String?

    public static func setBundledKanataPathOverride(_ path: String?) {
        bundledKanataPathOverride = path
    }

    /// Bundled kanata binary path (preferred - properly signed)
    public static var bundledKanataPath: String {
        if let override = bundledKanataPathOverride, !override.isEmpty {
            return override
        }
        if let override = ProcessInfo.processInfo.environment["KEYPATH_BUNDLED_KANATA_OVERRIDE"],
           !override.isEmpty {
            return override
        }
        return "\(Bundle.main.bundlePath)/Contents/Library/KeyPath/kanata"
    }

    /// Bundled kanata simulator binary path (for dry-run simulation)
    /// This binary outputs structured JSON instead of sending real HID events
    public static var bundledSimulatorPath: String {
        if let override = ProcessInfo.processInfo.environment["KEYPATH_BUNDLED_SIMULATOR_OVERRIDE"],
           !override.isEmpty {
            return override
        }
        return "\(Bundle.main.bundlePath)/Contents/Library/KeyPath/kanata-simulator"
    }

    /// Checks if the bundled simulator binary exists
    public static var bundledSimulatorExists: Bool {
        FileManager.default.fileExists(atPath: bundledSimulatorPath)
    }

    /// Active kanata binary path - uses simple filesystem checks for performance
    /// Single canonical path eliminates TCC permission fragmentation
    public static var kanataActiveBinary: String {
        // Use system install path if it exists (for LaunchDaemon)
        // Otherwise use bundled path (for UI/detection)
        if FileManager.default.fileExists(atPath: kanataSystemInstallPath) {
            return kanataSystemInstallPath
        }
        return bundledKanataPath
    }

    /// All known kanata binary paths for detection/filtering
    public static func allKnownKanataPaths() -> [String] {
        [kanataSystemInstallPath, bundledKanataPath].filter {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    /// Homebrew binary path
    public static var brewBinary: String {
        remapSystemPath("/opt/homebrew/bin/brew")
    }

    // MARK: - Configuration Paths

    /// User configuration file path following industry standard ~/.config/ pattern
    public static var userConfigPath: String {
        "\(userHomeDirectory)/.config/keypath/keypath.kbd"
    }

    /// User configuration directory
    public static var userConfigDirectory: String {
        "\(userHomeDirectory)/.config/keypath"
    }

    /// Legacy system configuration directory (no longer used)
    public static var systemConfigDirectory: String {
        remapSystemPath("/usr/local/etc/kanata")
    }

    /// Legacy system configuration file path (no longer used)
    public static var systemConfigPath: String {
        remapSystemPath("/usr/local/etc/kanata/keypath.kbd")
    }

    // MARK: - Log Files

    /// Candidate Kanata log files (SMAppService stdout first, legacy launchctl second)
    public static var kanataLogFileCandidates: [String] {
        [
            remapSystemPath("/var/log/com.keypath.kanata.stdout.log"),
            remapSystemPath("/var/log/kanata.log")
        ]
    }

    /// Main kanata log file (prefers existing candidate paths)
    public static var kanataLogFile: String {
        let fileManager = FileManager.default
        if let existing = kanataLogFileCandidates.first(where: { fileManager.fileExists(atPath: $0) }) {
            return existing
        }
        return kanataLogFileCandidates.first ?? "/var/log/com.keypath.kanata.stdout.log"
    }

    /// System log directory
    public static var systemLogDirectory: String {
        remapSystemPath("/var/log")
    }

    // MARK: - Service Paths

    /// LaunchDaemon plist file
    public static var launchDaemonPlist: String {
        remapSystemPath("/Library/LaunchDaemons/com.keypath.kanata.plist")
    }

    /// LaunchDaemon service identifier
    public static let launchDaemonIdentifier = "com.keypath.kanata"

    // MARK: - Karabiner Paths

    /// Karabiner-Elements VirtualHIDDevice path
    public static let karabinerVHIDDevice =
        "/Applications/Karabiner-Elements.app/Contents/Library/bin/karabiner_grabber"

    /// Karabiner-Elements daemon path
    public static let karabinerDaemon =
        "/Library/Application Support/org.pqrs.Karabiner-Elements/bin/karabiner_session_monitor"

    // MARK: - System Preference URLs

    /// Privacy & Security settings URL
    public static let privacySecuritySettings =
        "x-apple.systempreferences:com.apple.preference.security"

    /// Input Monitoring settings URL
    public static let inputMonitoringSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    /// Accessibility settings URL
    public static let accessibilitySettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Full Disk Access settings URL (needed to read TCC.db for kanata detection)
    public static let fullDiskAccessSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Login Items settings URL (macOS 13+)
    public static let loginItemsSettings =
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    // MARK: - Helper Methods

    /// Returns the best available kanata binary path - simple filesystem check for performance
    public static func detectKanataBinaryPath() -> String? {
        // Prefer system-installed path (for LaunchDaemon)
        if FileManager.default.fileExists(atPath: kanataSystemInstallPath) {
            return kanataSystemInstallPath
        }

        // Fall back to bundled kanata
        if FileManager.default.fileExists(atPath: bundledKanataPath) {
            return bundledKanataPath
        }

        return nil
    }

    // MARK: - Bundled Driver Paths

    /// The bundled VHID driver version - single source of truth
    /// Update this when bundling a new driver version
    public static let bundledVHIDDriverVersion = "6.0.0"

    /// The bundled VHID driver major version (for compatibility checks)
    public static var bundledVHIDDriverMajorVersion: Int {
        Int(bundledVHIDDriverVersion.split(separator: ".").first ?? "0") ?? 0
    }

    /// Bundled VHID driver package filename
    private static var bundledVHIDDriverPkgFilename: String {
        "Karabiner-DriverKit-VirtualHIDDevice-\(bundledVHIDDriverVersion)"
    }

    /// Bundled VHID driver package path
    /// This is the Karabiner-DriverKit-VirtualHIDDevice .pkg bundled with KeyPath
    /// Uses Bundle.main.url(forResource:) to work with both SPM bundles and proper app bundles
    public static var bundledVHIDDriverPkgPath: String {
        // Try Bundle.main first (works for both SPM and app bundles)
        if let url = Bundle.main.url(
            forResource: bundledVHIDDriverPkgFilename,
            withExtension: "pkg"
        ) {
            return url.path
        }
        // Fallback to expected app bundle location
        return "\(Bundle.main.bundlePath)/Contents/Resources/\(bundledVHIDDriverPkgFilename).pkg"
    }

    /// Checks if the bundled VHID driver package exists
    public static var bundledVHIDDriverPkgExists: Bool {
        FileManager.default.fileExists(atPath: bundledVHIDDriverPkgPath)
    }

    /// Checks if the user config file exists
    public static var userConfigExists: Bool {
        FileManager.default.fileExists(atPath: userConfigPath)
    }

    /// Checks if the system config directory exists
    public static var systemConfigDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: systemConfigDirectory)
    }

    // MARK: - Kanata Migration Detection

    /// Common Kanata config file names to search for
    public static var commonKanataConfigNames: [String] {
        ["kanata.kbd", "config.kbd", "keypath.kbd"]
    }

    /// Common directories where users store Kanata configs
    public static var commonKanataConfigDirectories: [String] {
        [
            "\(userHomeDirectory)/.config/kanata",
            "\(userHomeDirectory)/.config/keypath",
            userHomeDirectory,
            systemConfigDirectory
        ]
    }

    /// Detect existing Kanata config files in common locations
    /// Returns array of (path, displayName) tuples for found configs
    public static func detectExistingKanataConfigs() -> [(path: String, displayName: String)] {
        var foundConfigs: [(path: String, displayName: String)] = []
        let fileManager = FileManager.default

        for directory in commonKanataConfigDirectories {
            guard fileManager.fileExists(atPath: directory) else { continue }

            for configName in commonKanataConfigNames {
                let fullPath = "\(directory)/\(configName)"
                if fileManager.fileExists(atPath: fullPath) {
                    // Skip if it's already KeyPath's expected location
                    if fullPath == userConfigPath {
                        continue
                    }
                    let displayName = displayPath(for: fullPath)
                    foundConfigs.append((path: fullPath, displayName: displayName))
                }
            }
        }

        // Also check for configs directly in home directory (e.g., ~/.kanata.kbd)
        for configName in commonKanataConfigNames {
            let homeConfigPath = "\(userHomeDirectory)/.\(configName)"
            if fileManager.fileExists(atPath: homeConfigPath) {
                let displayName = displayPath(for: homeConfigPath)
                foundConfigs.append((path: homeConfigPath, displayName: displayName))
            }
        }

        return foundConfigs
    }

    /// KeyPath's expected config directory (Application Support)
    public static var keyPathConfigDirectory: String {
        "\(userHomeDirectory)/Library/Application Support/KeyPath"
    }

    /// KeyPath's expected config path (Application Support)
    public static var keyPathConfigPath: String {
        "\(keyPathConfigDirectory)/keypath.kbd"
    }

    /// KeyPath's generated apps config file
    public static var keyPathAppsConfigPath: String {
        "\(keyPathConfigDirectory)/keypath-apps.kbd"
    }

    /// Creates a display path for user interfaces (uses ~ for home directory)
    public static func displayPath(for fullPath: String) -> String {
        let homeDirectory = userHomeDirectory
        if fullPath.hasPrefix(homeDirectory) {
            return fullPath.replacingOccurrences(of: homeDirectory, with: "~")
        }
        return fullPath
    }

    // MARK: - Running Kanata Process Detection

    /// Information about a running Kanata process
    public struct RunningKanataInfo {
        public let pid: Int
        public let configPath: String?
        public let binaryPath: String
        public let isKeyPathManaged: Bool
    }

    /// Detect a running Kanata process and extract its config path from command line args
    /// Returns nil if no Kanata process is running
    /// Prioritizes external (non-KeyPath) processes over KeyPath-managed ones
    public static func detectRunningKanataProcess() -> RunningKanataInfo? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,args"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Known KeyPath-managed binary paths
        let keyPathManagedPaths = [
            kanataSystemInstallPath,
            bundledKanataPath
        ]

        var externalProcess: RunningKanataInfo?
        var keyPathProcess: RunningKanataInfo?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip lines that don't contain kanata binary
            guard trimmed.contains("kanata") else { continue }
            // Skip grep/ps commands themselves
            guard !trimmed.contains("grep") && !trimmed.contains("ps -eo") else { continue }

            // Parse PID and args
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int(parts[0]) else { continue }

            let args = String(parts[1])

            // Extract binary path (first component)
            let argComponents = args.split(separator: " ", omittingEmptySubsequences: true)
            guard let binaryPathComponent = argComponents.first else { continue }
            let binaryPath = String(binaryPathComponent)

            // Only consider actual kanata binaries
            guard binaryPath.hasSuffix("kanata") || binaryPath.contains("/kanata") else { continue }

            // Extract config path from --cfg or -c argument
            let configPath = extractConfigPath(from: args)

            let isKeyPathManaged = keyPathManagedPaths.contains { binaryPath.contains($0) }

            let info = RunningKanataInfo(
                pid: pid,
                configPath: configPath,
                binaryPath: binaryPath,
                isKeyPathManaged: isKeyPathManaged
            )

            if isKeyPathManaged {
                keyPathProcess = info
            } else {
                externalProcess = info
            }
        }

        // Prefer external process (user's own kanata) over KeyPath-managed
        return externalProcess ?? keyPathProcess
    }

    /// Extract config path from kanata command line arguments
    /// Handles both --cfg <path> and -c <path> formats
    private static func extractConfigPath(from args: String) -> String? {
        let patterns = ["--cfg", "-c"]

        for pattern in patterns {
            guard let range = args.range(of: pattern) else { continue }

            let afterPattern = args[range.upperBound...].trimmingCharacters(in: .whitespaces)

            // Handle quoted paths
            if afterPattern.hasPrefix("\"") {
                let withoutQuote = afterPattern.dropFirst()
                if let endQuote = withoutQuote.firstIndex(of: "\"") {
                    return String(withoutQuote[..<endQuote])
                }
            } else if afterPattern.hasPrefix("'") {
                let withoutQuote = afterPattern.dropFirst()
                if let endQuote = withoutQuote.firstIndex(of: "'") {
                    return String(withoutQuote[..<endQuote])
                }
            } else {
                // Unquoted path - take until next space or end
                let path = afterPattern.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
                if let path {
                    return String(path)
                }
            }
        }

        return nil
    }

    /// Common LaunchAgent locations for user-installed Kanata
    public static var userKanataLaunchAgentPaths: [String] {
        let launchAgentsDir = "\(userHomeDirectory)/Library/LaunchAgents"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: launchAgentsDir),
              let contents = try? fileManager.contentsOfDirectory(atPath: launchAgentsDir) else {
            return []
        }

        return contents
            .filter { $0.lowercased().contains("kanata") && $0.hasSuffix(".plist") }
            .map { "\(launchAgentsDir)/\($0)" }
    }
}
