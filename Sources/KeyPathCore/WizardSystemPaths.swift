import Foundation

/// System paths and configuration constants for the Installation Wizard
/// Centralizes hardcoded paths to improve maintainability and testing
public enum WizardSystemPaths {
    // MARK: - Test Overrides

    /// Test-only overrides below are read in debug builds only: in a release
    /// build, an environment variable must not change which paths KeyPath
    /// inspects or removes, or which binary it runs.
    private static func currentTestRoot() -> String? {
        #if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["KEYPATH_TEST_ROOT"],
                  !raw.isEmpty
            else {
                return nil
            }
            if raw.hasSuffix("/") {
                return String(raw.dropLast())
            }
            return raw
        #else
            return nil
        #endif
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
        #if DEBUG
            if let override = ProcessInfo.processInfo.environment["KEYPATH_HOME_DIR_OVERRIDE"],
               !override.isEmpty
            {
                return override
            }
        #endif
        return NSHomeDirectory()
    }

    public static var userHomeDirectory: String {
        resolvedHomeDirectory()
    }

    // MARK: - Binary Paths

    #if DEBUG
        private nonisolated(unsafe) static var bundledKanataPathOverride: String?

        public static func setBundledKanataPathOverride(_ path: String?) {
            bundledKanataPathOverride = path
        }
    #endif

    /// Bundled kanata binary path (preferred - properly signed)
    public static var bundledKanataPath: String {
        #if DEBUG
            if let override = bundledKanataPathOverride, !override.isEmpty {
                return override
            }
            if let override = ProcessInfo.processInfo.environment["KEYPATH_BUNDLED_KANATA_OVERRIDE"],
               !override.isEmpty
            {
                return override
            }
        #endif
        return currentRuntimeHost().bundledCorePath
    }

    /// Bundled kanata simulator binary path (for dry-run simulation)
    /// This binary outputs structured JSON instead of sending real HID events
    public static var bundledSimulatorPath: String {
        #if DEBUG
            if let override = ProcessInfo.processInfo.environment["KEYPATH_BUNDLED_SIMULATOR_OVERRIDE"],
               !override.isEmpty
            {
                return override
            }
        #endif
        return "\(Bundle.main.bundlePath)/Contents/Library/KeyPath/kanata-simulator"
    }

    /// Path to the Kanata Engine.app bundle wrapping the kanata binary.
    /// Reveal this in Finder when the user needs to add kanata to System Settings.
    public static var kanataEngineBundlePath: String {
        currentRuntimeHost().kanataEngineBundlePath
    }

    /// Bundle identifier for the Kanata Engine.app wrapper.
    public static let kanataEngineBundleID = KeyPathConstants.Bundle.kanataEngineBundleID

    /// Active kanata binary path - uses simple filesystem checks for performance
    /// Single canonical path eliminates TCC permission fragmentation
    public static var kanataActiveBinary: String {
        currentRuntimeHost().preferredCoreBinaryPath()
    }

    /// All known kanata binary paths for detection/filtering.
    /// Includes bundled path and legacy system path (kept for migration-period process detection).
    public static func allKnownKanataPaths() -> [String] {
        let runtimeHost = currentRuntimeHost()
        // Legacy path kept for migration-period process detection
        return [runtimeHost.bundledCorePath, legacySystemBinaryPath].filter {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    private static func currentRuntimeHost() -> KanataRuntimeHost {
        KanataRuntimeHost.current(bundlePath: Bundle.main.bundlePath)
    }

    // MARK: - Configuration Paths

    /// User configuration file path following industry standard ~/.config/ pattern
    public static var userConfigPath: String {
        "\(userConfigDirectory)/keypath.kbd"
    }

    /// User configuration directory
    public static var userConfigDirectory: String {
        userConfigDirectory(in: userHomeDirectory)
    }

    private static func userConfigDirectory(in homeDirectory: String) -> String {
        "\(homeDirectory)/.config/keypath"
    }

    /// Legacy system configuration directory (no longer used)
    public static var systemConfigDirectory: String {
        remapSystemPath("/usr/local/etc/kanata")
    }

    // MARK: - Karabiner Paths

    /// Karabiner-Elements user configuration file
    public static var karabinerConfigPath: String {
        "\(userHomeDirectory)/.config/karabiner/karabiner.json"
    }

    /// Whether a Karabiner config file exists at the default location
    public static var karabinerConfigExists: Bool {
        FileManager.default.fileExists(atPath: karabinerConfigPath)
    }

    // MARK: - System Preference URLs

    /// Accessibility settings URL
    public static let accessibilitySettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    // MARK: - Helper Methods

    /// Legacy system binary path from pre-bundled installations.
    /// Kept for migration-period fallback, consistent with PermissionOracle.
    public static var legacySystemBinaryPath: String {
        remapSystemPath("/Library/KeyPath/bin/kanata")
    }

    // MARK: - Kanata Migration Detection

    /// Common Kanata config file names to search for
    public static var commonKanataConfigNames: [String] {
        ["kanata.kbd", "config.kbd", "keypath.kbd"]
    }

    /// Common directories where users store Kanata configs
    public static var commonKanataConfigDirectories: [String] {
        kanataConfigDirectories(homeDirectory: userHomeDirectory, systemConfigDirectory: systemConfigDirectory)
    }

    private static func kanataConfigDirectories(homeDirectory: String, systemConfigDirectory: String) -> [String] {
        [
            "\(homeDirectory)/.config/kanata",
            userConfigDirectory(in: homeDirectory),
            homeDirectory,
            systemConfigDirectory
        ]
    }

    /// Detect existing Kanata config files in common locations
    /// Returns array of (path, displayName) tuples for found configs
    public static func detectExistingKanataConfigs() -> [(path: String, displayName: String)] {
        detectExistingKanataConfigs(homeDirectory: userHomeDirectory, systemConfigDirectory: systemConfigDirectory)
    }

    package static func detectExistingKanataConfigs(
        homeDirectory: String,
        systemConfigDirectory: String
    ) -> [(path: String, displayName: String)] {
        var foundConfigs: [(path: String, displayName: String)] = []
        let fileManager = FileManager.default
        let keyPathConfigPath = "\(userConfigDirectory(in: homeDirectory))/keypath.kbd"
        let directories = kanataConfigDirectories(
            homeDirectory: homeDirectory,
            systemConfigDirectory: systemConfigDirectory
        )

        for directory in directories {
            guard fileManager.fileExists(atPath: directory) else { continue }

            for configName in commonKanataConfigNames {
                let fullPath = "\(directory)/\(configName)"
                if fileManager.fileExists(atPath: fullPath) {
                    // Skip if it's already KeyPath's expected location
                    if fullPath == keyPathConfigPath {
                        continue
                    }
                    let displayName = displayPath(for: fullPath, homeDirectory: homeDirectory)
                    foundConfigs.append((path: fullPath, displayName: displayName))
                }
            }
        }

        // Also check for configs directly in home directory (e.g., ~/.kanata.kbd)
        for configName in commonKanataConfigNames {
            let homeConfigPath = "\(homeDirectory)/.\(configName)"
            if fileManager.fileExists(atPath: homeConfigPath) {
                let displayName = displayPath(for: homeConfigPath, homeDirectory: homeDirectory)
                foundConfigs.append((path: homeConfigPath, displayName: displayName))
            }
        }

        return foundConfigs
    }

    /// Legacy KeyPath config directory (Application Support).
    ///
    /// KeyPath's canonical user-owned config directory is `~/.config/keypath`.
    public static var keyPathConfigDirectory: String {
        "\(userHomeDirectory)/Library/Application Support/KeyPath"
    }

    /// Legacy KeyPath config path (Application Support).
    public static var keyPathConfigPath: String {
        "\(keyPathConfigDirectory)/keypath.kbd"
    }

    /// Creates a display path for user interfaces (uses ~ for home directory)
    public static func displayPath(for fullPath: String) -> String {
        displayPath(for: fullPath, homeDirectory: userHomeDirectory)
    }

    private static func displayPath(for fullPath: String, homeDirectory: String) -> String {
        if fullPath.hasPrefix(homeDirectory) {
            return fullPath.replacingOccurrences(of: homeDirectory, with: "~")
        }
        return fullPath
    }

    // MARK: - Running Kanata Process Detection

    /// Information about a running Kanata process
    public struct RunningKanataInfo: Sendable {
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
        } catch {
            return nil
        }
        // Read before waiting: `ps -eo pid,args` often exceeds the 64 KB pipe
        // buffer, and ps then blocks until it is read, so waiting first hung.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Known KeyPath-managed binary paths
        let keyPathManagedPaths = [
            bundledKanataPath,
            legacySystemBinaryPath
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
              let contents = try? fileManager.contentsOfDirectory(atPath: launchAgentsDir)
        else {
            return []
        }

        return contents
            .filter { $0.lowercased().contains("kanata") && $0.hasSuffix(".plist") }
            .map { "\(launchAgentsDir)/\($0)" }
    }
}
