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

    /// Checks if the user config file exists
    public static var userConfigExists: Bool {
        FileManager.default.fileExists(atPath: userConfigPath)
    }

    /// Checks if the system config directory exists
    public static var systemConfigDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: systemConfigDirectory)
    }

    /// Creates a display path for user interfaces (uses ~ for home directory)
    public static func displayPath(for fullPath: String) -> String {
        let homeDirectory = userHomeDirectory
        if fullPath.hasPrefix(homeDirectory) {
            return fullPath.replacingOccurrences(of: homeDirectory, with: "~")
        }
        return fullPath
    }
}
