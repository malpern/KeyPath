import Foundation

/// Utility for detecting test environment and controlling system operations during testing
public enum TestEnvironment {
    /// Check if code is running in test environment
    ///
    /// A false positive here is destructive, not just cosmetic: AppPaths redirects
    /// real user data (~/Library/Logs/KeyPath, ~/Library/Application Support/KeyPath)
    /// into a purgeable temp sandbox, and ActivityLogEncryption switches Keychain
    /// keys. Every signal below must therefore be either in-process proof of a test
    /// run or an explicit test-only opt-in — never an env var that can leak from a
    /// developer's shell into a real KeyPath.app/keypath-cli launch. Signals
    /// rejected for exactly that reason:
    /// - `KEYPATH_USE_SUDO=1` — a dev-workflow flag for *real* app runs (see
    ///   useSudoForPrivilegedOps); it proves nothing about tests
    /// - `__XCODE_BUILT_PRODUCTS_DIR_PATHS` — Xcode sets it for any scheme run,
    ///   including launching the real app
    /// - `DYLD_LIBRARY_PATH` containing ".build" — leaks from any `swift run` shell
    /// - the generic `CI` env var — set by various tools/editors
    public static var isRunningTests: Bool {
        detectionSignals.contains(where: \.present)
    }

    /// Specific CI systems only, NOT the generic "CI" env var — that one is too
    /// common (set by various tools, editors, etc.) and causes false positives
    /// when inherited from a user's shell environment.
    private static let ciIndicators = ["GITHUB_ACTIONS", "TRAVIS", "CIRCLE_CI", "JENKINS_URL"]

    /// The named signals behind `isRunningTests`, in evaluation order. Shared
    /// with `logEnvironmentStatus()` and the detection regression tests so the
    /// implementation, diagnostics, and tests cannot drift apart.
    public static var detectionSignals: [(name: String, present: Bool)] {
        let env = ProcessInfo.processInfo.environment
        let processName = ProcessInfo.processInfo.processName
        return [
            // A test bundle is actually loaded (not just XCTest classes existing).
            // On macOS 26+, XCTestSupport.framework is loaded into all apps, making
            // NSClassFromString("XCTestCase") unreliable for test detection.
            (
                "xctest-bundle-loaded",
                Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
            ),
            // Set by the XCTest/Xcode harness only for actual test invocations
            // (unlike __XCODE_BUILT_PRODUCTS_DIR_PATHS, which any Xcode run gets).
            ("XCTestConfigurationFilePath", env["XCTestConfigurationFilePath"] != nil),
            ("XCTestSessionIdentifier", env["XCTestSessionIdentifier"] != nil),
            // Explicit project opt-in, exported by the test scripts
            // (run-tests-safe.sh, test-lane.sh, run-installer-reliability-matrix.sh)
            // and inherited by any subprocess they spawn.
            ("SWIFT_TEST", env["SWIFT_TEST"] != nil),
            // Test runner process names. swiftpm-testing-helper hosts Swift Testing
            // (@Test) runs, which load no .xctest bundle.
            (
                "test-process-name",
                processName.contains("xctest") || processName.contains("KeyPathPackageTests")
                    || processName.contains("swift-test") || processName.contains("swiftpm-testing")
            ),
            ("ci-environment", ciIndicators.contains { env[$0] != nil })
        ]
    }

    /// Allow tests to override admin operation skipping
    private static let _adminOverrideLock = NSLock()
    private nonisolated(unsafe) static var _allowAdminOpsInTests: Bool = false

    public static var allowAdminOperationsInTests: Bool {
        get {
            _adminOverrideLock.lock()
            defer { _adminOverrideLock.unlock() }
            return _allowAdminOpsInTests
        }
        set {
            _adminOverrideLock.lock()
            _allowAdminOpsInTests = newValue
            _adminOverrideLock.unlock()
        }
    }

    /// Check if we should skip operations requiring administrator privileges
    public static var shouldSkipAdminOperations: Bool {
        _adminOverrideLock.lock()
        let allowOverride = _allowAdminOpsInTests
        _adminOverrideLock.unlock()
        if allowOverride {
            return false
        }
        // If sudo mode is enabled, don't skip admin operations
        if useSudoForPrivilegedOps {
            return false
        }
        return isRunningTests
    }

    /// Check if we should use sudo instead of osascript for privileged operations.
    ///
    /// **Enabled when:**
    /// - `KEYPATH_USE_SUDO=1` environment variable is set, AND
    /// - Either running tests OR in a DEBUG build
    ///
    /// When enabled:
    /// - Privileged operations use `sudo -n` (non-interactive) instead of osascript admin prompts
    /// - Requires sudoers NOPASSWD configuration (see Scripts/dev-setup-sudoers.sh)
    /// - Release builds always use osascript for user prompts (unless running tests)
    ///
    /// ⚠️ WARNING: Remove sudoers config before public release!
    public static var useSudoForPrivilegedOps: Bool {
        // Explicit env var takes precedence
        if let envValue = ProcessInfo.processInfo.environment["KEYPATH_USE_SUDO"] {
            if envValue == "1" {
                // Env var explicitly set to 1 - check if we're in a valid context
                if isRunningTests {
                    return true
                }
                #if DEBUG
                    return true
                #else
                    return false
                #endif
            } else {
                // Explicitly set to 0 or other value - never use sudo
                return false
            }
        }

        // Not in tests and no env var - never use sudo
        return false
    }

    /// Check if we should use mock data instead of real system calls
    public static var shouldUseMockData: Bool {
        isRunningTests
    }

    /// True when tests should keep expected fixture/setup diagnostics out of
    /// default warning output. Set `KEYPATH_TEST_VERBOSE_LOGS=1` to show them.
    public static var shouldQuietExpectedTestDiagnostics: Bool {
        isRunningTests && ProcessInfo.processInfo.environment["KEYPATH_TEST_VERBOSE_LOGS"] != "1"
    }

    /// Force test mode (for manual testing)
    /// Thread-safe: Uses atomic access pattern to avoid MainActor isolation issues
    private static let _forceTestModeLock = NSLock()
    private nonisolated(unsafe) static var _forceTestMode: Bool = false

    @MainActor public static var forceTestMode: Bool {
        get {
            _forceTestModeLock.lock()
            defer { _forceTestModeLock.unlock() }
            return _forceTestMode
        }
        set {
            _forceTestModeLock.lock()
            _forceTestMode = newValue
            _forceTestModeLock.unlock()

            if newValue {
                AppLogger.shared.log("🧪 [TestEnvironment] Force test mode enabled")
            }
        }
    }

    /// Combined check for any test-related behavior
    /// Thread-safe: Can be called from any thread
    public static var isTestMode: Bool {
        _forceTestModeLock.lock()
        defer { _forceTestModeLock.unlock() }
        return _forceTestMode || isRunningTests
    }

    /// Log test environment status
    public static func logEnvironmentStatus() {
        AppLogger.shared.log("🧪 [TestEnvironment] Running in tests: \(isRunningTests)")
        AppLogger.shared.log("🧪 [TestEnvironment] Should skip admin ops: \(shouldSkipAdminOperations)")
        AppLogger.shared.log("🧪 [TestEnvironment] Process name: \(ProcessInfo.processInfo.processName)")

        if isRunningTests {
            let active = detectionSignals.filter(\.present).map(\.name)
            AppLogger.shared.log(
                "🧪 [TestEnvironment] Active test signals: \(active.joined(separator: ", "))"
            )
        }
    }
}

/// Mock data providers for test environment
public enum MockSystemData {
    /// Mock launchctl service status
    public static func mockServiceStatus(loaded: Bool = true, running: Bool = false) -> String {
        if loaded, running {
            """
            {
                "LimitLoadToSessionType" = "System";
                "Label" = "com.keypath.kanata";
                "OnDemand" = true;
                "LastExitStatus" = 0;
                "PID" = 12345;
                "Program" = "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata";
                "ProgramArguments" = (
                    "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata",
                    "--cfg",
                    "/Users/test/.config/keypath/keypath.kbd",
                    "--port",
                    "37000"
                );
            }
            """
        } else if loaded {
            """
            {
                "LimitLoadToSessionType" = "System";
                "Label" = "com.keypath.kanata";
                "OnDemand" = true;
                "LastExitStatus" = 0;
                "Program" = "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata";
                "ProgramArguments" = (
                    "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata",
                    "--cfg",
                    "/Users/test/.config/keypath/keypath.kbd",
                    "--port",
                    "37000"
                );
            }
            """
        } else {
            "launchctl: couldn't find service"
        }
    }

    /// Mock file system operations
    public static let mockFileExists = true
    public static let mockDirectoryExists = true

    /// Mock process list (no kanata processes)
    public static let mockProcessList = ""

    /// Mock permission status
    public static let mockHasPermissions = true
}
