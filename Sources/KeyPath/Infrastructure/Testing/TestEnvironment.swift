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
    public static var forceTestMode: Bool = false {
        didSet {
            if forceTestMode {
                AppLogger.shared.log("🧪 [TestEnvironment] Force test mode enabled")
            }
        }
    }

    /// Combined check for any test-related behavior
    public static var isTestMode: Bool {
        forceTestMode || isRunningTests
    }

    /// Log test environment status
    public static func logEnvironmentStatus() {
        AppLogger.shared.log("🧪 [TestEnvironment] Running in tests: \(isRunningTests)")
        AppLogger.shared.log("🧪 [TestEnvironment] Should skip admin ops: \(shouldSkipAdminOperations)")
        AppLogger.shared.log("🧪 [TestEnvironment] Process name: \(ProcessInfo.processInfo.processName)")

        if isRunningTests {
            let testIndicators = [
                "XCTest class exists: \(NSClassFromString("XCTestCase") != nil)",
                "SWIFT_TEST env: \(ProcessInfo.processInfo.environment["SWIFT_TEST"] != nil)",
                "CI env detected: \(["CI", "GITHUB_ACTIONS", "TRAVIS", "CIRCLE_CI", "JENKINS_URL"].contains { ProcessInfo.processInfo.environment[$0] != nil })"
            ]
            AppLogger.shared.log("🧪 [TestEnvironment] Test indicators: \(testIndicators.joined(separator: ", "))")
        }
    }
}

/// Mock data providers for test environment
public enum MockSystemData {
    /// Mock launchctl service status
    public static func mockServiceStatus(loaded: Bool = true, running: Bool = false) -> String {
        if loaded && running {
            return """
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
            return """
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
            return "launchctl: couldn't find service"
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
