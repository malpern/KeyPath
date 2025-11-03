import AppKit
import Foundation
import KeyPathCore

/// Manages LaunchAgent for KeyPath to ensure proper lifecycle management
/// LaunchAgent starts KeyPath in headless mode, which then manages kanata subprocess
/// This ensures proper cleanup on logout/shutdown
@MainActor
final class LaunchAgentManager {
  // MARK: - Constants

  static let agentIdentifier = "com.keypath.agent"
  static let agentPlistName = "\(agentIdentifier).plist"

  static var agentPlistPath: String {
    "\(NSHomeDirectory())/Library/LaunchAgents/\(agentPlistName)"
  }

  static var appBundlePath: String {
    Bundle.main.bundlePath
  }

  static var executablePath: String {
    Bundle.main.executablePath ?? "\(appBundlePath)/Contents/MacOS/KeyPath"
  }

  // MARK: - LaunchAgent Status

  /// Get the full domain path for this LaunchAgent
  private static var domainPath: String {
    "gui/\(getuid())/\(agentIdentifier)"
  }

  /// Get launchctl executable path (with fallback)
  private static var launchctlPath: String {
    // Try /usr/bin/launchctl first (modern macOS), fallback to /bin/launchctl
    let modernPath = "/usr/bin/launchctl"
    if FileManager.default.fileExists(atPath: modernPath) {
      return modernPath
    }
    return "/bin/launchctl"
  }

  /// Check if LaunchAgent is installed
  static func isInstalled() -> Bool {
    FileManager.default.fileExists(atPath: agentPlistPath)
  }

  /// Check if LaunchAgent is loaded (using modern bootstrap API)
  static func isLoaded() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchctlPath)
    task.arguments = ["print", domainPath]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()
      return task.terminationStatus == 0
    } catch {
      AppLogger.shared.error("[LaunchAgent] Failed to check load status: \(error)")
      return false
    }
  }

  /// Check if LaunchAgent is running
  static func isRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchctlPath)
    task.arguments = ["print", domainPath]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus == 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("state = running")
      }
    } catch {
      AppLogger.shared.error("[LaunchAgent] Failed to check running status: \(error)")
    }

    return false
  }

  // MARK: - LaunchAgent Management

  /// Install LaunchAgent plist
  static func install() throws {
    AppLogger.shared.info("[LaunchAgent] Installing LaunchAgent...")

    // Create LaunchAgents directory if it doesn't exist
    let launchAgentsDir = (agentPlistPath as NSString).deletingLastPathComponent
    if !FileManager.default.fileExists(atPath: launchAgentsDir) {
      try FileManager.default.createDirectory(
        atPath: launchAgentsDir,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }

    // Create plist content
    let plistContent = createPlistContent()

    // Write plist file
    try plistContent.write(
      to: URL(fileURLWithPath: agentPlistPath), atomically: true, encoding: .utf8
    )

    // Set proper permissions
    let attributes = [FileAttributeKey.posixPermissions: 0o644]
    try FileManager.default.setAttributes(attributes, ofItemAtPath: agentPlistPath)

    AppLogger.shared.info("[LaunchAgent] LaunchAgent installed at \(agentPlistPath)")
  }

  /// Bootstrap LaunchAgent (modern API, replaces load)
  static func load() throws {
    AppLogger.shared.info("[LaunchAgent] Bootstrapping LaunchAgent...")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchctlPath)
    task.arguments = ["bootstrap", "gui/\(getuid())", agentPlistPath]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    try task.run()
    task.waitUntilExit()

    if task.terminationStatus != 0 {
      let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"

      // Ignore "service already bootstrapped" error (that's fine)
      if errorOutput.contains("already bootstrapped") || errorOutput.contains("already loaded") {
        AppLogger.shared.debug("[LaunchAgent] Already bootstrapped (this is fine)")
        return
      }

      AppLogger.shared.error("[LaunchAgent] Bootstrap failed: \(errorOutput)")
      throw KeyPathError.process(
        .startFailed(reason: "Failed to bootstrap LaunchAgent: \(errorOutput)"))
    }

    AppLogger.shared.info("[LaunchAgent] LaunchAgent bootstrapped")
  }

  /// Bootout LaunchAgent (modern API, replaces unload)
  static func unload() throws {
    AppLogger.shared.info("[LaunchAgent] Booting out LaunchAgent...")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: launchctlPath)
    task.arguments = ["bootout", domainPath]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    try task.run()
    task.waitUntilExit()

    if task.terminationStatus != 0 {
      let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"

      // Ignore "no such service" error (that's fine, means it's already unloaded)
      if errorOutput.contains("no such service") || errorOutput.contains("Could not find service") {
        AppLogger.shared.debug("[LaunchAgent] Already booted out (this is fine)")
        return
      }

      AppLogger.shared.error("[LaunchAgent] Bootout failed: \(errorOutput)")
      throw KeyPathError.process(
        .stopFailed(underlyingError: "Failed to bootout LaunchAgent: \(errorOutput)"))
    }

    AppLogger.shared.info("[LaunchAgent] LaunchAgent booted out")
  }

  /// Remove LaunchAgent plist
  static func uninstall() throws {
    AppLogger.shared.info("[LaunchAgent] Uninstalling LaunchAgent...")

    // Bootout first if loaded
    if isLoaded() {
      try unload()
    }

    // Remove plist file
    if FileManager.default.fileExists(atPath: agentPlistPath) {
      try FileManager.default.removeItem(atPath: agentPlistPath)
    }

    AppLogger.shared.info("[LaunchAgent] LaunchAgent uninstalled")
  }

  /// Enable LaunchAgent (install and bootstrap)
  static func enable() async throws {
    // Install if not already installed
    if !isInstalled() {
      try install()
    }

    // Bootstrap if not already bootstrapped
    if !isLoaded() {
      try load()
    }

    AppLogger.shared.info("[LaunchAgent] LaunchAgent enabled")
  }

  /// Disable LaunchAgent (bootout but keep installed)
  static func disable() async throws {
    if isLoaded() {
      try unload()
    }

    AppLogger.shared.info("[LaunchAgent] LaunchAgent disabled")
  }

  // MARK: - Private Helpers

  /// Create LaunchAgent plist content
  private static func createPlistContent() -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(agentIdentifier)</string>

        <key>ProgramArguments</key>
        <array>
            <string>\(executablePath)</string>
            <string>--headless</string>
        </array>

        <key>RunAtLoad</key>
        <true/>

        <key>KeepAlive</key>
        <dict>
            <key>SuccessfulExit</key>
            <false/>
            <key>Crashed</key>
            <true/>
        </dict>

        <key>ProcessType</key>
        <string>Background</string>

        <key>StandardOutPath</key>
        <string>/tmp/keypath-agent.log</string>

        <key>StandardErrorPath</key>
        <string>/tmp/keypath-agent.error.log</string>

        <key>WorkingDirectory</key>
        <string>\(NSHomeDirectory())</string>

        <key>EnvironmentVariables</key>
        <dict>
            <key>KEYPATH_HEADLESS</key>
            <string>1</string>
        </dict>

        <key>ThrottleInterval</key>
        <integer>10</integer>
    </dict>
    </plist>
    """
  }
}

// MARK: - Error Types

// (Removed deprecated LaunchAgentError - now using KeyPathError directly)
