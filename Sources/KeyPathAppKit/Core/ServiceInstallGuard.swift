import Foundation

/// Pure decision logic for whether to install/reinstall LaunchDaemon services.
/// Extracted from PrivilegedOperationsCoordinator so it survives refactoring
/// and can be tested independently of the privileged operations layer.
@MainActor
enum ServiceInstallGuard {
    enum Decision: Equatable {
        case skipNoInstall
        case skipPendingApproval
        case throttled(remaining: TimeInterval)
        case run(reason: String, bypassedThrottle: Bool)
    }

    private static let installThrottle: TimeInterval = 30
    private static let staleRecoveryBypassLimit = 3
    static var staleRecoveryAttemptCount = 0

    static func decide(
        state: KanataDaemonManager.ServiceManagementState,
        staleEnabledRegistration: Bool,
        now: Date,
        lastAttempt: Date?
    ) -> Decision {
        if state == .smappservicePending {
            return .skipPendingApproval
        }

        let requiresInstall = state.needsInstallation || state.needsMigration() || staleEnabledRegistration
        guard requiresInstall else {
            staleRecoveryAttemptCount = 0
            return .skipNoInstall
        }

        if staleEnabledRegistration {
            staleRecoveryAttemptCount += 1
            if staleRecoveryAttemptCount <= staleRecoveryBypassLimit {
                return .run(
                    reason: "stale-enabled-registration (recovery-attempt=\(staleRecoveryAttemptCount))",
                    bypassedThrottle: true
                )
            }
        } else {
            staleRecoveryAttemptCount = 0
        }

        if let lastAttempt,
           now.timeIntervalSince(lastAttempt) < installThrottle
        {
            let remaining = installThrottle - now.timeIntervalSince(lastAttempt)
            return .throttled(remaining: remaining)
        }

        if staleEnabledRegistration {
            return .run(
                reason: "stale-enabled-registration (throttle-applied after \(staleRecoveryBypassLimit) bypasses)",
                bypassedThrottle: false
            )
        }

        return .run(reason: "state=\(state.description)", bypassedThrottle: false)
    }

    static func reset() {
        staleRecoveryAttemptCount = 0
    }
}

/// Result of verifying kanata runtime readiness after an install or restart.
enum KanataReadinessResult: Equatable {
    case ready
    case pendingApproval
    case staleRegistration
    case launchctlNotFoundPersistent
    case tcpPortInUse
    case timedOut

    var isSuccess: Bool {
        self == .ready || self == .pendingApproval
    }

    var failureDescription: String {
        switch self {
        case .ready:
            "Kanata readiness verified"
        case .pendingApproval:
            "SMAppService approval pending"
        case .staleRegistration:
            "SMAppService registration is enabled but launchd cannot load the service"
        case .launchctlNotFoundPersistent:
            "launchctl repeatedly reported the Kanata service as not found"
        case .tcpPortInUse:
            "TCP port 37001 is already in use by an existing Kanata runtime"
        case .timedOut:
            "Kanata did not become running + TCP responsive within readiness timeout"
        }
    }
}

// MARK: - Error Types

enum PrivilegedOperationError: LocalizedError {
    case installationFailed(String)
    case operationFailed(String)
    case commandFailed(description: String, exitCode: Int32, output: String)
    case executionError(description: String, error: Error)

    var errorDescription: String? {
        switch self {
        case let .installationFailed(message):
            "Installation failed: \(message)"
        case let .operationFailed(message):
            "Operation failed: \(message)"
        case let .commandFailed(description, exitCode, output):
            "Command failed (\(description)): exit code \(exitCode)\nOutput: \(output)"
        case let .executionError(description, error):
            "Execution error (\(description)): \(error.localizedDescription)"
        }
    }
}
