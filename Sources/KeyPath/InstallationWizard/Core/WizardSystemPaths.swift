import Foundation

/// System paths and configuration constants for the Installation Wizard
/// Centralizes hardcoded paths to improve maintainability and testing
enum WizardSystemPaths {
  // MARK: - Binary Paths

  /// Primary kanata binary location (ARM Macs)
  static let kanataBinaryARM = "/opt/homebrew/bin/kanata"

  /// Fallback kanata binary location (Intel Macs)
  static let kanataBinaryIntel = "/usr/local/bin/kanata"

  /// Default kanata binary path for most operations
  static let kanataBinaryDefault = "/usr/local/bin/kanata"

  /// Homebrew binary path
  static let brewBinary = "/opt/homebrew/bin/brew"

  // MARK: - Configuration Paths

  /// User configuration file path
  static var userConfigPath: String {
    return "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
  }

  /// System configuration directory
  static let systemConfigDirectory = "/usr/local/etc/kanata"

  /// System configuration file path
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

  /// Login Items settings URL (macOS 13+)
  static let loginItemsSettings =
    "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

  // MARK: - Helper Methods

  /// Returns the best available kanata binary path
  static func detectKanataBinaryPath() -> String? {
    let candidatePaths = [kanataBinaryARM, kanataBinaryIntel, kanataBinaryDefault]

    for path in candidatePaths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    return nil
  }

  /// Checks if the user config file exists
  static var userConfigExists: Bool {
    return FileManager.default.fileExists(atPath: userConfigPath)
  }

  /// Checks if the system config directory exists
  static var systemConfigDirectoryExists: Bool {
    return FileManager.default.fileExists(atPath: systemConfigDirectory)
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
