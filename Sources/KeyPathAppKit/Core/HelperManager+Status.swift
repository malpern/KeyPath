import Foundation
import KeyPathCore
import os.lock

extension HelperManager {
    // MARK: - Helper Status

    /// Check if the privileged helper needs Login Items approval in System Settings
    /// - Returns: true if SMAppService reports `.requiresApproval`
    ///
    /// This is a synchronous check used by the wizard navigation engine to prioritize
    /// Login Items approval as a blocking dependency before other setup steps.
    public nonisolated func helperNeedsLoginItemsApproval() -> Bool {
        Self.systemStateProviderFactory()
            .smAppServiceStatusSynchronously(for: Self.helperPlistName) == .requiresApproval
    }

    /// Check if the privileged helper is installed and registered (SMAppService path)
    /// - Returns: true if SMAppService reports `.enabled` OR launchctl has the job
    ///
    /// On macOS 13+, the helper binary remains embedded inside the app bundle and is
    /// invoked via `BundleProgram` in the plist; there is no binary at
    /// `/Library/PrivilegedHelperTools` as with legacy SMJobBless.
    public nonisolated func isHelperInstalled() async -> Bool {
        let smStatus = await Self.systemStateProviderFactory()
            .cachedSMAppServiceStatus(for: Self.helperPlistName)
        if smStatus == .enabled { return true }

        // Best-effort check: does launchd know about the job?
        let evidence = await Self.systemStateProviderFactory()
            .launchctlPrint(target: "system/\(Self.helperBundleIdentifier)")
        if evidence.exitCode == 0 {
            let s = evidence.stdout
            if s.contains("program") || s.contains("state =") || s.contains("pid =") {
                AppLogger.shared.debug(
                    "[HelperManager] launchctl reports helper present while SMAppService status=\(smStatus)"
                )
                return true
            }
        }
        return false
    }

    /// Get the version of the installed helper
    /// - Returns: Version string, or nil if helper not installed or version check fails
    public func getHelperVersion() async -> String? {
        // Bypass XPC call in tests
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [HelperManager] Test mode - returning mock version")
            return Self.expectedHelperVersion
        }

        do {
            if isWithinAmbiguousMutationProbeWindow() {
                AppLogger.shared.log(
                    "⏳ [HelperManager] Deferring version probe after ambiguous mutation timeout"
                )
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
            }

            return try await withHelperOperationPermit {
                try Task.checkCancellation()

                guard await isHelperInstalled() else {
                    AppLogger.shared.log("⚠️ [HelperManager] Helper not installed, cannot get version")
                    return nil
                }

                return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                    let resumed = OSAllocatedUnfairLock(initialState: false)
                    let complete: @Sendable (String?) -> Void = { value in
                        let alreadyResumed = resumed.withLock { flag -> Bool in
                            if flag { return true }
                            flag = true
                            return false
                        }
                        guard !alreadyResumed else { return }
                        continuation.resume(returning: value)
                    }

                    let timeoutTask = Task { @Sendable in
                        try await Task.sleep(for: .seconds(3))
                        AppLogger.shared.log(
                            "⚠️ [HelperManager] getVersion timed out; preserving the shared connection because another operation may still be completing"
                        )
                        complete(nil)
                    }

                    Task {
                        do {
                            try Task.checkCancellation()
                            let remote = try await getRemoteProxy { error in
                                AppLogger.shared.log(
                                    "❌ [HelperManager] getVersion proxy error: \(Self.normalizedProxyError(error, operation: "getVersion"))"
                                )
                                timeoutTask.cancel()
                                complete(nil)
                            }
                            AppLogger.shared.log("📤 [HelperManager] Calling proxy.getVersion()")
                            remote.proxy.getVersion { version, error in
                                timeoutTask.cancel()
                                if let version {
                                    AppLogger.shared.info("✅ [HelperManager] Helper version: \(version)")
                                    complete(version)
                                } else {
                                    let message = error ?? "Unknown error"
                                    let generation = remote.connectionGeneration
                                    AppLogger.shared.log(
                                        "❌ [HelperManager] getVersion callback error: \(message)"
                                    )
                                    Task {
                                        await HelperManager.shared.clearConnection(
                                            ifGenerationMatches: generation
                                        )
                                    }
                                    complete(nil)
                                }
                            }
                        } catch {
                            timeoutTask.cancel()
                            AppLogger.shared.log(
                                "❌ [HelperManager] Failed to connect for version check: \(error)"
                            )
                            complete(nil)
                        }
                    }
                }
            }
        } catch {
            AppLogger.shared.log(
                "ℹ️ [HelperManager] Version check cancelled before dispatch: \(error)"
            )
            return nil
        }
    }

    /// Check if the helper version matches the expected version
    /// - Returns: true if versions match, false otherwise
    func isHelperVersionCompatible() async -> Bool {
        guard let helperVersion = await getHelperVersion() else {
            return false
        }

        let compatible = helperVersion == Self.expectedHelperVersion
        if !compatible {
            AppLogger.shared.log(
                "⚠️ [HelperManager] Version mismatch - expected: \(Self.expectedHelperVersion), got: \(helperVersion)"
            )
        }
        return compatible
    }

    /// Test if the helper is actually functional (can communicate via XPC)
    /// - Returns: true if helper responds to XPC calls, false otherwise
    ///
    /// **Use Case:** This is the definitive test for helper functionality.
    /// - Returns true ONLY if XPC connection succeeds AND helper responds
    /// - Returns false for phantom registrations, connection failures, timeouts
    /// - Should be used by wizard to verify helper is truly working
    public func testHelperFunctionality() async -> Bool {
        #if DEBUG
            if let override = Self.testHelperFunctionalityOverride {
                return await override()
            }
        #endif
        AppLogger.shared.log("🧪 [HelperManager] Testing helper functionality via XPC ping")

        // getHelperVersion() already checks isHelperInstalled() internally and proves
        // XPC connectivity if it returns a version. No need to call isHelperInstalled()
        // separately — that doubled SMAppService.status IPC calls for no benefit.
        // See: docs/bugs/2026-02-19-false-kanata-service-stopped-alert.md
        guard let version = await getHelperVersion() else {
            AppLogger.shared.log("❌ [HelperManager] Functionality test failed: XPC communication failed")
            return false
        }

        AppLogger.shared.info(
            "✅ [HelperManager] Functionality test passed: Helper v\(version) responding"
        )
        return true
    }

    /// Check if helper needs upgrade (installed but wrong version)
    /// - Returns: true if upgrade needed, false otherwise
    func needsHelperUpgrade() async -> Bool {
        guard await isHelperInstalled() else {
            return false // Not installed, not an upgrade case
        }

        return await !isHelperVersionCompatible()
    }

    /// Determine helper health state using SMAppService, launchctl, and XPC
    ///
    /// **Performance note:** This method calls `isHelperInstalled()` once and
    /// `getHelperVersion()` once. A successful version response already proves
    /// XPC connectivity, so `testHelperFunctionality()` is intentionally NOT
    /// called here — it was redundant and doubled the number of IPC calls,
    /// which caused 47s stalls when SMAppService.status was slow (see
    /// docs/bugs/2026-02-19-false-kanata-service-stopped-alert.md).
    func getHelperHealth() async -> HealthState {
        let smStatus = await Self.systemStateProviderFactory()
            .cachedSMAppServiceStatus(for: Self.helperPlistName)

        // Approval explicitly required
        if smStatus == .requiresApproval {
            return .requiresApproval("Approval required in System Settings → Login Items.")
        }

        let installed = await isHelperInstalled()
        if !installed {
            return .notInstalled
        }

        // A successful getHelperVersion() proves XPC connectivity + helper responsiveness.
        // No need to call testHelperFunctionality() separately.
        if let version = await getHelperVersion() {
            return .healthy(version: version)
        }

        if isWithinAmbiguousMutationProbeWindow() {
            return .temporarilyUnavailable(
                "Helper mutation timed out recently; responsiveness is temporarily unknown"
            )
        }

        // Installed but XPC failing
        return .registeredButUnresponsive("Helper registered but XPC communication failed")
    }

    // MARK: - Diagnostics

    nonisolated func runBlessDiagnostics() -> String {
        let report = BlessDiagnostics.run()
        return report.summarizedText()
    }

    // MARK: - Helper log surface (for UX when XPC fails)

    /// Fetch the last N helper log messages (message text only)
    /// Uses `log show` with a tight window to avoid heavy queries.
    nonisolated func lastHelperLogs(count: Int = 3, windowSeconds: Int = 300) async -> [String] {
        // First: if launchctl has no record of the job, surface that clearly.
        let evidence = await Self.systemStateProviderFactory()
            .launchctlPrint(target: "system/\(Self.helperBundleIdentifier)")
        if evidence.exitCode != 0 {
            let errStr = evidence.stderr
            if errStr.contains("Could not find service") || errStr.contains("Bad request") {
                return [
                    "Helper not registered: launchctl has no job 'system/com.keypath.helper'",
                    "Click 'Install Helper', then Test XPC again."
                ]
            }
        }

        let runner = Self.subprocessRunnerFactory()

        func fetch(_ seconds: Int) async -> [String] {
            do {
                let result = try await runner.run(
                    "/usr/bin/log",
                    args: [
                        "show",
                        "--last", "\(seconds)s",
                        "--style", "syslog",
                        "--predicate",
                        "process == 'KeyPathHelper' OR processImagePath CONTAINS[c] 'KeyPathHelper'"
                    ],
                    timeout: 10
                )
                guard !result.stdout.isEmpty else { return [] }
                return result.stdout.split(separator: "\n").map(String.init)
            } catch {
                return []
            }
        }
        // Try progressively larger windows
        let windows = [max(60, windowSeconds), 1800, 86400]
        var collected: [String] = []
        for w in windows {
            let lines = await fetch(w)
            // Extract message part after the first ': '
            let messages = lines.compactMap { line -> String? in
                guard let range = line.range(of: ": ") else { return nil }
                let msg = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return msg.isEmpty ? nil : msg
            }
            collected.append(contentsOf: messages)
            if collected.count >= count { break }
        }
        if !collected.isEmpty {
            return Array(collected.suffix(count))
        }
        // Fallback: check file logs if present
        let fileCandidates = [
            "/var/log/com.keypath.helper.stdout.log",
            "/var/log/com.keypath.helper.stderr.log"
        ]
        for path in fileCandidates where Foundation.FileManager().fileExists(atPath: path) {
            do {
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                let data = try handle.readToEnd()
                let s = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let lines = s.split(separator: "\n").map(String.init)
                if !lines.isEmpty { return Array(lines.suffix(count)) }
            } catch {
                AppLogger.shared.debug("⚠️ [HelperManager] Could not read log file at \(path): \(error.localizedDescription)")
            }
        }
        return []
    }
}
