import Foundation
import KeyPathCore

extension HelperManager {
    // MARK: - Helper Installation

    /// Install the privileged helper using SMJobBless
    /// - Throws: HelperManagerError if installation fails
    func installHelper() async throws {
        #if DEBUG
            if let override = Self.testInstallHelperOverride {
                try await override()
                return
            }
        #endif
        AppLogger.shared.log("🔐 [SMAPPSERVICE-TRIGGER] *** Registering privileged helper via SMAppService")
        AppLogger.shared.log("🔐 [SMAPPSERVICE-TRIGGER] Helper install caller stack unavailable in this build")
        guard #available(macOS 13, *) else {
            throw HelperManagerError.installationFailed("Requires macOS 13+ for SMAppService")
        }

        if let preflightError = await signingPreflightFailure() {
            throw HelperManagerError.installationFailed(preflightError)
        }

        // Diagnostic logging
        if let bundlePath = Bundle.main.bundlePath as String? {
            AppLogger.shared.log("📦 [HelperManager] App bundle: \(bundlePath)")
            let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
            if let infoDict = NSDictionary(contentsOfFile: infoPlistPath) {
                let hasSMPrivileged = infoDict["SMPrivilegedExecutables"] != nil
                AppLogger.shared.log(
                    "📋 [HelperManager] Info.plist has SMPrivilegedExecutables: \(hasSMPrivileged)"
                )
            } else {
                AppLogger.shared.log("⚠️ [HelperManager] Could not read Info.plist")
            }
        }

        let svc = Self.smServiceFactory(Self.helperPlistName)
        AppLogger.shared.log(
            "🔍 [HelperManager] SMAppService status: \(svc.status.rawValue) (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)"
        )
        switch svc.status {
        case .enabled:
            // Enabled means the app has background-item approval, not necessarily that
            // the daemon is registered. Attempt an idempotent register to ensure the
            // system copies are installed. Then verify XPC actually responds: launchd
            // can retain stale SMAppService state after app replacement.
            var registerError: Error?
            do {
                try svc.register()
            } catch {
                registerError = error
                if svc.status == .enabled {
                    AppLogger.shared.log("ℹ️ [HelperManager] Helper already Enabled after register error; verifying XPC")
                } else {
                    throw HelperManagerError.installationFailed(
                        "SMAppService register (enabled path) failed: \(error.localizedDescription)"
                    )
                }
            }

            if await waitForHelperFunctionality(context: "enabled helper refresh", attempts: 2) {
                AppLogger.shared.info("✅ [HelperManager] Helper registered and responding (was Enabled prior)")
                return
            }

            AppLogger.shared.log(
                "⚠️ [HelperManager] Helper SMAppService is enabled but XPC is unresponsive; clearing stale registration"
            )
            if let registerError {
                AppLogger.shared.log(
                    "ℹ️ [HelperManager] Enabled-path register error before stale recovery: \(registerError.localizedDescription)"
                )
            }
            try await recoverStaleEnabledHelper(svc)
        case .requiresApproval:
            throw HelperManagerError.installationFailed(
                "Approval required in System Settings → Login Items."
            )
        case .notRegistered:
            do {
                try svc.register()
                AppLogger.shared.info("✅ [HelperManager] Helper registered (status: \(svc.status))")
                return
            } catch {
                // If another thread already registered or approval raced, treat Enabled as success
                if svc.status == .enabled {
                    AppLogger.shared.info(
                        "✅ [HelperManager] Helper became Enabled during registration race; treating as success"
                    )
                    return
                }
                if svc.status == .requiresApproval {
                    throw HelperManagerError.installationFailed(
                        "Approval required in System Settings → Login Items."
                    )
                }
                throw HelperManagerError.installationFailed(
                    "SMAppService register failed: \(error.localizedDescription)"
                )
            }
        case .notFound:
            // .notFound means the system hasn't seen the helper yet, but registration might still work
            // Try to register to get the actual error message
            AppLogger.shared.log(
                "⚠️ [HelperManager] Helper status is .notFound - attempting registration anyway to get detailed error"
            )
            do {
                try svc.register()
                AppLogger.shared.info(
                    "✅ [HelperManager] Helper registered successfully despite initial .notFound status"
                )
                return
            } catch {
                // Now we have the real error from SMAppService
                let detail = Self.formatSMError(error)
                AppLogger.shared.log("❌ [HelperManager] Registration failed with detailed error: \(detail)")
                throw HelperManagerError.installationFailed(
                    "SMAppService register failed: \(detail)"
                )
            }
        @unknown default:
            do {
                try svc.register()
                return
            } catch {
                throw HelperManagerError.installationFailed(
                    "SMAppService register failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Uninstall the privileged helper
    /// - Throws: HelperManagerError if uninstallation fails
    func uninstallHelper() async throws {
        AppLogger.shared.log("🗑️ [HelperManager] Unregistering privileged helper via SMAppService")
        guard #available(macOS 13, *) else {
            throw HelperManagerError.operationFailed("Requires macOS 13+ for SMAppService")
        }
        let svc = Self.smServiceFactory(Self.helperPlistName)
        do { try await svc.unregister() } catch {
            throw HelperManagerError.operationFailed(
                "SMAppService unregister failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Error helpers

    static func formatSMError(_ error: Error) -> String {
        let ns = error as NSError
        var parts: [String] = []
        parts.append(ns.localizedDescription)
        parts.append("[\(ns.domain):\(ns.code)]")
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain):\(underlying.code) \(underlying.localizedDescription)")
        }
        return parts.joined(separator: " ")
    }

    static func staleHelperSMAppServiceBootoutCommands() -> [String] {
        [
            "/bin/launchctl bootout system/\(helperBundleIdentifier) 2>/dev/null || true"
        ]
    }

    private func recoverStaleEnabledHelper(_ svc: SMAppServiceProtocol) async throws {
        await clearConnection()

        do {
            try await svc.unregister()
            AppLogger.shared.log("✅ [HelperManager] Stale helper SMAppService unregister succeeded")
        } catch {
            AppLogger.shared.log(
                "⚠️ [HelperManager] Stale helper SMAppService unregister failed: \(error.localizedDescription)"
            )
        }

        let bootedOut = await bootOutStaleHelperSMAppServiceJob()
        guard bootedOut else {
            throw HelperManagerError.installationFailed(
                "Unable to clear stale helper launchd job. Try again and approve the administrator prompt."
            )
        }

        do {
            try svc.register()
            AppLogger.shared.log("✅ [HelperManager] Re-registered helper after stale SMAppService cleanup")
        } catch {
            if svc.status == .requiresApproval {
                throw HelperManagerError.installationFailed(
                    "Approval required in System Settings → Login Items."
                )
            }
            throw HelperManagerError.installationFailed(
                "SMAppService register after stale cleanup failed: \(error.localizedDescription)"
            )
        }

        guard await waitForHelperFunctionality(context: "stale helper recovery", attempts: 6) else {
            throw HelperManagerError.installationFailed(
                "Helper registered after stale cleanup but did not respond via XPC."
            )
        }
    }

    private func bootOutStaleHelperSMAppServiceJob() async -> Bool {
        AppLogger.shared.log("🔄 [HelperManager] Booting out stale helper launchd job")

        #if DEBUG
            if let override = Self.staleHelperSMAppServiceBootoutOverride {
                let result = await override()
                if !result.success {
                    AppLogger.shared.log("❌ [HelperManager] Stale helper bootout override failed: \(result.output)")
                }
                return result.success
            }
        #endif

        let command = Self.staleHelperSMAppServiceBootoutCommands().joined(separator: "\n")
        let executor = await MainActor.run { AdminCommandExecutorHolder.shared }
        do {
            let result = try await executor.execute(
                command: command,
                description: "Clear stale KeyPath helper registration"
            )
            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [HelperManager] Stale helper launchd job cleared")
                return true
            }
            AppLogger.shared.log(
                "❌ [HelperManager] Stale helper launchd clear failed (\(result.exitCode)): \(result.output)"
            )
            return false
        } catch {
            AppLogger.shared.log("❌ [HelperManager] Stale helper launchd clear error: \(error.localizedDescription)")
            return false
        }
    }

    private func waitForHelperFunctionality(context: String, attempts: Int) async -> Bool {
        for attempt in 1 ... attempts {
            if await testHelperFunctionality() {
                return true
            }
            if attempt < attempts {
                AppLogger.shared.log(
                    "⏳ [HelperManager] Helper not responding during \(context) (attempt \(attempt)/\(attempts)); waiting"
                )
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        return false
    }

    private nonisolated func signingPreflightFailure() async -> String? {
        if TestEnvironment.isRunningTests { return nil }

        let fm = Foundation.FileManager()
        let bundlePath = Bundle.main.bundlePath
        let helperPath = bundlePath + "/Contents/Library/HelperTools/KeyPathHelper"

        if !fm.fileExists(atPath: helperPath) {
            return "Bundled helper missing at \(helperPath). Reinstall KeyPath from /Applications."
        }

        let runner = Self.subprocessRunnerFactory()

        do {
            let appResult = try await runner.run(
                "/usr/bin/codesign",
                args: ["--verify", "--deep", "--strict", bundlePath],
                timeout: 10
            )
            if appResult.exitCode != 0 {
                AppLogger.shared.log(
                    "❌ [HelperManager] App signature invalid: \(appResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
                return "KeyPath is not properly signed. Install a Developer ID signed build in /Applications."
            }
        } catch {
            AppLogger.shared.log("⚠️ [HelperManager] codesign verify failed: \(error.localizedDescription)")
            return "Unable to verify KeyPath signature. Ensure you are running a signed build from /Applications."
        }

        do {
            let helperResult = try await runner.run(
                "/usr/bin/codesign",
                args: ["--verify", "--strict", helperPath],
                timeout: 10
            )
            if helperResult.exitCode != 0 {
                AppLogger.shared.log(
                    "❌ [HelperManager] Helper signature invalid: \(helperResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
                return "KeyPath helper is not properly signed. Rebuild with Scripts/build-and-sign.sh and reinstall."
            }
        } catch {
            AppLogger.shared.log("⚠️ [HelperManager] codesign verify (helper) failed: \(error.localizedDescription)")
            return "Unable to verify KeyPath helper signature. Ensure you are running a signed build."
        }

        if !bundlePath.hasPrefix("/Applications/") {
            AppLogger.shared.log(
                "⚠️ [HelperManager] KeyPath running from non-/Applications path: \(bundlePath)"
            )
        }

        return nil
    }
}
