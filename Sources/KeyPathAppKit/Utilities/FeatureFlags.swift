import Foundation
import KeyPathCore

/// Centralized runtime flags for the current process.
///
/// Avoids using environment variables for intra-process feature switches,
/// preventing accidental inheritance by child processes and racey global state.
final class FeatureFlags {
    static let shared = FeatureFlags()

    private let stateQueue = DispatchQueue(
        label: "com.keypath.featureflags.state", qos: .userInitiated
    )

    // MARK: - Startup Mode

    private var _startupModeActive: Bool = false

    /// Test seam: allow injecting startup mode during unit tests
    nonisolated(unsafe) static var testStartupMode: Bool?

    /// True while we want to avoid potentially-blocking permission checks during early startup.
    var startupModeActive: Bool {
        // Test seam: use injected value in tests
        if TestEnvironment.isRunningTests, let override = Self.testStartupMode {
            return override
        }
        return stateQueue.sync { _startupModeActive }
    }

    /// Activate startup mode, optionally auto-deactivating after a timeout.
    func activateStartupMode(timeoutSeconds: Double = 5.0) {
        stateQueue.sync { _startupModeActive = true }
        if timeoutSeconds > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard let self else { return }
                if startupModeActive {
                    deactivateStartupMode()
                }
            }
        }
    }

    /// Deactivate startup mode.
    func deactivateStartupMode() {
        stateQueue.sync { _startupModeActive = false }
    }

    // MARK: - Auto Trigger (currently in-process only)

    private var _autoTriggerEnabled: Bool = false

    var autoTriggerEnabled: Bool { stateQueue.sync { _autoTriggerEnabled } }

    func setAutoTriggerEnabled(_ enabled: Bool) {
        stateQueue.sync { _autoTriggerEnabled = enabled }
    }
}

// FeatureFlags manages its own synchronization.
// Mark unchecked to silence Swift 6 Sendable warnings for cross-actor access.
extension FeatureFlags: @unchecked Sendable {}

// MARK: - Persisted flags (UserDefaults-backed)

extension FeatureFlags {
    private static let captureListenOnlyKey = "CAPTURE_LISTEN_ONLY_ENABLED"
    private static let tcpProtocolV2Key = "TCP_PROTOCOL_V2_ENABLED"
    private static let useAutomaticPermissionPromptsKey = "USE_AUTOMATIC_PERMISSION_PROMPTS"
    private static let useJustInTimePermissionRequestsKey = "USE_JIT_PERMISSION_REQUESTS"
    private static let allowOptionalWizardKey = "ALLOW_OPTIONAL_WIZARD"
    private static let useUnifiedWizardRouterKey = "USE_UNIFIED_WIZARD_ROUTER"

    static var captureListenOnlyEnabled: Bool {
        if UserDefaults.standard.object(forKey: captureListenOnlyKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: captureListenOnlyKey)
    }

    static func setCaptureListenOnlyEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: captureListenOnlyKey)
    }

    // MARK: - Protocol flags

    static var tcpProtocolV2Enabled: Bool {
        if UserDefaults.standard.object(forKey: tcpProtocolV2Key) == nil {
            return true // default ON (canary-friendly)
        }
        return UserDefaults.standard.bool(forKey: tcpProtocolV2Key)
    }

    static func setTcpProtocolV2Enabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: tcpProtocolV2Key)
    }

    // MARK: - SMAppService Daemon Management

    private static let useSMAppServiceForDaemonKey = "USE_SMAPPSERVICE_FOR_DAEMON"

    /// Whether to use SMAppService for Kanata daemon management (default: true)
    /// When enabled, uses SMAppService instead of launchctl for daemon registration
    static var useSMAppServiceForDaemon: Bool {
        let userDefaultsValue = UserDefaults.standard.object(forKey: useSMAppServiceForDaemonKey)
        let defaultValue = true // default ON (use SMAppService)

        if userDefaultsValue == nil {
            // Logging removed to avoid import dependency - can be added back if needed
            return defaultValue
        }

        let boolValue = UserDefaults.standard.bool(forKey: useSMAppServiceForDaemonKey)
        // Logging removed to avoid import dependency - can be added back if needed
        return boolValue
    }

    static func setUseSMAppServiceForDaemon(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useSMAppServiceForDaemonKey)
    }

    // MARK: - Permission UX flags

    /// Phase 1: Automatic system prompts for KeyPath.app (default ON)
    static var useAutomaticPermissionPrompts: Bool {
        if UserDefaults.standard.object(forKey: useAutomaticPermissionPromptsKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: useAutomaticPermissionPromptsKey)
    }

    static func setUseAutomaticPermissionPrompts(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useAutomaticPermissionPromptsKey)
    }

    /// Phase 2: Just-in-time permission requests (default OFF)
    static var useJustInTimePermissionRequests: Bool {
        if UserDefaults.standard.object(forKey: useJustInTimePermissionRequestsKey) == nil {
            return false // default OFF
        }
        return UserDefaults.standard.bool(forKey: useJustInTimePermissionRequestsKey)
    }

    static func setUseJustInTimePermissionRequests(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useJustInTimePermissionRequestsKey)
    }

    /// Phase 3: Optional wizard (non-blocking) (default OFF)
    static var allowOptionalWizard: Bool {
        if UserDefaults.standard.object(forKey: allowOptionalWizardKey) == nil {
            return false // default OFF
        }
        return UserDefaults.standard.bool(forKey: allowOptionalWizardKey)
    }

    static func setAllowOptionalWizard(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: allowOptionalWizardKey)
    }

    // MARK: - Wizard routing

    /// Enable the unified, pure-function wizard router/state-machine path.
    /// Default ON to match test expectations; can be flipped off for emergency rollback.
    static var useUnifiedWizardRouter: Bool {
        if UserDefaults.standard.object(forKey: useUnifiedWizardRouterKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: useUnifiedWizardRouterKey)
    }

    static func setUseUnifiedWizardRouter(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useUnifiedWizardRouterKey)
    }
}
