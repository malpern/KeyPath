import Foundation

/// Utility for detecting test environment and controlling system operations during testing
public enum TestEnvironment {
    /// Check if code is running in test environment
    public static var isRunningTests: Bool {
        // Check for XCTest environment (XCTest-based tests)
        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        // Check for Swift Testing framework (modern @Test macro-based tests)
        // The Testing module provides these types when tests are running
        if NSClassFromString("Testing.Test") != nil
            || NSClassFromString("XCTestScaffold.XCTestScaffold") != nil
        {
            return true
        }

        // Check for Swift test runner env var
        if ProcessInfo.processInfo.environment["SWIFT_TEST"] != nil {
            return true
        }

        // Check for KEYPATH_USE_SUDO - if set, we're definitely in test mode
        // This is the explicit test environment flag
        if ProcessInfo.processInfo.environment["KEYPATH_USE_SUDO"] == "1" {
            return true
        }

        // Check for test process names
        let processName = ProcessInfo.processInfo.processName
        if processName.contains("xctest") || processName.contains("KeyPathPackageTests")
            || processName.contains("swift-test")
        {
            return true
        }

        // Check if running in swift-testing worker process
        // Swift Testing uses worker processes with specific environment
        if ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
            || ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"]?.contains(".build") == true
        {
            return true
        }

        // Check for CI environment variables - but only specific CI systems, NOT just "CI"
        // The generic "CI" env var is too common (can be set by various tools, editors, etc.)
        // and causes false positives when inherited from user's shell environment
        let ciIndicators = ["GITHUB_ACTIONS", "TRAVIS", "CIRCLE_CI", "JENKINS_URL"]
        for indicator in ciIndicators where ProcessInfo.processInfo.environment[indicator] != nil {
            return true
        }

        return false
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
            let xctestExists = NSClassFromString("XCTestCase") != nil
            let swiftTestEnv = ProcessInfo.processInfo.environment["SWIFT_TEST"] != nil
            let ciDetected = ["CI", "GITHUB_ACTIONS", "TRAVIS", "CIRCLE_CI", "JENKINS_URL"].contains {
                ProcessInfo.processInfo.environment[$0] != nil
            }
            let testIndicators = [
                "XCTest class exists: \(xctestExists)",
                "SWIFT_TEST env: \(swiftTestEnv)",
                "CI env detected: \(ciDetected)"
            ]
            AppLogger.shared.log(
                "🧪 [TestEnvironment] Test indicators: \(testIndicators.joined(separator: ", "))"
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
                "Program" = "/Library/KeyPath/bin/kanata";
                "ProgramArguments" = (
                    "/Library/KeyPath/bin/kanata",
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
                "Program" = "/Library/KeyPath/bin/kanata";
                "ProgramArguments" = (
                    "/Library/KeyPath/bin/kanata",
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
