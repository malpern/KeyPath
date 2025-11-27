import Foundation
import KeyPathCore

/// Handles installation and management of the Kanata binary.
/// Responsible for copying bundled binary to system location and version checks.
///
/// This service provides binary installation capabilities extracted from LaunchDaemonInstaller
/// to support both LaunchDaemon and SMAppService installation paths.
@MainActor
final class KanataBinaryInstaller {
    static let shared = KanataBinaryInstaller()

    private init() {}

    // MARK: - Public Interface

    /// Install bundled Kanata binary to system location (/Library/KeyPath/bin/kanata)
    /// Returns true if installation succeeded or binary already exists
    func installBundledKanata() async -> Bool {
        AppLogger.shared.log("🔧 [KanataBinaryInstaller] Installing bundled kanata binary to system location")

        let bundledPath = WizardSystemPaths.bundledKanataPath
        let systemPath = WizardSystemPaths.kanataSystemInstallPath
        let systemDir = "/Library/KeyPath/bin"

        // Ensure bundled binary exists
        // NOTE: This case is now surfaced as a .critical wizard issue via KanataBinaryDetector
        // detecting .bundledMissing status and IssueGenerator creating a .bundledKanataMissing component issue
        guard FileManager.default.fileExists(atPath: bundledPath) else {
            AppLogger.shared.log(
                "❌ [KanataBinaryInstaller] CRITICAL: Bundled kanata binary not found at: \(bundledPath)")
            AppLogger.shared.log(
                "❌ [KanataBinaryInstaller] This indicates a packaging issue - the app bundle is missing the kanata binary"
            )
            return false
        }

        // Verify the bundled binary is executable
        guard FileManager.default.isExecutableFile(atPath: bundledPath) else {
            AppLogger.shared.log(
                "❌ [KanataBinaryInstaller] Bundled kanata binary exists but is not executable: \(bundledPath)")
            return false
        }

        AppLogger.shared.log("📂 [KanataBinaryInstaller] Copying \(bundledPath) → \(systemPath)")

        // Check if we should skip admin operations for testing
        let success: Bool
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("⚠️ [KanataBinaryInstaller] TEST MODE: Skipping actual binary installation")
            // In test mode, just verify the source exists and return success
            success = FileManager.default.fileExists(atPath: bundledPath)
        } else {
            let command = """
            mkdir -p '\(systemDir)' && \
            cp '\(bundledPath)' '\(systemPath)' && \
            chmod 755 '\(systemPath)' && \
            chown root:wheel '\(systemPath)' && \
            xattr -d com.apple.quarantine '\(systemPath)' 2>/dev/null || true
            """

            let result = PrivilegedCommandRunner.execute(
                command: command,
                prompt: "KeyPath needs to install the Kanata binary to the system location."
            )
            success = result.success
        }

        if success {
            AppLogger.shared.log(
                "✅ [KanataBinaryInstaller] Bundled kanata binary installed successfully to \(systemPath)")

            // Verify code signing and trust
            await verifyCodeSigning(at: systemPath)

            // Smoke test: verify the binary can actually execute (skip in test mode)
            if !TestEnvironment.shouldSkipAdminOperations {
                await runSmokeTest(at: systemPath)
            }

            // Verify the installation using detector
            let detector = KanataBinaryDetector.shared
            let result = detector.detectCurrentStatus()
            AppLogger.shared.log(
                "🔍 [KanataBinaryInstaller] Post-installation detection: \(result.status) at \(result.path ?? "unknown")"
            )

            // With SMAppService, bundled Kanata is sufficient
            return detector.isInstalled()
        } else {
            AppLogger.shared.log("❌ [KanataBinaryInstaller] Failed to install bundled kanata binary")
            return false
        }
    }

    /// Check if bundled Kanata should upgrade the system installation
    /// Returns true if an upgrade is needed
    func shouldUpgradeKanata() async -> Bool {
        let systemPath = WizardSystemPaths.kanataSystemInstallPath
        let bundledPath = WizardSystemPaths.bundledKanataPath

        // If system version doesn't exist, we need to install it
        guard FileManager.default.fileExists(atPath: systemPath) else {
            AppLogger.shared.log("🔄 [KanataBinaryInstaller] System kanata not found - initial installation needed")
            return true
        }

        // If bundled version doesn't exist, no upgrade possible
        guard FileManager.default.fileExists(atPath: bundledPath) else {
            AppLogger.shared.log("⚠️ [KanataBinaryInstaller] Bundled kanata not found - cannot upgrade")
            return false
        }

        let systemVersion = await getKanataVersionAtPath(systemPath)
        let bundledVersion = await getKanataVersionAtPath(bundledPath)

        AppLogger.shared.log(
            "🔄 [KanataBinaryInstaller] Version check: System=\(systemVersion ?? "unknown"), Bundled=\(bundledVersion ?? "unknown")"
        )

        // If we can't determine versions, assume upgrade is needed for safety
        guard let systemVer = systemVersion, let bundledVer = bundledVersion else {
            AppLogger.shared.log("⚠️ [KanataBinaryInstaller] Cannot determine versions - assuming upgrade needed")
            return true
        }

        // Compare versions (simple string comparison works for most version formats)
        let upgradeNeeded = bundledVer != systemVer
        if upgradeNeeded {
            AppLogger.shared.log("🔄 [KanataBinaryInstaller] Upgrade needed: \(systemVer) → \(bundledVer)")
        } else {
            AppLogger.shared.log("✅ [KanataBinaryInstaller] Kanata versions match - no upgrade needed")
        }

        return upgradeNeeded
    }

    /// Extract version string from Kanata binary at path
    func getKanataVersionAtPath(_ path: String) async -> String? {
        do {
            let result = try await SubprocessRunner.shared.run(
                path,
                args: ["--version"],
                timeout: 5
            )

            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        } catch {
            AppLogger.shared.log("❌ [KanataBinaryInstaller] Failed to get kanata version at \(path): \(error)")
            return nil
        }
    }

    /// Get the appropriate Kanata binary path (system or bundled)
    /// Prefers system installation path which has Input Monitoring TCC permissions
    func getKanataBinaryPath() -> String {
        // Use system install path which has Input Monitoring TCC permissions
        // The bundled path inside KeyPath.app does NOT have permissions
        let systemPath = WizardSystemPaths.kanataSystemInstallPath

        // Verify the system path exists, otherwise fall back to bundled
        if FileManager.default.fileExists(atPath: systemPath) {
            AppLogger.shared.log(
                "✅ [KanataBinaryInstaller] Using system Kanata path (has TCC permissions): \(systemPath)")
            return systemPath
        } else {
            let bundledPath = WizardSystemPaths.bundledKanataPath
            if FileManager.default.fileExists(atPath: bundledPath) {
                AppLogger.shared.log(
                    "⚠️ [KanataBinaryInstaller] System kanata not found, using bundled path: \(bundledPath)")
            } else {
                AppLogger.shared.log("❌ [KanataBinaryInstaller] Bundled Kanata binary not found at: \(bundledPath)")
                AppLogger.shared.log(
                    "💡 [KanataBinaryInstaller] User may need to reinstall Kanata components before proceeding")
            }
            return bundledPath
        }
    }

    /// Check if bundled Kanata binary exists in app bundle
    func isBundledKanataAvailable() -> Bool {
        let bundledPath = WizardSystemPaths.bundledKanataPath
        let exists = FileManager.default.fileExists(atPath: bundledPath)
        if exists {
            AppLogger.shared.log("✅ [KanataBinaryInstaller] Bundled kanata available at: \(bundledPath)")
        } else {
            AppLogger.shared.log("❌ [KanataBinaryInstaller] Bundled kanata not found at: \(bundledPath)")
        }
        return exists
    }

    // MARK: - Private Helpers

    /// Verify code signing and trust for the installed binary
    private func verifyCodeSigning(at path: String) async {
        AppLogger.shared.log("🔍 [KanataBinaryInstaller] Verifying code signing and trust...")
        let verifyCommand = "spctl -a '\(path)' 2>&1"

        do {
            let result = try await SubprocessRunner.shared.run(
                "/bin/bash",
                args: ["-c", verifyCommand],
                timeout: 10
            )

            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [KanataBinaryInstaller] Binary passed Gatekeeper verification")
            } else if result.stderr.contains("rejected") || result.stderr.contains("not accepted") {
                AppLogger.shared.log("⚠️ [KanataBinaryInstaller] Binary failed Gatekeeper verification: \(result.stderr)")
                // Continue anyway - the binary is installed and quarantine removed
            }
        } catch {
            AppLogger.shared.log("⚠️ [KanataBinaryInstaller] Could not verify code signing: \(error)")
        }
    }

    /// Run smoke test to verify the binary can actually execute
    private func runSmokeTest(at path: String) async {
        AppLogger.shared.log("🔍 [KanataBinaryInstaller] Running smoke test to verify binary execution...")

        do {
            let result = try await SubprocessRunner.shared.run(
                path,
                args: ["--version"],
                timeout: 5
            )

            if result.exitCode == 0 {
                let smokeOutput = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.shared.log(
                    "✅ [KanataBinaryInstaller] Kanata binary executes successfully (--version): \(smokeOutput)"
                )
            } else {
                AppLogger.shared.log(
                    "⚠️ [KanataBinaryInstaller] Kanata exec smoke test failed with exit code \(result.exitCode): \(result.stderr)"
                )
                // Continue anyway - the binary is installed
            }
        } catch {
            AppLogger.shared.log("⚠️ [KanataBinaryInstaller] Kanata exec smoke test threw error: \(error)")
            // Continue anyway - the binary is installed
        }
    }
}
