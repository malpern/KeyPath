import AppKit
import Foundation
import KeyPathCore
import KeyPathInstallationWizard

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
            Foundation.FileManager().homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/KeyPath"),
            Foundation.FileManager().homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/KeyPath"),
            Foundation.FileManager().homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences")
                .appendingPathComponent("com.keypath.KeyPath.plist")
        ]

        // Count how many orphaned paths exist
        let orphanCount = orphanedPaths.filter {
            Foundation.FileManager().fileExists(atPath: $0.path)
        }.count

        // If 2 or more paths exist, this is likely an orphaned install
        // (config files can legitimately exist from previous install, but
        //  if Application Support AND Logs both exist, that's suspicious)
        return orphanCount >= 2
    }

    /// Detects if orphaned VHID daemon plists exist
    private func detectOrphanedVHIDDaemons() -> Bool {
        Self.vhidDaemonPlists.contains { Foundation.FileManager().fileExists(atPath: $0) }
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
            "🧹 [OrphanDetector] Detected orphaned installation (leftover files from manual deletion)"
        )
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
        var userFilesFailed: [(name: String, reason: String)] = []
        var deferredForNextUninstall = false
        var daemonsCleaned = false
        var daemonsError: String?

        // Clean user files (no privileges needed)
        // Note: Application Support can't be removed while the app is running —
        // it's silently deferred to next uninstall rather than shown as a failure.
        if cleanFiles {
            let pathsToClean: [(url: URL, canCleanWhileRunning: Bool)] = [
                (Foundation.FileManager().homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/KeyPath"), false),
                (Foundation.FileManager().homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/KeyPath"), true),
                (Foundation.FileManager().homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences")
                    .appendingPathComponent("com.keypath.KeyPath.plist"), true)
            ]

            for (path, canCleanWhileRunning) in pathsToClean {
                guard Foundation.FileManager().fileExists(atPath: path.path) else { continue }

                if !canCleanWhileRunning {
                    AppLogger.shared.log("⏭️ [OrphanDetector] Deferring \(path.lastPathComponent) - will be cleaned on next uninstall")
                    deferredForNextUninstall = true
                    continue
                }

                do {
                    try Foundation.FileManager().removeItem(at: path)
                    userFilesCleaned += 1
                    AppLogger.shared.log("🧹 [OrphanDetector] Removed: \(path.path)")
                } catch {
                    AppLogger.shared.log("❌ [OrphanDetector] Failed to remove \(path.path): \(error)")
                    userFilesFailed.append((path.lastPathComponent, error.localizedDescription))
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
                deferredForNextUninstall: deferredForNextUninstall,
                daemonsCleaned: daemonsCleaned,
                daemonsError: daemonsError
            )
        }
    }

    private func showCleanupResult(
        userFilesCleaned: Int,
        userFilesFailed: [(name: String, reason: String)],
        deferredForNextUninstall: Bool,
        daemonsCleaned: Bool,
        daemonsError: String?
    ) {
        let hasRealFailures = !userFilesFailed.isEmpty || daemonsError != nil
        let didAnything = userFilesCleaned > 0 || daemonsCleaned

        // If everything succeeded (possibly with deferred items), show clean success
        if !hasRealFailures {
            AppLogger.shared.info("🧹 [OrphanDetector] Cleanup complete: \(userFilesCleaned) user files, daemons: \(daemonsCleaned), deferred: \(deferredForNextUninstall)")
            if didAnything {
                let resultAlert = NSAlert()
                resultAlert.messageText = "Cleanup Complete"
                var parts: [String] = []
                if userFilesCleaned > 0 {
                    parts.append("Removed \(userFilesCleaned) file(s)")
                }
                if daemonsCleaned {
                    parts.append("Removed system keyboard services")
                }
                resultAlert.informativeText = parts.joined(separator: " and ") + " from a previous KeyPath installation."
                resultAlert.alertStyle = .informational
                resultAlert.runModal()
            }
            return
        }

        // There were real failures — show simplified partial result
        let resultAlert = NSAlert()
        resultAlert.messageText = "Cleanup Partially Complete"
        resultAlert.informativeText = "Some leftover files could not be removed. They will be cleaned up automatically on next uninstall."
        resultAlert.alertStyle = .warning
        resultAlert.runModal()
    }
}
