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
    private static let kanataServiceID = "com.keypath.kanata"

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
                "❌ [KanataBinaryInstaller] CRITICAL: Bundled kanata binary not found at: \(bundledPath)"
            )
            AppLogger.shared.log(
                "❌ [KanataBinaryInstaller] This indicates a packaging issue - the app bundle is missing the kanata binary"
            )
            return false
        }

        // Verify the bundled binary is executable
        guard FileManager.default.isExecutableFile(atPath: bundledPath) else {
            AppLogger.shared.log(
                "❌ [KanataBinaryInstaller] Bundled kanata binary exists but is not executable: \(bundledPath)"
            )
            return false
        }

        // Ensure we only install binaries with a valid, expected signature (unless explicitly
        // overridden for local dev experiments).
        let preflight = await signingPreflight(forBundledBinaryAt: bundledPath)
        guard preflight.success else {
            AppLogger.shared.error(
                "❌ [KanataBinaryInstaller] Refusing install due to signing preflight failure: \(preflight.reason)"
            )
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
            // Mark warm-up before replacement so health checks can treat launchctl "not found"
            // transitions as transient while the daemon is being swapped.
            ServiceBootstrapper.shared.markRestartTime(for: [Self.kanataServiceID])

            let qSystemDir = Self.shellSingleQuoted(systemDir)
            let qBundledPath = Self.shellSingleQuoted(bundledPath)
            let qSystemPath = Self.shellSingleQuoted(systemPath)
            let qServiceID = Self.shellSingleQuoted(Self.kanataServiceID)
            let command = """
            set -e
            SYSTEM_DIR='\(qSystemDir)'
            SRC='\(qBundledPath)'
            DST='\(qSystemPath)'
            SERVICE_ID='\(qServiceID)'
            TMP_PATH="${SYSTEM_DIR}/.kanata.new.$$"
            BACKUP_PATH="${SYSTEM_DIR}/.kanata.backup.$$"
            HAD_BACKUP=0

            cleanup_tmp() {
              rm -f "${TMP_PATH}" 2>/dev/null || true
            }

            rollback_binary() {
              if [ "${HAD_BACKUP}" -eq 1 ] && [ -f "${BACKUP_PATH}" ]; then
                mv -f "${BACKUP_PATH}" "${DST}" 2>/dev/null || true
              fi
            }

            trap cleanup_tmp EXIT

            /bin/mkdir -p "${SYSTEM_DIR}"
            /usr/sbin/chown root:wheel "${SYSTEM_DIR}" 2>/dev/null || true
            /bin/chmod 755 "${SYSTEM_DIR}" 2>/dev/null || true

            /usr/bin/install -o root -g wheel -m 755 "${SRC}" "${TMP_PATH}"
            /usr/bin/xattr -d com.apple.quarantine "${TMP_PATH}" 2>/dev/null || true
            /usr/bin/codesign --verify --strict --verbose=2 "${TMP_PATH}"

            /bin/launchctl bootout "system/${SERVICE_ID}" 2>/dev/null || true
            /usr/bin/pkill -f "kanata.*--cfg" 2>/dev/null || true

            if [ -f "${DST}" ]; then
              mv -f "${DST}" "${BACKUP_PATH}"
              HAD_BACKUP=1
            fi

            if ! mv -f "${TMP_PATH}" "${DST}"; then
              rollback_binary
              exit 1
            fi

            if ! /usr/bin/codesign --verify --strict --verbose=2 "${DST}"; then
              rm -f "${DST}" 2>/dev/null || true
              rollback_binary
              exit 2
            fi

            if ! "${DST}" --version >/dev/null 2>&1; then
              rm -f "${DST}" 2>/dev/null || true
              rollback_binary
              exit 3
            fi

            rm -f "${BACKUP_PATH}" 2>/dev/null || true
            """

            let result = PrivilegedCommandRunner.execute(
                command: command,
                prompt: "KeyPath needs to install the Kanata binary to the system location."
            )
            success = result.success
        }

        if success {
            AppLogger.shared.log(
                "✅ [KanataBinaryInstaller] Bundled kanata binary installed successfully to \(systemPath)"
            )

            // Keep transition window open slightly past copy completion to absorb launchd churn.
            ServiceBootstrapper.shared.markRestartTime(for: [Self.kanataServiceID])

            // Verify code signing and trust (must pass in strict mode)
            guard await verifyCodeSigning(
                at: systemPath,
                expectedTeamIdentifier: preflight.expectedTeamIdentifier
            ) else {
                AppLogger.shared.error("❌ [KanataBinaryInstaller] Post-install signature verification failed")
                return false
            }

            // Smoke test: verify the binary can actually execute.
            if !TestEnvironment.shouldSkipAdminOperations {
                guard await runSmokeTest(at: systemPath) else {
                    AppLogger.shared.error("❌ [KanataBinaryInstaller] Post-install smoke test failed")
                    return false
                }
            }

            // Verify the installation using detector
            let detector = KanataBinaryDetector.shared
            let result = detector.detectCurrentStatus()
            AppLogger.shared.log(
                "🔍 [KanataBinaryInstaller] Post-installation detection: \(result.status) at \(result.path ?? "unknown")"
            )

            // The installer writes the canonical system path; the detector should now report installed.
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
                "✅ [KanataBinaryInstaller] Using system Kanata path (has TCC permissions): \(systemPath)"
            )
            return systemPath
        } else {
            let bundledPath = WizardSystemPaths.bundledKanataPath
            if FileManager.default.fileExists(atPath: bundledPath) {
                AppLogger.shared.log(
                    "⚠️ [KanataBinaryInstaller] System kanata not found, using bundled path: \(bundledPath)"
                )
            } else {
                AppLogger.shared.log("❌ [KanataBinaryInstaller] Bundled Kanata binary not found at: \(bundledPath)")
                AppLogger.shared.log(
                    "💡 [KanataBinaryInstaller] User may need to reinstall Kanata components before proceeding"
                )
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

    private struct SigningPreflightResult {
        let success: Bool
        let reason: String
        let expectedTeamIdentifier: String?
    }

    private func signingPreflight(forBundledBinaryAt bundledPath: String) async -> SigningPreflightResult {
        if TestEnvironment.shouldSkipAdminOperations || allowUnsignedKanataForDevelopment {
            return SigningPreflightResult(
                success: true,
                reason: "Signature preflight bypassed for test/dev override",
                expectedTeamIdentifier: nil
            )
        }

        let appPath = Bundle.main.bundlePath
        let appVerify = await verifyCodeSigning(at: appPath, expectedTeamIdentifier: nil)
        guard appVerify else {
            return SigningPreflightResult(
                success: false,
                reason: "App signature verification failed at \(appPath)",
                expectedTeamIdentifier: nil
            )
        }

        let bundledVerify = await verifyCodeSigning(at: bundledPath, expectedTeamIdentifier: nil)
        guard bundledVerify else {
            return SigningPreflightResult(
                success: false,
                reason: "Bundled kanata signature verification failed at \(bundledPath)",
                expectedTeamIdentifier: nil
            )
        }

        let appTeam = await extractTeamIdentifier(at: appPath)
        let bundledTeam = await extractTeamIdentifier(at: bundledPath)

        guard let appTeam else {
            return SigningPreflightResult(
                success: false,
                reason: "Could not determine app TeamIdentifier",
                expectedTeamIdentifier: nil
            )
        }
        guard let bundledTeam else {
            return SigningPreflightResult(
                success: false,
                reason: "Could not determine bundled kanata TeamIdentifier",
                expectedTeamIdentifier: nil
            )
        }

        guard appTeam == bundledTeam else {
            return SigningPreflightResult(
                success: false,
                reason: "Bundled kanata TeamIdentifier mismatch (app=\(appTeam), kanata=\(bundledTeam))",
                expectedTeamIdentifier: appTeam
            )
        }

        AppLogger.shared.log("✅ [KanataBinaryInstaller] Signing preflight passed (TeamIdentifier=\(appTeam))")
        return SigningPreflightResult(
            success: true,
            reason: "OK",
            expectedTeamIdentifier: appTeam
        )
    }

    /// Verify code signing and trust for a binary or bundle path.
    private func verifyCodeSigning(at path: String, expectedTeamIdentifier: String?) async -> Bool {
        do {
            let result = try await SubprocessRunner.shared.run(
                "/usr/bin/codesign",
                args: ["--verify", "--strict", "--verbose=2", path],
                timeout: 10
            )
            guard result.exitCode == 0 else {
                let output = result.stderr.isEmpty ? result.stdout : result.stderr
                AppLogger.shared.error(
                    "❌ [KanataBinaryInstaller] codesign verify failed for \(path): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
                return false
            }
        } catch {
            AppLogger.shared.error("❌ [KanataBinaryInstaller] codesign verify threw for \(path): \(error)")
            return false
        }

        if let expectedTeamIdentifier {
            let teamID = await extractTeamIdentifier(at: path)
            guard teamID == expectedTeamIdentifier else {
                AppLogger.shared.error(
                    "❌ [KanataBinaryInstaller] TeamIdentifier mismatch for \(path): expected \(expectedTeamIdentifier), got \(teamID ?? "nil")"
                )
                return false
            }
        }

        return true
    }

    /// Run smoke test to verify the binary can actually execute
    private func runSmokeTest(at path: String) async -> Bool {
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
                return true
            } else {
                AppLogger.shared.log(
                    "❌ [KanataBinaryInstaller] Kanata exec smoke test failed with exit code \(result.exitCode): \(result.stderr)"
                )
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [KanataBinaryInstaller] Kanata exec smoke test threw error: \(error)")
            return false
        }
    }

    private var allowUnsignedKanataForDevelopment: Bool {
        ProcessInfo.processInfo.environment["KEYPATH_ALLOW_UNSIGNED_KANATA"] == "1"
    }

    private func extractTeamIdentifier(at path: String) async -> String? {
        do {
            let result = try await SubprocessRunner.shared.run(
                "/usr/bin/codesign",
                args: ["-d", "--verbose=4", path],
                timeout: 10
            )
            let output = "\(result.stdout)\n\(result.stderr)"
            return Self.parseTeamIdentifier(fromCodesignOutput: output)
        } catch {
            AppLogger.shared.warn("⚠️ [KanataBinaryInstaller] Unable to extract TeamIdentifier for \(path): \(error)")
            return nil
        }
    }

    nonisolated internal static func parseTeamIdentifier(fromCodesignOutput output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"TeamIdentifier=([A-Z0-9]+)"#) else {
            return nil
        }

        let nsRange = NSRange(output.startIndex ..< output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: nsRange) else {
            return nil
        }
        guard match.numberOfRanges > 1, let teamRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[teamRange])
    }

    nonisolated internal static func shellSingleQuoted(_ value: String) -> String {
        // Escapes single quotes for inclusion inside a surrounding single-quoted string in POSIX shells.
        // Example: abc'def -> abc'"'"'def
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}
