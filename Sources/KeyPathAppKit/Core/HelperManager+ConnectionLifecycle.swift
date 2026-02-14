import Darwin
import Foundation
import KeyPathCore

extension HelperManager {
    // MARK: - Connection Management

    /// Get or create the XPC connection to the helper
    /// - Returns: The active XPC connection
    /// - Throws: HelperError if connection cannot be established
    func getConnection() async throws -> NSXPCConnection {
        // Check if existing connection is still valid
        if let existingConnection = connection {
            // Verify connection is still alive by checking if we can get process identifier
            // If connection is invalidated, processIdentifier will be 0 or connection will be nil
            let pid = existingConnection.processIdentifier
            if pid > 0 {
                // Connection appears valid - but verify helper process is still running
                // This catches cases where helper restarted but connection wasn't invalidated
                if isHelperProcessRunning(pid: pid) {
                    AppLogger.shared.log("♻️ [HelperManager] Reusing existing XPC connection (PID: \(pid))")
                    return existingConnection
                } else {
                    AppLogger.shared.log(
                        "⚠️ [HelperManager] Cached connection points to dead helper process (PID: \(pid)) - clearing"
                    )
                    connection = nil
                }
            } else {
                AppLogger.shared.log("⚠️ [HelperManager] Cached connection has invalid PID - clearing")
                connection = nil
            }
        }

        // Best-effort: verify embedded helper signature/requirement before connecting
        await verifyEmbeddedHelperSignature()

        // Create new connection
        AppLogger.shared.log(
            "🔗 [HelperManager] Creating XPC connection to \(Self.helperMachServiceName)"
        )

        let newConnection = NSXPCConnection(
            machServiceName: Self.helperMachServiceName, options: .privileged
        )

        // Set up the interface
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        // Handle connection lifecycle
        newConnection.invalidationHandler = {
            AppLogger.shared.log("❌ [HelperManager] XPC connection invalidated")
            Task { await HelperManager.shared.clearConnection() }
        }

        newConnection.interruptionHandler = {
            AppLogger.shared.log("⚠️ [HelperManager] XPC connection interrupted - will reconnect")
            Task { await HelperManager.shared.clearConnection() }
        }

        // Start the connection
        newConnection.resume()

        connection = newConnection
        AppLogger.shared.info(
            "✅ [HelperManager] XPC connection established (PID: \(newConnection.processIdentifier))"
        )

        return newConnection
    }

    /// Close the XPC connection
    func disconnect() {
        AppLogger.shared.log("🔌 [HelperManager] Disconnecting XPC connection")
        connection?.invalidate()
        connection = nil
    }

    func clearConnection() {
        AppLogger.shared.log("🧹 [HelperManager] Clearing XPC connection cache")
        connection?.invalidate()
        connection = nil
        // Clear cached version when connection is cleared (might be stale)
        cachedHelperVersion = nil
    }

    /// Check if helper process is still running
    /// - Parameter pid: Process ID to check
    /// - Returns: true if process exists, false otherwise
    private func isHelperProcessRunning(pid: Int32) -> Bool {
        // Use kill(pid, 0) to check if process exists (doesn't actually kill, just checks)
        // Returns 0 if process exists, -1 with errno set if it doesn't
        // EPERM means process exists but we don't have permission (still means it's running)
        let result = kill(pid, 0)
        if result == 0 {
            return true
        }
        // Check errno - EPERM means process exists but we can't signal it (still running)
        // ESRCH means process doesn't exist
        let error = errno
        return error == EPERM
    }

    /// Verify the embedded helper's designated requirement roughly matches expectations.
    /// Logs warnings on mismatch; does not block connection (to avoid false positives during dev).
    private nonisolated func verifyEmbeddedHelperSignature() async {
        let fm = FileManager.default
        // Use the production app path (like SignatureHealthCheck does)
        // Bundle.main.bundlePath can be wrong when launched via Xcode tools
        let bundlePath = "/Applications/KeyPath.app"
        let helperPath = bundlePath + "/Contents/Library/HelperTools/KeyPathHelper"
        guard fm.fileExists(atPath: helperPath) else {
            AppLogger.shared.log("⚠️ [HelperManager] Embedded helper not found at \(helperPath)")
            AppLogger.shared.log("   Bundle.main.bundlePath = \(Bundle.main.bundlePath)")
            return
        }

        // Extract designated requirement using codesign
        let runner = Self.subprocessRunnerFactory()
        do {
            let result = try await runner.run(
                "/usr/bin/codesign",
                args: ["-d", "-r-", helperPath],
                timeout: 10
            )
            let combined = result.stdout + "\n" + result.stderr
            guard
                let req = combined.components(separatedBy: "designated =>").last?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), !req.isEmpty
            else {
                AppLogger.shared.log("⚠️ [HelperManager] Could not parse helper designated requirement")
                return
            }

            // Minimal checks
            var warnings: [String] = []
            if !req.contains("identifier \"com.keypath.helper\"") {
                warnings.append("missing identifier 'com.keypath.helper'")
            }
            if !req.contains("1.2.840.113635.100.6.2.6") { // Developer ID CA
                warnings.append("missing Developer ID CA marker")
            }
            if !req.contains("1.2.840.113635.100.6.1.13") { // Developer ID Application
                warnings.append("missing Developer ID Application marker")
            }

            // Compare with SMPrivilegedExecutables requirement (if present)
            var plistRequirement: String?
            if let info = NSDictionary(contentsOfFile: bundlePath + "/Contents/Info.plist"),
               let sm = (info["SMPrivilegedExecutables"] as? NSDictionary)?[Self.helperBundleIdentifier]
               as? String
            {
                plistRequirement = sm
                if !req.contains("com.keypath.helper") {
                    warnings.append(
                        "helper req does not show expected identifier, while Info.plist declares it"
                    )
                }
            }

            if warnings.isEmpty {
                AppLogger.shared.log("🔒 [HelperManager] Embedded helper signature looks valid")
            } else {
                AppLogger.shared.log(
                    "⚠️ [HelperManager] Embedded helper signature warnings: \(warnings.joined(separator: "; "))"
                )
                if let plistRequirement {
                    AppLogger.shared.log(
                        "ℹ️ [HelperManager] App Info.plist SMPrivilegedExecutables[\(Self.helperBundleIdentifier)] = \(plistRequirement)"
                    )
                }
                AppLogger.shared.log("ℹ️ [HelperManager] codesign designated => \(req)")
            }
        } catch {
            AppLogger.shared.log(
                "⚠️ [HelperManager] Could not run codesign: \(error.localizedDescription)"
            )
        }
    }
}
