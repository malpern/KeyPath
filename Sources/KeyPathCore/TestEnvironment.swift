import Foundation

/// Utility for detecting test environment and controlling system operations during testing
public enum TestEnvironment {
    /// Check if code is running in test environment
    public static var isRunningTests: Bool {
        // Check for XCTest environment
        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        // Check for Swift test runner
        if ProcessInfo.processInfo.environment["SWIFT_TEST"] != nil {
            return true
        }

        // Check for test process names
        let processName = ProcessInfo.processInfo.processName
        if processName.contains("xctest") || processName.contains("KeyPathPackageTests") {
            return true
        }

        // Check for CI environment variables
        let ciIndicators = ["CI", "GITHUB_ACTIONS", "TRAVIS", "CIRCLE_CI", "JENKINS_URL"]
        for indicator in ciIndicators {
            if ProcessInfo.processInfo.environment[indicator] != nil {
                return true
            }
        }

        return false
    }

    /// Check if we should skip operations requiring administrator privileges
    public static var shouldSkipAdminOperations: Bool {
        isRunningTests
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
            AppLogger.shared.log("🧪 [TestEnvironment] Test indicators: \(testIndicators.joined(separator: ", "))")
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

