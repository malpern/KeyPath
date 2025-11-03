import Foundation

public final class FeatureFlags {
    public static let shared = FeatureFlags()

    private let stateQueue = DispatchQueue(label: "com.keypath.featureflags.state", qos: .userInitiated)

    // MARK: - Startup Mode

    private var _startupModeActive: Bool = false

    /// True while we want to avoid potentially-blocking permission checks during early startup.
    public var startupModeActive: Bool { stateQueue.sync { _startupModeActive } }

    /// Activate startup mode, optionally auto-deactivating after a timeout.
    public func activateStartupMode(timeoutSeconds: Double = 5.0) {
        stateQueue.sync { _startupModeActive = true }
        if timeoutSeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                guard let self else { return }
                if self.startupModeActive {
                    self.deactivateStartupMode()
                }
            }
        }
    }

    /// Deactivate startup mode.
    public func deactivateStartupMode() {
        stateQueue.sync { _startupModeActive = false }
    }

    // MARK: - Auto Trigger (currently in-process only)

    private var _autoTriggerEnabled: Bool = false

    public var autoTriggerEnabled: Bool { stateQueue.sync { _autoTriggerEnabled } }

    public func setAutoTriggerEnabled(_ enabled: Bool) {
        stateQueue.sync { _autoTriggerEnabled = enabled }
    }
}
// FeatureFlags manages its own synchronization.
// Mark unchecked to silence Swift 6 Sendable warnings for cross-actor access.
extension FeatureFlags: @unchecked Sendable {}

// MARK: - Persisted flags (UserDefaults-backed)
public extension FeatureFlags {
    private static let captureListenOnlyKey = "CAPTURE_LISTEN_ONLY_ENABLED"
    private static let useConfigApplyPipelineKey = "USE_CONFIG_APPLY_PIPELINE"

    static var captureListenOnlyEnabled: Bool {
        if UserDefaults.standard.object(forKey: captureListenOnlyKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: captureListenOnlyKey)
    }

    static func setCaptureListenOnlyEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: captureListenOnlyKey)
    }

    /// Feature-gated rollout for the new ConfigApplyPipeline actor.
    /// Defaults to false. Persisted in UserDefaults.
    static var useConfigApplyPipeline: Bool {
        if UserDefaults.standard.object(forKey: useConfigApplyPipelineKey) == nil {
            return false // default OFF
        }
        return UserDefaults.standard.bool(forKey: useConfigApplyPipelineKey)
    }

    static func setUseConfigApplyPipeline(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: useConfigApplyPipelineKey)
    }
}