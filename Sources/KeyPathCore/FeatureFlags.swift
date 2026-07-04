import Foundation

public final class FeatureFlags {
    public static let shared = FeatureFlags()

    private let stateQueue = DispatchQueue(
        label: "com.keypath.featureflags.state", qos: .userInitiated
    )

    // MARK: - Startup Mode

    private var _startupModeActive: Bool = false

    // Test seam: allow injecting startup mode during unit tests
    #if DEBUG
        public nonisolated(unsafe) static var testStartupMode: Bool?
    #endif

    /// True while we want to avoid potentially-blocking permission checks during early startup.
    public var startupModeActive: Bool {
        // Test seam: use injected value in tests
        #if DEBUG
            if TestEnvironment.isRunningTests, let override = Self.testStartupMode {
                return override
            }
        #endif
        return stateQueue.sync { _startupModeActive }
    }

    /// Activate startup mode. Deactivated explicitly by MainAppStateController
    /// once services are ready — no auto-timeout.
    public func activateStartupMode() {
        stateQueue.sync { _startupModeActive = true }
    }

    /// Deactivate startup mode.
    public func deactivateStartupMode() {
        stateQueue.sync { _startupModeActive = false }
    }
}

/// FeatureFlags manages its own synchronization.
/// Mark unchecked to silence Swift 6 Sendable warnings for cross-actor access.
extension FeatureFlags: @unchecked Sendable {}

// MARK: - Persisted flags (UserDefaults-backed)

public extension FeatureFlags {
    /// In-memory flag store used instead of `UserDefaults.standard` while running tests.
    ///
    /// `UserDefaults.standard` is process-global AND persistent, so a test suite that
    /// flips a flag can leak state into every other suite in the run (and into later
    /// runs, or the developer's real app) if a throw skips its tearDown — the exact
    /// mechanism behind the #896 RemapEndToEndTests flake. Under
    /// `TestEnvironment.isRunningTests`, flag setters write here and readers resolve
    /// override-then-compiled-default, never touching real UserDefaults.
    private enum TestOverrides {
        static let lock = NSLock()
        nonisolated(unsafe) static var values: [String: Any] = [:]

        static func value(forKey key: String) -> Any? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        static func set(_ value: Any, forKey key: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }

        static func reset() {
            lock.lock()
            defer { lock.unlock() }
            values.removeAll()
        }
    }

    /// Memoized: the detection signals are process-stable, and re-evaluating them
    /// (Bundle.allBundles scan) on every flag read is wasteful.
    private static let isRunningTests = TestEnvironment.isRunningTests

    /// Clear all in-memory test overrides, returning every flag to its compiled
    /// default. Called between tests (KeyPathTestCase) and by suites that flip flags.
    static func resetTestOverrides() {
        TestOverrides.reset()
    }

    private static func boolFlag(forKey key: String, default defaultValue: Bool) -> Bool {
        if isRunningTests {
            return TestOverrides.value(forKey: key) as? Bool ?? defaultValue
        }
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func setBoolFlag(_ enabled: Bool, forKey key: String) {
        if isRunningTests {
            TestOverrides.set(enabled, forKey: key)
            return
        }
        UserDefaults.standard.set(enabled, forKey: key)
    }

    private static func stringFlag(forKey key: String) -> String? {
        if isRunningTests {
            return TestOverrides.value(forKey: key) as? String
        }
        return UserDefaults.standard.string(forKey: key)
    }

    private static func setStringFlag(_ value: String, forKey key: String) {
        if isRunningTests {
            TestOverrides.set(value, forKey: key)
            return
        }
        UserDefaults.standard.set(value, forKey: key)
    }

    private static let captureListenOnlyKey = "CAPTURE_LISTEN_ONLY_ENABLED"
    private static let useSMAppServiceForDaemonKey = "USE_SMAPPSERVICE_FOR_DAEMON"
    private static let simulatorAndVirtualKeysEnabledKey = "SIMULATOR_AND_VIRTUAL_KEYS_ENABLED"
    private static let useJustInTimePermissionRequestsKey = "USE_JIT_PERMISSION_REQUESTS"
    private static let allowOptionalWizardKey = "ALLOW_OPTIONAL_WIZARD"
    private static let keyboardSuppressionDebugEnabledKey = "KEYBOARD_SUPPRESSION_DEBUG_ENABLED"
    private static let uninstallForTestingKey = "UNINSTALL_FOR_TESTING"
    private static let learningTipsModeKey = "LEARNING_TIPS_MODE"
    private static let contextHUDListEnabledKey = "CONTEXT_HUD_LIST_ENABLED"

    // MARK: - Active Feature Flags

    /// CGEvent tap listen-only mode (default ON)
    /// When enabled, KeyPath only listens to key events without modifying them.
    static var captureListenOnlyEnabled: Bool {
        boolFlag(forKey: captureListenOnlyKey, default: true)
    }

    static func setCaptureListenOnlyEnabled(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: captureListenOnlyKey)
    }

    /// Whether to use SMAppService for Kanata daemon management (default ON)
    /// When enabled, uses SMAppService instead of launchctl for daemon registration.
    static var useSMAppServiceForDaemon: Bool {
        boolFlag(forKey: useSMAppServiceForDaemonKey, default: true)
    }

    static func setUseSMAppServiceForDaemon(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: useSMAppServiceForDaemonKey)
    }

    /// Enable simulator for layer mapping and virtual key actions (default ON)
    /// Required for overlay to show correct remapped key labels.
    static var simulatorAndVirtualKeysEnabled: Bool {
        // default ON - needed for correct overlay labels
        boolFlag(forKey: simulatorAndVirtualKeysEnabledKey, default: true)
    }

    static func setSimulatorAndVirtualKeysEnabled(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: simulatorAndVirtualKeysEnabledKey)
    }

    /// Verbose logging for keyboard suppression decisions (default OFF).
    static var keyboardSuppressionDebugEnabled: Bool {
        boolFlag(forKey: keyboardSuppressionDebugEnabledKey, default: false)
    }

    static func setKeyboardSuppressionDebugEnabled(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: keyboardSuppressionDebugEnabledKey)
    }

    /// Reset TCC permissions and preferences on uninstall for fresh install testing (default OFF)
    /// When enabled, uninstall also clears Accessibility, Input Monitoring, and Full Disk Access
    /// permissions plus UserDefaults, allowing a true "first launch" experience.
    static var uninstallForTesting: Bool {
        // default OFF for production
        boolFlag(forKey: uninstallForTestingKey, default: false)
    }

    static func setUninstallForTesting(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: uninstallForTestingKey)
    }

    /// Learning tips display mode
    /// - untilLearned: Show tips until user demonstrates proficiency (default)
    /// - alwaysOn: Always show tips regardless of learned state
    /// - off: Never show learning tips
    static var learningTipsMode: LearningTipsMode {
        if let rawValue = stringFlag(forKey: learningTipsModeKey),
           let mode = LearningTipsMode(rawValue: rawValue)
        {
            return mode
        }
        return .off // default
    }

    static func setLearningTipsMode(_ mode: LearningTipsMode) {
        setStringFlag(mode.rawValue, forKey: learningTipsModeKey)
    }

    /// Context HUD floating list window (default ON)
    /// When enabled, shows a compact key list alongside or instead of the keyboard overlay.
    static var contextHUDListEnabled: Bool {
        boolFlag(forKey: contextHUDListEnabledKey, default: true)
    }

    static func setContextHUDListEnabled(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: contextHUDListEnabledKey)
    }

    // MARK: - Future Implementation (not yet built)

    /// Phase 2: Just-in-time permission requests (NOT YET IMPLEMENTED)
    /// Will allow requesting permissions only when needed rather than upfront.
    static var useJustInTimePermissionRequests: Bool {
        // default OFF - not implemented
        boolFlag(forKey: useJustInTimePermissionRequestsKey, default: false)
    }

    static func setUseJustInTimePermissionRequests(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: useJustInTimePermissionRequestsKey)
    }

    /// Phase 3: Optional wizard - non-blocking setup (NOT YET IMPLEMENTED)
    /// Will allow skipping the wizard and configuring later.
    static var allowOptionalWizard: Bool {
        // default OFF - not implemented
        boolFlag(forKey: allowOptionalWizardKey, default: false)
    }

    static func setAllowOptionalWizard(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: allowOptionalWizardKey)
    }
}

// MARK: - Learning Tips Mode

/// Controls when contextual learning tips are displayed
public enum LearningTipsMode: String, CaseIterable {
    /// Show tips until user demonstrates proficiency (default)
    case untilLearned = "until_learned"
    /// Always show tips regardless of learned state
    case alwaysOn = "always_on"
    /// Never show learning tips
    case off

    public var displayName: String {
        switch self {
        case .untilLearned: "Until Learned"
        case .alwaysOn: "Always On"
        case .off: "Off"
        }
    }
}
