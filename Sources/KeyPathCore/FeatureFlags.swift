import Foundation

public final class FeatureFlags {
    public static let shared = FeatureFlags()

    private let stateQueue = DispatchQueue(
        label: "com.keypath.featureflags.state", qos: .userInitiated
    )

    // MARK: - Startup Mode

    private var _startupModeActive: Bool = false

    /// Test seam: allow injecting startup mode during unit tests
    public nonisolated(unsafe) static var testStartupMode: Bool?

    /// True while we want to avoid potentially-blocking permission checks during early startup.
    public var startupModeActive: Bool {
        // Test seam: use injected value in tests
        if TestEnvironment.isRunningTests, let override = Self.testStartupMode {
            return override
        }
        return stateQueue.sync { _startupModeActive }
    }

    /// Activate startup mode, optionally auto-deactivating after a timeout.
    public func activateStartupMode(timeoutSeconds: Double = 5.0) {
        stateQueue.sync { _startupModeActive = true }
        if timeoutSeconds > 0 {
            Task { @MainActor [weak self] in
                try await Task.sleep(for: .seconds(timeoutSeconds))
                guard let self else { return }
                if startupModeActive {
                    deactivateStartupMode()
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
    private static let tahoeInputMonitoringWorkaroundKey = "TAHOE_INPUT_MONITORING_UI_WORKAROUND"

    static var captureListenOnlyEnabled: Bool {
        if UserDefaults.standard.object(forKey: captureListenOnlyKey) == nil {
            return true // default ON
        }
        return UserDefaults.standard.bool(forKey: captureListenOnlyKey)
    }

    static func setCaptureListenOnlyEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: captureListenOnlyKey)
    }

    /// Workaround for macOS 15/26 "Tahoe" Input Monitoring UI bug where CLI binaries added via the
    /// System Settings “+” button do not appear in the list even though TCC grants them permission.
    /// KeyPath uses this flag to trust the TCC row and avoid trapping users in a broken Fix loop.
    static var tahoeInputMonitoringWorkaroundEnabled: Bool {
        if UserDefaults.standard.object(forKey: tahoeInputMonitoringWorkaroundKey) == nil {
            return true // default ON until Apple ships a fix
        }
        return UserDefaults.standard.bool(forKey: tahoeInputMonitoringWorkaroundKey)
    }

    static func setTahoeInputMonitoringWorkaroundEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: tahoeInputMonitoringWorkaroundKey)
    }
}
