import Foundation
import KeyPathCore

// MARK: - Release Milestone Gating

/// Controls which features are available in each release.
///
/// To prepare for a release:
/// 1. Set `ReleaseMilestone.defaultMilestone` to the target milestone
/// 2. Build and test - hidden features won't appear in UI
/// 3. When ready for next release, bump the milestone
///
/// Features are cumulative - R2 includes everything from R1.
///
/// Secret toggle: Cmd+Option+Shift+R cycles through milestones at runtime.
enum ReleaseMilestone: Int, Comparable, CaseIterable {
    /// R1: Installer + Custom Rules Only (thin Kanata fork ~480 lines)
    /// - Installation Wizard, Permissions, VHID Driver
    /// - LaunchDaemon, Privileged Helper
    /// - Rules Tab with Custom Rules only (no Rule Collections)
    /// - Config Generation, Hot Reload, Validation
    case r1_installer_rules = 1

    /// R2: Full Features (full Kanata fork ~700 lines)
    /// - Rule Collections (Vim, Caps Lock, Home Row Mods, etc.)
    /// - Live Keyboard Overlay
    /// - Mapper UI
    /// - Simulator Tab
    /// - HoldActivated telemetry, Action URIs, Virtual Keys Inspector
    case r2_overlay_mapper = 2

    /// The default milestone for this build. Change before release.
    static let defaultMilestone: ReleaseMilestone = .r1_installer_rules

    private static let userDefaultsKey = "KEYPATH_RELEASE_MILESTONE_OVERRIDE"

    /// The current active milestone (may be overridden at runtime via secret toggle)
    static var current: ReleaseMilestone {
        if let override = UserDefaults.standard.object(forKey: userDefaultsKey) as? Int,
           let milestone = ReleaseMilestone(rawValue: override)
        {
            return milestone
        }
        return defaultMilestone
    }

    /// Cycle to the next milestone (wraps around). Returns the new milestone.
    @discardableResult
    static func cycleToNext() -> ReleaseMilestone {
        let allCases = ReleaseMilestone.allCases
        guard let currentIndex = allCases.firstIndex(of: current) else {
            return current
        }
        let nextIndex = (currentIndex + 1) % allCases.count
        let next = allCases[nextIndex]
        UserDefaults.standard.set(next.rawValue, forKey: userDefaultsKey)
        return next
    }

    /// Reset to the default milestone for this build
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    var displayName: String {
        switch self {
        case .r1_installer_rules: "R1 (Installer + Rules)"
        case .r2_overlay_mapper: "R2 (Full Features)"
        }
    }

    static func < (lhs: ReleaseMilestone, rhs: ReleaseMilestone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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

    // MARK: - Release Milestone Feature Gates

    /// Simulator tab - available in R2+
    static var simulatorEnabled: Bool {
        ReleaseMilestone.current >= .r2_overlay_mapper
    }

    /// Live Keyboard Overlay - available in R2+
    static var overlayEnabled: Bool {
        ReleaseMilestone.current >= .r2_overlay_mapper
    }

    /// Mapper window - available in R2+
    static var mapperEnabled: Bool {
        ReleaseMilestone.current >= .r2_overlay_mapper
    }

    /// Input Capture Experiment - only in R2+ (will be removed before final R2)
    static var inputCaptureExperimentEnabled: Bool {
        ReleaseMilestone.current >= .r2_overlay_mapper
    }

    /// Virtual Keys Inspector - available in R2+ (requires simulator/overlay features)
    static var virtualKeysInspectorEnabled: Bool {
        ReleaseMilestone.current >= .r2_overlay_mapper
    }

    /// Rule Collections (Vim, Caps Lock, Home Row Mods, Leader Key, etc.) - available in R2+
    /// Custom Rules are always available (R1+)
    static var ruleCollectionsEnabled: Bool {
        ReleaseMilestone.current >= .r2_overlay_mapper
    }
}
