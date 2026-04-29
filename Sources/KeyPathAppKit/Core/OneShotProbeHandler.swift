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
    private static let helperRepairTriggerPath = "/var/tmp/keypath-helper-repair"

    static func handleIfNeeded() -> Bool {
        if handleHelperRepair() { return true }
        return false
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

}
