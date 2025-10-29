import Foundation

/// System paths and configuration constants for the Installation Wizard
/// Centralizes hardcoded paths to improve maintainability and testing
enum WizardSystemPaths {
    // MARK: - Binary Paths

    /// System-installed kanata binary location (avoids Gatekeeper issues)
    /// This is where the LaunchDaemon installer copies the bundled binary
    static let kanataSystemInstallPath = "/Library/KeyPath/bin/kanata"

    /// Standard kanata binary location - used for both homebrew and experimental versions
    /// Using a single standard location simplifies permission management
    static let kanataStandardLocation = "/usr/local/bin/kanata"

    /// Primary kanata binary location (ARM Macs with Homebrew)
    static let kanataBinaryARM = "/opt/homebrew/bin/kanata"

    /// Default kanata binary path for most operations (same as standard)
    static let kanataBinaryDefault = "/usr/local/bin/kanata"

    /// Bundled kanata binary path (preferred - properly signed)
    static var bundledKanataPath: String {
        "\(Bundle.main.bundlePath)/Contents/Library/KeyPath/kanata"
    }

    /// Active kanata binary path - uses simple filesystem checks for performance
    /// Single canonical path eliminates TCC permission fragmentation
    static var kanataActiveBinary: String {
        // Use system install path if it exists (for LaunchDaemon)
        // Otherwise use bundled path (for UI/detection)
        if FileManager.default.fileExists(atPath: kanataSystemInstallPath) {
            return kanataSystemInstallPath
        }
        return bundledKanataPath
    }

    /// All known kanata binary paths for detection/filtering
    static func allKnownKanataPaths() -> [String] {
        [kanataSystemInstallPath, bundledKanataPath].filter {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    /// Homebrew binary path
    static let brewBinary = "/opt/homebrew/bin/brew"

    // MARK: - Configuration Paths

    /// User configuration file path following industry standard ~/.config/ pattern
    static var userConfigPath: String {
        "\(NSHomeDirectory())/.config/keypath/keypath.kbd"
    }

    /// User configuration directory
    static var userConfigDirectory: String {
        "\(NSHomeDirectory())/.config/keypath"
    }

    /// Legacy system configuration directory (no longer used)
    static let systemConfigDirectory = "/usr/local/etc/kanata"

    /// Legacy system configuration file path (no longer used)
    static let systemConfigPath = "/usr/local/etc/kanata/keypath.kbd"

    // MARK: - Log Files

    /// Main kanata log file
    static let kanataLogFile = "/var/log/kanata.log"

    /// System log directory
    static let systemLogDirectory = "/var/log"

    // MARK: - Service Paths

    /// LaunchDaemon plist file
    static let launchDaemonPlist = "/Library/LaunchDaemons/com.keypath.kanata.plist"

    /// LaunchDaemon service identifier
    static let launchDaemonIdentifier = "com.keypath.kanata"

    // MARK: - Karabiner Paths

    /// Karabiner-Elements VirtualHIDDevice path
    static let karabinerVHIDDevice =
        "/Applications/Karabiner-Elements.app/Contents/Library/bin/karabiner_grabber"

    /// Karabiner-Elements daemon path
    static let karabinerDaemon =
        "/Library/Application Support/org.pqrs.Karabiner-Elements/bin/karabiner_session_monitor"

    // MARK: - System Preference URLs

    /// Privacy & Security settings URL
    static let privacySecuritySettings = "x-apple.systempreferences:com.apple.preference.security"

    /// Input Monitoring settings URL
    static let inputMonitoringSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    /// Accessibility settings URL
    static let accessibilitySettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Full Disk Access settings URL (needed to read TCC.db for kanata detection)
    static let fullDiskAccessSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Login Items settings URL (macOS 13+)
    static let loginItemsSettings =
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    // MARK: - Helper Methods

    /// Returns the best available kanata binary path - simple filesystem check for performance
    static func detectKanataBinaryPath() -> String? {
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
    static var userConfigExists: Bool {
        FileManager.default.fileExists(atPath: userConfigPath)
    }

    /// Checks if the system config directory exists
    static var systemConfigDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: systemConfigDirectory)
    }

    /// Creates a display path for user interfaces (uses ~ for home directory)
    static func displayPath(for fullPath: String) -> String {
        let homeDirectory = NSHomeDirectory()
        if fullPath.hasPrefix(homeDirectory) {
            return fullPath.replacingOccurrences(of: homeDirectory, with: "~")
        }
        return fullPath
    }
}
