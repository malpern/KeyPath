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
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
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
}

// FeatureFlags manages its own synchronization.
// Mark unchecked to silence Swift 6 Sendable warnings for cross-actor access.
extension FeatureFlags: @unchecked Sendable {}

// MARK: - Persisted flags (UserDefaults-backed)

extension FeatureFlags {
    private static let captureListenOnlyKey = "CAPTURE_LISTEN_ONLY_ENABLED"
    private static let useSMAppServiceForDaemonKey = "USE_SMAPPSERVICE_FOR_DAEMON"
    private static let simulatorAndVirtualKeysEnabledKey = "SIMULATOR_AND_VIRTUAL_KEYS_ENABLED"
    private static let useJustInTimePermissionRequestsKey = "USE_JIT_PERMISSION_REQUESTS"
    private static let allowOptionalWizardKey = "ALLOW_OPTIONAL_WIZARD"
    private static let keyboardSuppressionDebugEnabledKey = "KEYBOARD_SUPPRESSION_DEBUG_ENABLED"
    private static let uninstallForTestingKey = "UNINSTALL_FOR_TESTING"

    // MARK: - Active Feature Flags

    /// CGEvent tap listen-only mode (default ON)
    /// When enabled, KeyPath only listens to key events without modifying them.
    static var captureListenOnlyEnabled: Bool {
        if UserDefaults.standard.object(forKey: captureListenOnlyKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: captureListenOnlyKey)
    }

    static func setCaptureListenOnlyEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: captureListenOnlyKey)
    }

    /// Whether to use SMAppService for Kanata daemon management (default ON)
    /// When enabled, uses SMAppService instead of launchctl for daemon registration.
    static var useSMAppServiceForDaemon: Bool {
        if UserDefaults.standard.object(forKey: useSMAppServiceForDaemonKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: useSMAppServiceForDaemonKey)
    }

    static func setUseSMAppServiceForDaemon(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useSMAppServiceForDaemonKey)
    }

    /// Enable simulator for layer mapping and virtual key actions (default ON)
    /// Required for overlay to show correct remapped key labels.
    static var simulatorAndVirtualKeysEnabled: Bool {
        if UserDefaults.standard.object(forKey: simulatorAndVirtualKeysEnabledKey) == nil {
            return true // default ON - needed for correct overlay labels
        }
        return UserDefaults.standard.bool(forKey: simulatorAndVirtualKeysEnabledKey)
    }

    static func setSimulatorAndVirtualKeysEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: simulatorAndVirtualKeysEnabledKey)
    }

    /// Verbose logging for keyboard suppression decisions (default OFF).
    static var keyboardSuppressionDebugEnabled: Bool {
        if UserDefaults.standard.object(forKey: keyboardSuppressionDebugEnabledKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: keyboardSuppressionDebugEnabledKey)
    }

    static func setKeyboardSuppressionDebugEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: keyboardSuppressionDebugEnabledKey)
    }

    /// Reset TCC permissions and preferences on uninstall for fresh install testing (default ON)
    /// When enabled, uninstall also clears Accessibility, Input Monitoring, and Full Disk Access
    /// permissions plus UserDefaults, allowing a true "first launch" experience.
    static var uninstallForTesting: Bool {
        if UserDefaults.standard.object(forKey: uninstallForTestingKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: uninstallForTestingKey)
    }

    static func setUninstallForTesting(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: uninstallForTestingKey)
    }

    // MARK: - Future Implementation (not yet built)

    /// Phase 2: Just-in-time permission requests (NOT YET IMPLEMENTED)
    /// Will allow requesting permissions only when needed rather than upfront.
    static var useJustInTimePermissionRequests: Bool {
        if UserDefaults.standard.object(forKey: useJustInTimePermissionRequestsKey) == nil {
            return false // default OFF - not implemented
        }
        return UserDefaults.standard.bool(forKey: useJustInTimePermissionRequestsKey)
    }

    static func setUseJustInTimePermissionRequests(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useJustInTimePermissionRequestsKey)
    }

    /// Phase 3: Optional wizard - non-blocking setup (NOT YET IMPLEMENTED)
    /// Will allow skipping the wizard and configuring later.
    static var allowOptionalWizard: Bool {
        if UserDefaults.standard.object(forKey: allowOptionalWizardKey) == nil {
            return false // default OFF - not implemented
        }
        return UserDefaults.standard.bool(forKey: allowOptionalWizardKey)
    }

    static func setAllowOptionalWizard(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: allowOptionalWizardKey)
    }
}
