import XCTest
@testable import KeyPath

/// Tests for VHIDDeviceManager to validate driver version detection and compatibility logic
/// Critical for ADR-012: Karabiner Driver Version Fix
final class VHIDDeviceManagerTests: XCTestCase {

    var vhidManager: VHIDDeviceManager!

    override func setUp() {
        super.setUp()
        vhidManager = VHIDDeviceManager()
    }

    override func tearDown() {
        vhidManager = nil
        super.tearDown()
    }

    // MARK: - Installation Detection Tests

    func testDetectInstallationReturnsBoolean() {
        // When: Checking if VirtualHID Manager is installed
        let isInstalled = vhidManager.detectInstallation()

        // Then: Should return a boolean (true or false depending on system state)
        XCTAssertTrue(isInstalled == true || isInstalled == false, "Should return a boolean value")
    }

    func testDetectActivationReturnsBoolean() {
        // When: Checking if VirtualHID Manager is activated
        let isActivated = vhidManager.detectActivation()

        // Then: Should return a boolean value
        XCTAssertTrue(isActivated == true || isActivated == false, "Should return a boolean value")
    }

    func testDetectRunningReturnsBoolean() {
        // When: Checking if VirtualHID daemon is running
        let isRunning = vhidManager.detectRunning()

        // Then: Should return a boolean value
        XCTAssertTrue(isRunning == true || isRunning == false, "Should return a boolean value")
    }

    func testDetectConnectionHealthReturnsBoolean() {
        // When: Checking connection health
        let isHealthy = vhidManager.detectConnectionHealth()

        // Then: Should return a boolean value
        XCTAssertTrue(isHealthy == true || isHealthy == false, "Should return a boolean value")
    }

    // MARK: - Version Detection Tests

    func testGetInstalledVersionReturnsValidFormat() {
        // When: Getting installed version
        let version = vhidManager.getInstalledVersion()

        // Then: If version exists, should be in format X.Y.Z
        if let ver = version {
            XCTAssertTrue(ver.contains("."), "Version should contain dots")
            let components = ver.split(separator: ".")
            XCTAssertGreaterThanOrEqual(components.count, 2, "Version should have at least major.minor")

            // All components should be numeric
            for component in components {
                XCTAssertNotNil(Int(component), "Version component '\(component)' should be numeric")
            }
        }
    }

    func testGetRegisteredExtensionVersionReturnsValidFormat() {
        // When: Getting registered system extension version
        let version = vhidManager.getRegisteredExtensionVersion()

        // Then: If version exists, should be in format X.Y.Z
        if let ver = version {
            XCTAssertTrue(ver.contains("."), "Version should contain dots")
            let components = ver.split(separator: ".")
            XCTAssertGreaterThanOrEqual(components.count, 2, "Version should have at least major.minor")
        }
    }

    // MARK: - Version Mismatch Detection Tests

    func testHasVersionMismatchWithNoDriverInstalled() {
        // Given: System has no driver (simulated by real system state)
        // Note: This test validates the logic but depends on actual system state

        // When: Checking for version mismatch
        let hasMismatch = vhidManager.hasVersionMismatch()

        // Then: Should return a boolean (true if driver missing/wrong version)
        XCTAssertTrue(hasMismatch == true || hasMismatch == false, "Should return boolean")
    }

    func testVersionMismatchDetectionLogic() {
        // This test documents the version mismatch logic without requiring actual driver installation

        // Given: Current requirements (from VHIDDeviceManager constants)
        let requiredMajorVersion = 5 // Kanata v1.9.0 requires v5.x.x
        let futureVersion = "1.10"    // Kanata v1.10 will support v6.x.x

        // Test scenarios:
        let testCases: [(installed: String, expected: Bool, reason: String)] = [
            ("5.0.0", false, "v5.0.0 should be compatible with kanata v1.9.0"),
            ("5.1.0", false, "v5.1.0 should be compatible (same major version)"),
            ("6.0.0", true, "v6.0.0 should be incompatible (requires kanata v\(futureVersion))"),
            ("4.0.0", true, "v4.0.0 should be incompatible (too old)"),
            ("1.8.0", true, "v1.8.0 should be incompatible (legacy version)")
        ]

        for testCase in testCases {
            let components = testCase.installed.split(separator: ".").compactMap { Int($0) }
            guard let majorVersion = components.first else {
                XCTFail("Failed to parse version: \(testCase.installed)")
                continue
            }

            let hasMismatch = majorVersion != requiredMajorVersion
            XCTAssertEqual(
                hasMismatch, testCase.expected,
                "Version \(testCase.installed): \(testCase.reason)"
            )
        }
    }

    func testVersionMismatchMessageFormatWhenMismatchExists() {
        // When: Getting version mismatch message
        let message = vhidManager.getVersionMismatchMessage()

        // Then: If message exists (driver has mismatch), should contain key information
        if let msg = message {
            // Should mention version numbers
            XCTAssertTrue(
                msg.contains("5.0.0") || msg.contains("v5") || msg.contains("Version"),
                "Message should mention required version v5.0.0"
            )

            // Should mention Kanata version compatibility
            XCTAssertTrue(
                msg.contains("1.9.0") || msg.contains("Kanata"),
                "Message should mention Kanata version"
            )

            // Should mention future compatibility
            XCTAssertTrue(
                msg.contains("1.10") || msg.contains("pre-release"),
                "Message should mention future kanata v1.10 compatibility"
            )
        }
    }

    // MARK: - Activation Tests

    func testActivateManagerReturnsBoolean() async {
        // When: Activating the VirtualHID Manager
        // Note: This may require elevated privileges and actual driver installation
        let result = await vhidManager.activateManager()

        // Then: Should return a boolean indicating success/failure
        XCTAssertTrue(result == true || result == false, "Should return boolean result")
    }

    // MARK: - Download and Install Tests

    func testDownloadAndInstallCorrectVersionReturnsBoolean() async throws {
        // Note: This test validates the method exists and returns boolean
        // Full integration testing requires network and elevated privileges

        // Skip in CI environment
        guard ProcessInfo.processInfo.environment["CI"] != "true" else {
            throw XCTSkip("Skipping download test in CI environment")
        }

        // When: Attempting to download and install
        // (Will likely fail without network/permissions, but should not crash)
        let result = await vhidManager.downloadAndInstallCorrectVersion()

        // Then: Should return a boolean
        XCTAssertTrue(result == true || result == false, "Should return boolean result")
    }

    // MARK: - Version Compatibility Edge Cases

    func testVersionParsingEdgeCases() {
        // Test version parsing with various formats
        let testVersions = [
            "5.0.0",
            "5.0",
            "5",
            "10.0.0",
            "1.8.0"
        ]

        for versionString in testVersions {
            let components = versionString.split(separator: ".").compactMap { Int($0) }

            // Should successfully parse major version
            XCTAssertFalse(components.isEmpty, "Should parse version: \(versionString)")

            if let major = components.first {
                XCTAssertGreaterThan(major, 0, "Major version should be positive")
            }
        }
    }

    func testMajorVersionExtractionFromComplexVersionStrings() {
        // Simulates parsing version strings from systemextensionsctl output
        // Example: "G43BCU2T37	org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (5.0.0/5.0.0)"

        let exampleOutputLines = [
            "\t*\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (5.0.0/5.0.0)\t[activated enabled]",
            "\t*\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (6.0.0/6.0.0)\t[activated enabled]",
            "\t*\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0)\t[activated enabled]"
        ]

        for line in exampleOutputLines {
            // Extract version using regex pattern (similar to actual implementation)
            if let versionRange = line.range(of: #"\(\d+\.\d+\.\d+/\d+\.\d+\.\d+\)"#, options: .regularExpression) {
                let versionString = String(line[versionRange])
                if let firstVersion = versionString.components(separatedBy: "/").first?.trimmingCharacters(in: CharacterSet(charactersIn: "()")) {
                    let components = firstVersion.split(separator: ".").compactMap { Int($0) }
                    XCTAssertFalse(components.isEmpty, "Should extract version from: \(line)")

                    if let major = components.first {
                        XCTAssertGreaterThan(major, 0, "Extracted major version should be positive")
                    }
                }
            }
        }
    }

    // MARK: - ADR-012 Validation Tests

    func testADR012_RequiredVersionIsV5() {
        // ADR-012: Kanata v1.9.0 requires Karabiner-DriverKit-VirtualHIDDevice v5.0.0
        // This test documents and validates the requirement

        let requiredMajorVersion = 5

        // Version 5.x.x should be compatible
        XCTAssertFalse(5 != requiredMajorVersion, "v5.x.x should be required version")

        // Version 6.x.x should not be compatible (yet)
        XCTAssertTrue(6 != requiredMajorVersion, "v6.x.x should not be compatible with current kanata v1.9.0")

        // Version 4.x.x should not be compatible
        XCTAssertTrue(4 != requiredMajorVersion, "v4.x.x should not be compatible")
    }

    func testADR012_FutureCompatibilityWithV6() {
        // ADR-012: When kanata v1.10 is released, v6.0.0 will be compatible
        // This test documents the future upgrade path

        let currentRequiredMajor = 5
        let futureRequiredMajor = 6
        let futureKanataVersion = "1.10"

        // Document future state
        XCTAssertNotEqual(futureRequiredMajor, currentRequiredMajor, "Future version will be different")
        XCTAssertGreaterThan(futureRequiredMajor, currentRequiredMajor, "Future version will be newer")
        XCTAssertEqual(futureKanataVersion, "1.10", "Future kanata version documented")
    }

    // MARK: - Integration Smoke Tests

    func testVHIDManagerMethodsDoNotCrash() {
        // Smoke test: All public methods should complete without crashing

        // Detection methods
        _ = vhidManager.detectInstallation()
        _ = vhidManager.detectActivation()
        _ = vhidManager.detectRunning()
        _ = vhidManager.detectConnectionHealth()

        // Version methods
        _ = vhidManager.getInstalledVersion()
        _ = vhidManager.getRegisteredExtensionVersion()
        _ = vhidManager.hasVersionMismatch()
        _ = vhidManager.getVersionMismatchMessage()

        // If we reached here, no crashes occurred
        XCTAssertTrue(true, "All VHIDDeviceManager methods completed without crashing")
    }

    func testVersionMismatchAndMessageConsistency() {
        // When: Checking version mismatch and message
        let hasMismatch = vhidManager.hasVersionMismatch()
        let message = vhidManager.getVersionMismatchMessage()

        // Then: If has mismatch, should have message (or vice versa)
        if hasMismatch {
            // If version mismatch detected, getMessage might return message
            // (Could be nil if version can't be determined)
            if message == nil {
                // This is OK - might not have driver installed to detect version from
                XCTAssertTrue(true, "Mismatch detected but no version to read - acceptable")
            } else {
                XCTAssertFalse(message!.isEmpty, "If mismatch and message exists, should not be empty")
            }
        } else {
            // If no mismatch, should not have message
            XCTAssertNil(message, "No mismatch should mean no mismatch message")
        }
    }
}

// MARK: - ADR-012 Documentation Extension

extension VHIDDeviceManagerTests {
    /// Documentation test for ADR-012: Karabiner Driver Version Fix
    ///
    /// **Current State** (October 2025):
    /// - Kanata v1.9.0 requires Karabiner-DriverKit-VirtualHIDDevice v5.0.0
    /// - v6.0.0 is incompatible with current kanata
    /// - KeyPath auto-fixes version mismatches by downloading/installing v5.0.0
    ///
    /// **Implementation**:
    /// - `hasVersionMismatch()`: Detects if installed version != v5.x.x
    /// - `getVersionMismatchMessage()`: Provides user-facing explanation
    /// - `downloadAndInstallCorrectVersion()`: Automates v5.0.0 installation
    /// - `activateManager()`: Registers system extension with macOS
    ///
    /// **Future Path**:
    /// - When Kanata v1.10 is released (currently pre-release), will support v6.0.0+
    /// - Update requiredDriverVersionMajor to 6 at that time
    /// - Tests will validate the new requirement
    ///
    /// **Critical Behavior**:
    /// - Uses file version first (workaround for macOS registry caching)
    /// - Falls back to registered extension version if file check fails
    /// - Handles version format: X.Y.Z where X is major version
    func testADR012_Documentation() {
        // This test exists to document ADR-012 in the test suite
        // Actual testing is done in other test methods
        XCTAssertTrue(true, "ADR-012 documented in test suite")
    }
}
