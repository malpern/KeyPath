import Foundation

/// Single source of truth for detecting one-shot probe mode.
///
/// One-shot probe mode is active when the app was launched with one of the
/// special environment variables that trigger a single diagnostic action and
/// then exit. In this mode, heavy initialization (bootstrap, event monitoring,
/// notification registration, etc.) is skipped.
enum OneShotProbeEnvironment {
    static let hostPassthruDiagnosticEnvKey = "KEYPATH_ENABLE_HOST_PASSTHRU_DIAGNOSTIC"
    static let hostPassthruBridgePrepEnvKey = "KEYPATH_PREPARE_HOST_PASSTHRU_BRIDGE"
    static let helperRepairEnvKey = "KEYPATH_RUN_HELPER_REPAIR"
    static let companionRestartProbeEnvKey = "KEYPATH_EXERCISE_OUTPUT_BRIDGE_COMPANION_RESTART"

    static func isActive(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[hostPassthruDiagnosticEnvKey] == "1"
            || environment[hostPassthruBridgePrepEnvKey] == "1"
            || environment[helperRepairEnvKey] == "1"
            || environment[companionRestartProbeEnvKey] == "1"
    }
}
