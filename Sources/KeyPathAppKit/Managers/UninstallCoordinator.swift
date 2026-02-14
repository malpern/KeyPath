import AppKit
import Foundation
import KeyPathCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class UninstallCoordinator {
    private(set) var logLines: [String] = []
    private(set) var isRunning = false
    private(set) var didSucceed = false
    private(set) var lastError: String?

    @ObservationIgnored private let resolveUninstallerURLClosure: () -> URL?
    @ObservationIgnored private let runWithAdminPrivilegesClosure: (URL, Bool) async -> AppleScriptResult

    init(
        resolveUninstallerURL: @escaping () -> URL?,
        runWithAdminPrivileges: @escaping (URL, Bool) async -> AppleScriptResult
    ) {
        resolveUninstallerURLClosure = resolveUninstallerURL
        runWithAdminPrivilegesClosure = runWithAdminPrivileges
    }

    convenience init() {
        self.init(
            resolveUninstallerURL: Self.defaultResolveUninstallerURL,
            runWithAdminPrivileges: Self.defaultRunWithAdminPrivileges
        )
    }

    @discardableResult
    func uninstall(deleteConfig: Bool = false) async -> Bool {
        guard !isRunning else { return false }

        isRunning = true
        didSucceed = false
        lastError = nil
        logLines = ["🗑️ Starting KeyPath uninstall..."]

        defer { isRunning = false }

        // IMPORTANT: Unregister SMAppService daemons BEFORE helper/script cleanup
        // This clears the internal registration database that helper/script can't access
        await unregisterSMAppServiceDaemons()

        // Try to use the privileged helper first (no password prompt needed)
        if await tryUninstallViaHelper(deleteConfig: deleteConfig) {
            didSucceed = true
            await resetForTestingIfEnabled()
            logLines.append("✅ Uninstall completed")
            return true
        }

        // Fall back to script-based uninstall if helper isn't available
        logLines.append("⚠️ Helper not available, falling back to admin prompt...")
        return await uninstallViaScript(deleteConfig: deleteConfig)
    }

    /// Try to uninstall using the privileged helper (no password prompt)
    /// Returns true if successful, false if helper isn't available or fails
    private func tryUninstallViaHelper(deleteConfig: Bool) async -> Bool {
        let helper = HelperManager.shared

        // Check if helper is installed and functional
        guard await helper.isHelperInstalled() else {
            logLines.append("ℹ️ Privileged helper not installed")
            return false
        }

        guard await helper.testHelperFunctionality() else {
            logLines.append("ℹ️ Privileged helper not responding")
            return false
        }

        logLines.append("🔧 Using privileged helper for uninstall...")
        if deleteConfig {
            logLines.append("🗑️ User configuration will be deleted")
        } else {
            logLines.append("💾 User configuration will be preserved")
        }

        do {
            try await helper.uninstallKeyPath(deleteConfig: deleteConfig)
            logLines.append("✅ Services and files removed via helper")
            return true
        } catch {
            logLines.append("❌ Helper uninstall failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Fallback uninstall using the shell script with admin privileges
    private func uninstallViaScript(deleteConfig: Bool) async -> Bool {
        guard let scriptURL = resolveUninstallerURLClosure() else {
            let message = "Uninstaller script wasn't found in this build."
            logLines.append("❌ \(message)")
            lastError = message
            return false
        }

        logLines.append("📄 Using uninstaller at: \(scriptURL.path)")
        if deleteConfig {
            logLines.append("🗑️ User configuration will be deleted")
        } else {
            logLines.append("💾 User configuration will be preserved")
        }

        let result = await runWithAdminPrivilegesClosure(scriptURL, deleteConfig)

        if result.success {
            didSucceed = true
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                logLines.append(contentsOf: output.components(separatedBy: "\n"))
            }
            await resetForTestingIfEnabled()
            logLines.append("✅ Uninstall completed")
        } else {
            let trimmed = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logLines.append("❌ \(trimmed)")
                lastError = trimmed
            } else {
                logLines.append("❌ Uninstall failed (error code \(result.exitStatus))")
                lastError = "Uninstall failed with exit code \(result.exitStatus)"
            }
        }

        return result.success
    }

    func copyTerminalCommand() {
        guard let scriptURL = resolveUninstallerURLClosure() else { return }
        let command = "sudo \"\(scriptURL.path)\""
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        logLines.append("📋 Copied command: \(command)")
    }

    func revealUninstallerInFinder() {
        guard let scriptURL = resolveUninstallerURLClosure() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([scriptURL])
    }

    // MARK: - Testing Reset

    /// Reset TCC permissions and preferences for fresh install testing.
    /// Only runs when FeatureFlags.uninstallForTesting is enabled.
    private func resetForTestingIfEnabled() async {
        guard FeatureFlags.uninstallForTesting else {
            logLines.append("ℹ️ TCC reset skipped (uninstallForTesting disabled)")
            return
        }

        logLines.append("🧪 Resetting for fresh install testing...")

        let bundleId = "com.keypath.KeyPath"
        let kanataBinary = "/Library/KeyPath/bin/kanata"

        // Reset TCC permissions (these don't require admin)
        let tccResets: [(service: String, target: String)] = [
            ("Accessibility", bundleId),
            ("ListenEvent", bundleId), // Input Monitoring
            ("ListenEvent", kanataBinary), // Input Monitoring for kanata
            ("SystemPolicyAllFiles", bundleId) // Full Disk Access
        ]

        for (service, target) in tccResets {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, target]

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    logLines.append("  ✓ Reset \(service) for \(target)")
                } else {
                    logLines.append("  ⚠️ Failed to reset \(service) for \(target)")
                }
            } catch {
                logLines.append("  ⚠️ tccutil error: \(error.localizedDescription)")
            }
        }

        // Clear UserDefaults
        let defaultsProcess = Process()
        defaultsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaultsProcess.arguments = ["delete", bundleId]

        do {
            try defaultsProcess.run()
            defaultsProcess.waitUntilExit()
            if defaultsProcess.terminationStatus == 0 {
                logLines.append("  ✓ Cleared UserDefaults")
            } else {
                logLines.append("  ⚠️ No UserDefaults to clear (or already cleared)")
            }
        } catch {
            logLines.append("  ⚠️ defaults error: \(error.localizedDescription)")
        }

        logLines.append("🧪 Testing reset complete")
    }

    // MARK: - SMAppService Cleanup

    /// Unregister all KeyPath daemons via SMAppService API before helper/script cleanup.
    /// This is necessary because helper and shell script can only use launchctl/rm,
    /// which leaves stale entries in SMAppService's internal registration database.
    private func unregisterSMAppServiceDaemons() async {
        let daemonPlists = [
            "com.keypath.kanata.plist"
            // Note: Karabiner VirtualHID daemons are managed separately and don't use SMAppService
        ]

        for plistName in daemonPlists {
            let service = SMAppService.daemon(plistName: plistName)
            guard service.status == .enabled else {
                logLines.append("ℹ️ SMAppService \(plistName): not registered, skipping")
                continue
            }

            do {
                try await service.unregister()
                logLines.append("✅ SMAppService \(plistName): unregistered")
            } catch {
                // Log but continue - the helper/script will still clean up files
                logLines.append("⚠️ SMAppService \(plistName): unregister failed - \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func defaultResolveUninstallerURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "uninstall", withExtension: "sh") {
            return bundled
        }

        let repoPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/KeyPath/Resources/uninstall.sh")
        if FileManager.default.isExecutableFile(atPath: repoPath.path) {
            return repoPath
        }

        return nil
    }

    private static func defaultRunWithAdminPrivileges(scriptURL: URL, deleteConfig: Bool) async
        -> AppleScriptResult
    {
        // Use PrivilegedCommandRunner which respects TestEnvironment.useSudoForPrivilegedOps
        let configFlag = deleteConfig ? " --delete-config" : ""
        let command = "KEYPATH_UNINSTALL_ASSUME_YES=1 '\(scriptURL.path)' --assume-yes\(configFlag)"
        let result = PrivilegedCommandRunner.execute(
            command: command,
            prompt: "KeyPath needs to uninstall system services."
        )
        return AppleScriptResult(
            success: result.success,
            output: result.output,
            error: result.success ? "" : result.output,
            exitStatus: result.exitCode
        )
    }

    private static func escapeForAppleScript(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct AppleScriptResult {
    let success: Bool
    let output: String
    let error: String
    let exitStatus: Int32
}

// NOTE: AppleScriptRunner was removed - now using PrivilegedCommandRunner which respects
// TestEnvironment.useSudoForPrivilegedOps for sudo-based execution in test environments.
