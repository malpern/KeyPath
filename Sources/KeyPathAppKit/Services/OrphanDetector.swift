import AppKit
import Foundation
import KeyPathCore

/// Detects and handles orphaned installations where the app was manually deleted
/// but user data and support files remain
@MainActor
final class OrphanDetector {
    // MARK: - Dependencies

    private let engineFactory: () -> (any InstallerEnginePrivilegedRouting)
    private let brokerFactory: () -> PrivilegeBroker

    // MARK: - Singleton

    static let shared = OrphanDetector()

    init(
        engineFactory: @escaping () -> (any InstallerEnginePrivilegedRouting) = { InstallerEngine() },
        brokerFactory: @escaping () -> PrivilegeBroker = { PrivilegeBroker() }
    ) {
        self.engineFactory = engineFactory
        self.brokerFactory = brokerFactory
    }

    /// User defaults key to track if we've shown the orphan cleanup alert
    private static let hasShownOrphanAlertKey = "HasShownOrphanCleanupAlert"

    /// VHID daemon plist paths
    private static let vhidDaemonPlists = [
        "/Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist",
        "/Library/LaunchDaemons/com.keypath.karabiner-vhidmanager.plist"
    ]

    /// Detects if this is a reinstall after manual deletion (orphaned user data exists)
    func detectOrphanedInstall() -> Bool {
        // Check for leftover files from manual app deletion
        let orphanedPaths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/KeyPath"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/KeyPath"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences")
                .appendingPathComponent("com.keypath.KeyPath.plist")
        ]

        // Count how many orphaned paths exist
        let orphanCount = orphanedPaths.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }.count

        // If 2 or more paths exist, this is likely an orphaned install
        // (config files can legitimately exist from previous install, but
        //  if Application Support AND Logs both exist, that's suspicious)
        return orphanCount >= 2
    }

    /// Detects if orphaned VHID daemon plists exist
    private func detectOrphanedVHIDDaemons() -> Bool {
        Self.vhidDaemonPlists.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Check for orphans and show cleanup alert if needed
    func checkForOrphans() {
        // Don't show the alert more than once
        guard !UserDefaults.standard.bool(forKey: Self.hasShownOrphanAlertKey) else {
            return
        }

        let hasOrphanedFiles = detectOrphanedInstall()
        let hasOrphanedDaemons = detectOrphanedVHIDDaemons()

        guard hasOrphanedFiles || hasOrphanedDaemons else {
            return
        }

        AppLogger.shared.log(
            "🧹 [OrphanDetector] Detected orphaned installation (leftover files from manual deletion)")
        if hasOrphanedFiles {
            AppLogger.shared.log("🧹 [OrphanDetector]   - User data files: YES")
        }
        if hasOrphanedDaemons {
            AppLogger.shared.log("🧹 [OrphanDetector]   - VHID system daemons: YES")
        }

        // Mark as shown so we don't spam the user
        UserDefaults.standard.set(true, forKey: Self.hasShownOrphanAlertKey)

        // Show alert offering to clean up
        showOrphanCleanupAlert(hasFiles: hasOrphanedFiles, hasDaemons: hasOrphanedDaemons)
    }

    private func showOrphanCleanupAlert(hasFiles: Bool, hasDaemons: Bool) {
        let alert = NSAlert()
        alert.messageText = "Leftover Files Detected"

        // Build list of what was found
        var foundItems: [String] = []
        if hasFiles {
            foundItems.append("• Application Support files")
            foundItems.append("• Log files")
            foundItems.append("• Preferences")
        }
        if hasDaemons {
            foundItems.append("• System keyboard services (requires authorization)")
        }

        alert.informativeText = """
        It looks like KeyPath was previously deleted manually (dragged to Trash) instead of using the Uninstall button.

        Some files were left behind:
        \(foundItems.joined(separator: "\n"))

        Would you like to clean these up now?

        Note: Your keyboard configuration will be preserved.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Clean Up Now")
        alert.addButton(withTitle: "Keep Files")
        alert.addButton(withTitle: "Remind Me Later")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn: // Clean Up Now
            AppLogger.shared.log("🧹 [OrphanDetector] User chose to clean up orphaned files")
            Task {
                await performCleanup(cleanFiles: hasFiles, cleanDaemons: hasDaemons)
            }

        case .alertSecondButtonReturn: // Keep Files
            AppLogger.shared.log("🧹 [OrphanDetector] User chose to keep orphaned files")
    // Do nothing, alert won't show again

        case .alertThirdButtonReturn: // Remind Me Later
            AppLogger.shared.log("🧹 [OrphanDetector] User chose 'Remind Me Later'")
            // Reset the flag so we can show the alert again
            UserDefaults.standard.set(false, forKey: Self.hasShownOrphanAlertKey)

        default:
            break
        }
    }

    private func performCleanup(cleanFiles: Bool, cleanDaemons: Bool) async {
        var userFilesCleaned = 0
        var userFilesFailed: [String] = []
        var daemonsCleaned = false
        var daemonsError: String?

        // Clean user files (no privileges needed)
        if cleanFiles {
            let pathsToClean = [
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/KeyPath"),
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/KeyPath"),
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences")
                    .appendingPathComponent("com.keypath.KeyPath.plist")
            ]

            for path in pathsToClean {
                do {
                    if FileManager.default.fileExists(atPath: path.path) {
                        try FileManager.default.removeItem(at: path)
                        userFilesCleaned += 1
                        AppLogger.shared.log("🧹 [OrphanDetector] Removed: \(path.path)")
                    }
                } catch {
                    AppLogger.shared.log("❌ [OrphanDetector] Failed to remove \(path.path): \(error)")
                    userFilesFailed.append(path.lastPathComponent)
                }
            }
        }

        // Clean VHID daemons (requires privileges)
        // Routing via InstallerEngine per AGENTS.md
        if cleanDaemons {
            do {
                AppLogger.shared.log("🧹 [OrphanDetector] Attempting to remove VHID system daemons...")
                let engine = engineFactory()
                let broker = brokerFactory()
                try await engine.uninstallVirtualHIDDrivers(using: broker)
                daemonsCleaned = true
                AppLogger.shared.log("✅ [OrphanDetector] Successfully removed VHID system daemons")
            } catch {
                AppLogger.shared.log("❌ [OrphanDetector] Failed to remove VHID daemons: \(error)")
                daemonsError = error.localizedDescription
            }
        }

        // Show result to user
        await MainActor.run {
            showCleanupResult(
                userFilesCleaned: userFilesCleaned,
                userFilesFailed: userFilesFailed,
                daemonsCleaned: daemonsCleaned,
                daemonsError: daemonsError
            )
        }
    }

    private func showCleanupResult(
        userFilesCleaned: Int,
        userFilesFailed: [String],
        daemonsCleaned: Bool,
        daemonsError: String?
    ) {
        let resultAlert = NSAlert()

        let hasUserFileFailures = !userFilesFailed.isEmpty
        let hasDaemonFailure = daemonsError != nil
        let allSuccess = !hasUserFileFailures && !hasDaemonFailure

        if allSuccess {
            resultAlert.messageText = "Cleanup Complete"
            var details: [String] = []
            if userFilesCleaned > 0 {
                details.append("Removed \(userFilesCleaned) user file(s)")
            }
            if daemonsCleaned {
                details.append("Removed system keyboard services")
            }
            resultAlert.informativeText = details.joined(separator: "\n")
            resultAlert.alertStyle = .informational
        } else {
            resultAlert.messageText = "Cleanup Partially Complete"
            var details: [String] = []

            if userFilesCleaned > 0 {
                details.append("✅ Removed \(userFilesCleaned) user file(s)")
            }
            if !userFilesFailed.isEmpty {
                details.append("❌ Failed to remove:")
                details.append(contentsOf: userFilesFailed.map { "  • \($0)" })
            }
            if daemonsCleaned {
                details.append("✅ Removed system keyboard services")
            }
            if let error = daemonsError {
                details.append("❌ Failed to remove system services:")
                details.append("  \(error)")
            }

            details.append("")
            details.append("You may need to remove failed items manually.")

            resultAlert.informativeText = details.joined(separator: "\n")
            resultAlert.alertStyle = .warning
        }
        resultAlert.runModal()
    }
}
