import Foundation
import KeyPathCore

extension HelperManager {
    // MARK: - Helper Status

    /// Check if the privileged helper needs Login Items approval in System Settings
    /// - Returns: true if SMAppService reports `.requiresApproval`
    ///
    /// This is a synchronous check used by the wizard navigation engine to prioritize
    /// Login Items approval as a blocking dependency before other setup steps.
    nonisolated func helperNeedsLoginItemsApproval() -> Bool {
        let svc = Self.smServiceFactory(Self.helperPlistName)
        return svc.status == .requiresApproval
    }

    /// Check if the privileged helper is installed and registered (SMAppService path)
    /// - Returns: true if SMAppService reports `.enabled` OR launchctl has the job
    ///
    /// On macOS 13+, the helper binary remains embedded inside the app bundle and is
    /// invoked via `BundleProgram` in the plist; there is no binary at
    /// `/Library/PrivilegedHelperTools` as with legacy SMJobBless.
    nonisolated func isHelperInstalled() async -> Bool {
        let svc = Self.smServiceFactory(Self.helperPlistName)
        if svc.status == .enabled { return true }

        // Best-effort check: does launchd know about the job?
        let runner = Self.subprocessRunnerFactory()

        do {
            let result = try await runner.launchctl("print", ["system/\(Self.helperBundleIdentifier)"])
            if result.exitCode == 0 {
                let s = result.stdout
                if s.contains("program") || s.contains("state =") || s.contains("pid =") {
                    AppLogger.shared.debug(
                        "[HelperManager] launchctl reports helper present while SMAppService status=\(svc.status)"
                    )
                    return true
                }
            }
        } catch {
            // Ignore; treated as not installed
        }
        return false
    }

    /// Get the version of the installed helper
    /// - Returns: Version string, or nil if helper not installed or version check fails
    func getHelperVersion() async -> String? {
        // Return cached version if available
        if let cached = cachedHelperVersion {
            return cached
        }

        // Bypass XPC call in tests
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [HelperManager] Test mode - returning mock version")
            return Self.expectedHelperVersion
        }

        // Query version from helper
        guard await isHelperInstalled() else {
            AppLogger.shared.log("⚠️ [HelperManager] Helper not installed, cannot get version")
            return nil
        }

        do {
            let proxy = try await getRemoteProxy { _ in /* proxy error handled by timeout path */ }
            return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                let sema = DispatchSemaphore(value: 0)
                final class VersionHolder: @unchecked Sendable {
                    var value: String?
                }
                let versionHolder = VersionHolder()
                AppLogger.shared.log("📤 [HelperManager] Calling proxy.getVersion()")
                proxy.getVersion { version, error in
                    let threadName = Thread.current.isMainThread ? "main" : "background"
                    AppLogger.shared.log(
                        "📥 [HelperManager] getVersion callback received on \(threadName) thread"
                    )
                    if let version {
                        AppLogger.shared.log("✅ [HelperManager] getVersion callback: version=\(version)")
                        versionHolder.value = version
                    } else {
                        let msg = error ?? "Unknown error"
                        AppLogger.shared.log("❌ [HelperManager] getVersion callback error: \(msg)")
                    }
                    AppLogger.shared.log("📥 [HelperManager] Signaling semaphore")
                    sema.signal()
                }
                AppLogger.shared.log(
                    "📤 [HelperManager] proxy.getVersion() call dispatched, waiting for callback"
                )
                DispatchQueue.global(qos: .utility).async {
                    let waited = sema.wait(timeout: .now() + 3)
                    if waited == .timedOut {
                        AppLogger.shared.log(
                            "⚠️ [HelperManager] getVersion timed out - clearing connection cache"
                        )
                        // Clear connection on timeout - it's likely stale
                        Task { await HelperManager.shared.clearConnection() }
                        continuation.resume(returning: nil)
                    } else {
                        if let v = versionHolder.value {
                            AppLogger.shared.info("✅ [HelperManager] Helper version: \(v)")
                            continuation.resume(returning: v)
                        } else {
                            AppLogger.shared.log(
                                "⚠️ [HelperManager] getVersion callback completed but no version received - clearing connection cache"
                            )
                            // Clear connection if callback completed but no version (connection issue)
                            Task { await HelperManager.shared.clearConnection() }
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        } catch {
            AppLogger.shared.log(
                "❌ [HelperManager] Failed to connect to helper for version check: \(error)"
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
    func testHelperFunctionality() async -> Bool {
        if let override = Self.testHelperFunctionalityOverride {
            return await override()
        }
        AppLogger.shared.log("🧪 [HelperManager] Testing helper functionality via XPC ping")

        // Pre-flight check: Must be installed first
        guard await isHelperInstalled() else {
            AppLogger.shared.log("❌ [HelperManager] Functionality test failed: Not installed")
            return false
        }

        // Test actual XPC communication by getting version
        // This tests: XPC connection, helper process, message handling
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
    func getHelperHealth() async -> HealthState {
        let svc = Self.smServiceFactory(Self.helperPlistName)
        let smStatus = svc.status

        // Approval explicitly required
        if smStatus == .requiresApproval {
            return .requiresApproval("Approval required in System Settings → Login Items.")
        }

        let installed = await isHelperInstalled()
        if !installed {
            return .notInstalled
        }

        // Fast path: if XPC responds, we are healthy
        if let version = await getHelperVersion(), await testHelperFunctionality() {
            return .healthy(version: version)
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
        let runner = Self.subprocessRunnerFactory()

        // First: if launchctl has no record of the job, surface that clearly.
        do {
            let result = try await runner.launchctl("print", ["system/com.keypath.helper"])
            if result.exitCode != 0 {
                let errStr = result.stderr
                if errStr.contains("Could not find service") || errStr.contains("Bad request") {
                    return [
                        "Helper not registered: launchctl has no job 'system/com.keypath.helper'",
                        "Click 'Install Helper', then Test XPC again."
                    ]
                }
            }
        } catch {
            // Ignore; fall through to unified-log path
        }
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
        for path in fileCandidates where FileManager.default.fileExists(atPath: path) {
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
