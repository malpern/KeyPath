import AppKit
import Foundation

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

    /// Check if LaunchAgent is installed
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: agentPlistPath)
    }

    /// Check if LaunchAgent is loaded
    static func isLoaded() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", agentIdentifier]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            AppLogger.shared.log("❌ [LaunchAgent] Failed to check load status: \(error)")
            return false
        }
    }

    /// Check if LaunchAgent is running
    static func isRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "gui/\(getuid())/\(agentIdentifier)"]

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
            AppLogger.shared.log("❌ [LaunchAgent] Failed to check running status: \(error)")
        }

        return false
    }

    // MARK: - LaunchAgent Management

    /// Install LaunchAgent plist
    static func install() throws {
        AppLogger.shared.log("📝 [LaunchAgent] Installing LaunchAgent...")

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

        AppLogger.shared.log("✅ [LaunchAgent] LaunchAgent installed at \(agentPlistPath)")
    }

    /// Load LaunchAgent
    static func load() throws {
        AppLogger.shared.log("🚀 [LaunchAgent] Loading LaunchAgent...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", agentPlistPath]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw KeyPathError.process(.startFailed(reason: "Failed to load LaunchAgent"))
        }

        AppLogger.shared.log("✅ [LaunchAgent] LaunchAgent loaded")
    }

    /// Unload LaunchAgent
    static func unload() throws {
        AppLogger.shared.log("🛑 [LaunchAgent] Unloading LaunchAgent...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", agentPlistPath]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw KeyPathError.process(.stopFailed(underlyingError: "Failed to unload LaunchAgent"))
        }

        AppLogger.shared.log("✅ [LaunchAgent] LaunchAgent unloaded")
    }

    /// Remove LaunchAgent plist
    static func uninstall() throws {
        AppLogger.shared.log("🗑️ [LaunchAgent] Uninstalling LaunchAgent...")

        // Unload first if loaded
        if isLoaded() {
            try unload()
        }

        // Remove plist file
        if FileManager.default.fileExists(atPath: agentPlistPath) {
            try FileManager.default.removeItem(atPath: agentPlistPath)
        }

        AppLogger.shared.log("✅ [LaunchAgent] LaunchAgent uninstalled")
    }

    /// Enable LaunchAgent (install and load)
    static func enable() async throws {
        // Install if not already installed
        if !isInstalled() {
            try install()
        }

        // Load if not already loaded
        if !isLoaded() {
            try load()
        }

        AppLogger.shared.log("✅ [LaunchAgent] LaunchAgent enabled")
    }

    /// Disable LaunchAgent (unload but keep installed)
    static func disable() async throws {
        if isLoaded() {
            try unload()
        }

        AppLogger.shared.log("✅ [LaunchAgent] LaunchAgent disabled")
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

/// LaunchAgent operation errors
///
/// - Deprecated: Use `KeyPathError.process(...)` instead for consistent error handling
@available(*, deprecated, message: "Use KeyPathError.process(...) instead")
enum LaunchAgentError: LocalizedError {
    case loadFailed
    case unloadFailed
    case notInstalled
    case alreadyLoaded

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            "Failed to load LaunchAgent"
        case .unloadFailed:
            "Failed to unload LaunchAgent"
        case .notInstalled:
            "LaunchAgent is not installed"
        case .alreadyLoaded:
            "LaunchAgent is already loaded"
        }
    }

    /// Convert to KeyPathError for consistent error handling
    var asKeyPathError: KeyPathError {
        switch self {
        case .loadFailed:
            return .process(.startFailed(reason: "Failed to load LaunchAgent"))
        case .unloadFailed:
            return .process(.stopFailed(underlyingError: "Failed to unload LaunchAgent"))
        case .notInstalled:
            return .process(.notRunning)
        case .alreadyLoaded:
            return .process(.alreadyRunning)
        }
    }
}
