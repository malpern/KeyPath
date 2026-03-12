import AppKit
import KeyPathCore
import KeyPathDaemonLifecycle

/// Handles one-shot diagnostic probe modes that run during `applicationDidFinishLaunching`
/// and immediately exit the process.
///
/// These probes are triggered by environment variables or sentinel files and are used
/// for host passthru diagnostics, bridge preparation, helper repair, and companion
/// restart testing.
@MainActor
enum OneShotProbeHandler {
    private static let hostPassthruDiagnosticTriggerPath = "/var/tmp/keypath-host-passthru-diagnostic"
    private static let hostPassthruBridgePrepTriggerPath = "/var/tmp/keypath-host-passthru-bridge-prep"
    private static let hostPassthruBridgePrepOutputPath = "/var/tmp/keypath-host-passthru-bridge-env.txt"
    private static let helperRepairTriggerPath = "/var/tmp/keypath-helper-repair"
    private static let companionRestartProbeOutputPath = "/var/tmp/keypath-host-passthru-companion-restart.txt"

    /// Checks for and handles any one-shot probe mode.
    /// Returns `true` if a probe was handled (caller should return early from launch).
    static func handleIfNeeded() -> Bool {
        if handleHostPassthruDiagnostic() { return true }
        if handleHostPassthruBridgePrep() { return true }
        if handleHelperRepair() { return true }
        if handleCompanionRestartProbe() { return true }
        return false
    }

    // MARK: - Host Passthru Diagnostic

    private static func handleHostPassthruDiagnostic() -> Bool {
        let shouldRun =
            ProcessInfo.processInfo.environment[OneShotProbeEnvironment.hostPassthruDiagnosticEnvKey] == "1"
                || Foundation.FileManager().fileExists(atPath: hostPassthruDiagnosticTriggerPath)

        guard shouldRun else { return false }

        try? Foundation.FileManager().removeItem(atPath: hostPassthruDiagnosticTriggerPath)
        AppLogger.shared.info("🧪 [OneShotProbe] Running experimental host passthru diagnostics and exiting")
        Task { @MainActor in
            let diagnosticsService = DiagnosticsService(
                processLifecycleManager: ProcessLifecycleManager()
            )
            let diagnostic = await diagnosticsService.runHostPassthruDiagnostic()
            AppLogger.shared.info(
                "🧪 [OneShotProbe] Host passthru diagnostic result: \(diagnostic.title) | severity=\(diagnostic.severity.rawValue) | details=\(diagnostic.technicalDetails)"
            )
            FileHandle.standardError.write(
                Data(
                    """
                    [keypath-host-passthru-diagnostic]
                    title=\(diagnostic.title)
                    severity=\(diagnostic.severity.rawValue)
                    details=\(diagnostic.technicalDetails)

                    """.utf8
                )
            )
            FileHandle.standardError.synchronizeFile()
            Foundation.exit(0)
        }
        return true
    }

    // MARK: - Host Passthru Bridge Preparation

    private static func handleHostPassthruBridgePrep() -> Bool {
        let shouldRun =
            ProcessInfo.processInfo.environment[OneShotProbeEnvironment.hostPassthruBridgePrepEnvKey] == "1"
                || Foundation.FileManager().fileExists(atPath: hostPassthruBridgePrepTriggerPath)

        guard shouldRun else { return false }

        try? Foundation.FileManager().removeItem(atPath: hostPassthruBridgePrepTriggerPath)
        AppLogger.shared.info("🧪 [OneShotProbe] Preparing experimental host passthru bridge environment and exiting")
        Task { @MainActor in
            do {
                let bridgeEnvironment = try await KanataRuntimePathCoordinator.prepareExperimentalOutputBridgeEnvironment(
                    hostPID: getpid()
                )
                let sessionID = bridgeEnvironment[KanataRuntimePathCoordinator.experimentalOutputBridgeSessionEnvKey] ?? "missing"
                let socketPath = bridgeEnvironment[KanataRuntimePathCoordinator.experimentalOutputBridgeSocketEnvKey] ?? "missing"
                let payload = """
                session=\(sessionID)
                socket=\(socketPath)

                """
                try payload.write(
                    toFile: hostPassthruBridgePrepOutputPath,
                    atomically: true,
                    encoding: .utf8
                )
                AppLogger.shared.info(
                    "🧪 [OneShotProbe] Prepared experimental host passthru bridge environment session=\(sessionID) socket=\(socketPath)"
                )
                FileHandle.standardError.write(
                    Data(
                        """
                        [keypath-host-passthru-bridge]
                        session=\(sessionID)
                        socket=\(socketPath)
                        output=\(hostPassthruBridgePrepOutputPath)

                        """.utf8
                    )
                )
                FileHandle.standardError.synchronizeFile()
                Foundation.exit(0)
            } catch {
                let message = error.localizedDescription
                AppLogger.shared.error("🧪 [OneShotProbe] Host passthru bridge preparation failed: \(message)")
                FileHandle.standardError.write(
                    Data(
                        """
                        [keypath-host-passthru-bridge]
                        error=\(message)

                        """.utf8
                    )
                )
                FileHandle.standardError.synchronizeFile()
                Foundation.exit(1)
            }
        }
        return true
    }

    // MARK: - Helper Repair

    private static func handleHelperRepair() -> Bool {
        let shouldRun =
            ProcessInfo.processInfo.environment[OneShotProbeEnvironment.helperRepairEnvKey] == "1"
                || Foundation.FileManager().fileExists(atPath: helperRepairTriggerPath)

        guard shouldRun else { return false }

        try? Foundation.FileManager().removeItem(atPath: helperRepairTriggerPath)
        AppLogger.shared.info("🧪 [OneShotProbe] Running helper cleanup/repair and exiting")
        let useAppleScriptFallbackRaw = ProcessInfo.processInfo.environment["KEYPATH_HELPER_REPAIR_USE_APPLESCRIPT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let useAppleScriptFallback = useAppleScriptFallbackRaw == nil
            || useAppleScriptFallbackRaw == "1"
            || useAppleScriptFallbackRaw == "true"
            || useAppleScriptFallbackRaw == "yes"
        Task { @MainActor in
            let repaired = await HelperMaintenance.shared.runCleanupAndRepair(
                useAppleScriptFallback: useAppleScriptFallback
            )
            let details = HelperMaintenance.shared.logLines.joined(separator: " | ")
            FileHandle.standardError.write(
                Data(
                    """
                    [keypath-helper-repair]
                    success=\(repaired)
                    use_apple_script_fallback=\(useAppleScriptFallback)
                    details=\(details)

                    """.utf8
                )
            )
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    // MARK: - Companion Restart Probe

    private static func handleCompanionRestartProbe() -> Bool {
        let shouldRun =
            ProcessInfo.processInfo.environment[OneShotProbeEnvironment.companionRestartProbeEnvKey] == "1"

        guard shouldRun else { return false }

        let captureRaw = ProcessInfo.processInfo.environment[AppDelegate.hostPassthruCaptureEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let includeCapture = captureRaw == "1" || captureRaw == "true" || captureRaw == "yes"

        AppLogger.shared.info(
            "🧪 [OneShotProbe] Running output bridge companion restart probe and exiting"
        )
        Task { @MainActor in
            do {
                var lines: [String] = []
                if let statusBefore = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                    lines.append("companion_running_before=\(statusBefore.companionRunning)")
                } else {
                    lines.append("companion_running_before=unknown")
                }
                lines.append("capture=\(includeCapture)")

                let pid = try await KanataSplitRuntimeHostService.shared.startPersistentPassthruHost(
                    includeCapture: includeCapture
                )
                lines.append("host_pid=\(pid)")
                try await Task.sleep(for: .milliseconds(300))

                do {
                    try await KanataOutputBridgeCompanionManager.shared.restartCompanion()
                    lines.append("companion_restarted=1")
                } catch {
                    lines.append("companion_restarted=0")
                    lines.append(
                        "companion_restart_error=\(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
                    )
                }
                try await Task.sleep(for: .milliseconds(500))

                if let statusAfter = try? await KanataOutputBridgeCompanionManager.shared.outputBridgeStatus() {
                    lines.append("companion_running_after=\(statusAfter.companionRunning)")
                } else {
                    lines.append("companion_running_after=unknown")
                }

                KanataSplitRuntimeHostService.shared.stopPersistentPassthruHost()
                lines.append("host_stopped=1")

                let payload = lines.joined(separator: "\n") + "\n"
                try payload.write(
                    toFile: companionRestartProbeOutputPath,
                    atomically: true,
                    encoding: .utf8
                )
                FileHandle.standardError.write(
                    Data(
                        """
                        [keypath-output-bridge-companion-restart]
                        \(payload)
                        """.utf8
                    )
                )
                FileHandle.standardError.synchronizeFile()
                Foundation.exit(0)
            } catch {
                let message = error.localizedDescription
                AppLogger.shared.error(
                    "🧪 [OneShotProbe] Output bridge companion restart probe failed: \(message)"
                )
                FileHandle.standardError.write(
                    Data(
                        """
                        [keypath-output-bridge-companion-restart]
                        error=\(message)

                        """.utf8
                    )
                )
                FileHandle.standardError.synchronizeFile()
                Foundation.exit(1)
            }
        }
        return true
    }
}
