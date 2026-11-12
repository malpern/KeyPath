import Foundation
import Synchronization

public final class FeatureFlags: Sendable {
    public static let shared = FeatureFlags()

    private let startupMode = Mutex(false)

    // Test seam: allow injecting startup mode during unit tests
    #if DEBUG
        private static let startupModeOverride = Mutex<Bool?>(nil)

        public static var testStartupMode: Bool? {
            get { startupModeOverride.withLock { $0 } }
            set { startupModeOverride.withLock { $0 = newValue } }
        }
    #endif

    /// True while we want to avoid potentially-blocking permission checks during early startup.
    public var startupModeActive: Bool {
        // Test seam: use injected value in tests
        #if DEBUG
            if TestEnvironment.isRunningTests, let override = Self.testStartupMode {
                return override
            }
        #endif
        return startupMode.withLock { $0 }
    }

    /// Activate startup mode. Deactivated explicitly by MainAppStateController
    /// once services are ready — no auto-timeout.
    public func activateStartupMode() {
        startupMode.withLock { $0 = true }
    }

    /// Deactivate startup mode.
    public func deactivateStartupMode() {
        startupMode.withLock { $0 = false }
    }
}

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
    private enum TestOverride: Sendable {
        case bool(Bool)
        case string(String)
    }

    private static let testOverrides = Mutex<[String: TestOverride]>([:])

    /// Memoized: the detection signals are process-stable, and re-evaluating them
    /// (Bundle.allBundles scan) on every flag read is wasteful.
    private static let isRunningTests = TestEnvironment.isRunningTests

    /// Clear all in-memory test overrides, returning every flag to its compiled
    /// default. Called between tests (KeyPathTestCase) and by suites that flip flags.
    static func resetTestOverrides() {
        testOverrides.withLock { $0.removeAll() }
    }

    private static func boolFlag(forKey key: String, default defaultValue: Bool) -> Bool {
        if isRunningTests {
            guard case let .bool(value) = testOverrides.withLock({ $0[key] }) else { return defaultValue }
            return value
        }
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func setBoolFlag(_ enabled: Bool, forKey key: String) {
        if isRunningTests {
            testOverrides.withLock { $0[key] = .bool(enabled) }
            return
        }
        UserDefaults.standard.set(enabled, forKey: key)
    }

    private static func stringFlag(forKey key: String) -> String? {
        if isRunningTests {
            guard case let .string(value) = testOverrides.withLock({ $0[key] }) else { return nil }
            return value
        }
        return UserDefaults.standard.string(forKey: key)
    }

    private static func setStringFlag(_ value: String, forKey key: String) {
        if isRunningTests {
            testOverrides.withLock { $0[key] = .string(value) }
            return
        }
        UserDefaults.standard.set(value, forKey: key)
    }

    private static let captureListenOnlyKey = "CAPTURE_LISTEN_ONLY_ENABLED"
    private static let simulatorAndVirtualKeysEnabledKey = "SIMULATOR_AND_VIRTUAL_KEYS_ENABLED"
    private static let keyboardSuppressionDebugEnabledKey = "KEYBOARD_SUPPRESSION_DEBUG_ENABLED"
    private static let uninstallForTestingKey = "UNINSTALL_FOR_TESTING"
    private static let learningTipsModeKey = "LEARNING_TIPS_MODE"
    private static let contextHUDListEnabledKey = "CONTEXT_HUD_LIST_ENABLED"
    private static let keyboardStageRendererKey = "KEYBOARD_STAGE_RENDERER"

    // MARK: - Active Feature Flags

    /// CGEvent tap listen-only mode (default ON)
    /// When enabled, KeyPath only listens to key events without modifying them.
    static var captureListenOnlyEnabled: Bool {
        boolFlag(forKey: captureListenOnlyKey, default: true)
    }

    static func setCaptureListenOnlyEnabled(_ enabled: Bool) {
        setBoolFlag(enabled, forKey: captureListenOnlyKey)
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
    /// When enabled, uninstall also clears KeyPath's privacy permission entries
    /// plus UserDefaults, allowing a true "first launch" experience.
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

    /// First-success keyboard hero renderer.
    ///
    /// Automatic is the production default: prefer Metal when the renderer is
    /// healthy, while retaining the native SwiftUI accessibility fallback.
    static var keyboardStageRendererPreference: KeyboardStageRendererPreference {
        guard let rawValue = stringFlag(forKey: keyboardStageRendererKey),
              let preference = KeyboardStageRendererPreference(rawValue: rawValue)
        else {
            return .automatic
        }
        return preference
    }

    static func setKeyboardStageRendererPreference(_ preference: KeyboardStageRendererPreference) {
        setStringFlag(preference.rawValue, forKey: keyboardStageRendererKey)
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
        case .untilLearned: String(localized: "Until Learned")
        case .alwaysOn: String(localized: "Always On")
        case .off: String(localized: "Off")
        }
    }
}

/// Runtime selection for the first-success keyboard hero.
public enum KeyboardStageRendererPreference: String, CaseIterable, Equatable, Sendable {
    case automatic
    case metal
    case swiftUI = "swiftui"
}
