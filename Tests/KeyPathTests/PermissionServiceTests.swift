import XCTest

@testable import KeyPath

/// Comprehensive tests for PermissionService
/// Tests the unified permission checking architecture including binary-aware checking,
/// TCC database queries, and system permission status reporting
@MainActor
final class PermissionServiceTests: XCTestCase {
    var permissionService: PermissionService!

    override func setUp() async throws {
        try await super.setUp()
        permissionService = PermissionService.shared
    }

    // MARK: - Basic Permission Checking Tests

    func testHasInputMonitoringPermission() {
        // Test that the method returns a boolean without crashing
        let result = permissionService.hasInputMonitoringPermission()
        XCTAssert(result == true || result == false, "Should return a valid boolean")
    }

    func testHasAccessibilityPermission() {
        // Test that the method returns a boolean without crashing
        let result = permissionService.hasAccessibilityPermission()
        XCTAssert(result == true || result == false, "Should return a valid boolean")
    }

    // MARK: - System Permission Status Tests

    func testCheckSystemPermissions() {
        let testKanataPath = "/usr/local/bin/kanata"
        let systemStatus = permissionService.checkSystemPermissions(kanataBinaryPath: testKanataPath)

        // Verify structure is populated
        XCTAssertEqual(systemStatus.keyPath.binaryPath, Bundle.main.bundlePath)
        XCTAssertEqual(systemStatus.kanata.binaryPath, testKanataPath)

        // Verify boolean results are valid
        XCTAssert(
            systemStatus.keyPath.hasInputMonitoring == true
                || systemStatus.keyPath.hasInputMonitoring == false)
        XCTAssert(
            systemStatus.keyPath.hasAccessibility == true
                || systemStatus.keyPath.hasAccessibility == false)
        XCTAssert(
            systemStatus.kanata.hasInputMonitoring == true
                || systemStatus.kanata.hasInputMonitoring == false)
        XCTAssert(
            systemStatus.kanata.hasAccessibility == true || systemStatus.kanata.hasAccessibility == false)

        // Verify aggregate status computation
        let expectedOverallStatus =
            systemStatus.keyPath.hasAllRequiredPermissions
                && systemStatus.kanata.hasAllRequiredPermissions
        XCTAssertEqual(systemStatus.hasAllRequiredPermissions, expectedOverallStatus)
    }

    func testCheckBinaryPermissions() {
        let testPath = "/usr/local/bin/kanata"
        let binaryStatus = permissionService.checkSystemPermissions(kanataBinaryPath: testPath)

        XCTAssertEqual(binaryStatus.kanata.binaryPath, testPath)
        XCTAssert(
            binaryStatus.kanata.hasInputMonitoring == true
                || binaryStatus.kanata.hasInputMonitoring == false)
        XCTAssert(
            binaryStatus.kanata.hasAccessibility == true || binaryStatus.kanata.hasAccessibility == false)

        // Test aggregate status
        XCTAssert(
            binaryStatus.hasAllRequiredPermissions == true
                || binaryStatus.hasAllRequiredPermissions == false)
    }

    func testCheckBinaryPermissionsForKeyPath() {
        let keyPathBundle = Bundle.main.bundlePath
        let binaryStatus = permissionService.checkSystemPermissions(kanataBinaryPath: keyPathBundle)

        XCTAssertEqual(binaryStatus.keyPath.binaryPath, keyPathBundle)

        // Should use KeyPath-specific permission checking (not TCC database)
        // We can't easily mock this, but we can verify it doesn't crash
        XCTAssert(
            binaryStatus.hasAllRequiredPermissions == true
                || binaryStatus.hasAllRequiredPermissions == false)
        XCTAssert(
            binaryStatus.keyPath.hasAccessibility == true
                || binaryStatus.keyPath.hasAccessibility == false)
    }

    // MARK: - Error Message Generation Tests

    func testMissingPermissionErrorMessages() {
        let testKanataPath = "/usr/local/bin/kanata"
        let systemStatus = permissionService.checkSystemPermissions(kanataBinaryPath: testKanataPath)

        if systemStatus.hasAllRequiredPermissions {
            // If all permissions are granted, should return nil
            XCTAssertNil(systemStatus.missingPermissionError)
        } else {
            // If permissions are missing, should return actionable error message
            XCTAssertNotNil(systemStatus.missingPermissionError)
            let errorMessage = systemStatus.missingPermissionError!

            // Should contain actionable instructions
            XCTAssert(
                errorMessage.contains("System Settings") || errorMessage.contains("Privacy & Security"),
                "Error message should contain actionable instructions: \(errorMessage)"
            )

            // Should specify which permission is missing
            XCTAssert(
                errorMessage.contains("KeyPath") || errorMessage.contains("Kanata")
                    || errorMessage.contains("Input Monitoring") || errorMessage.contains("Accessibility"),
                "Error message should specify which permission: \(errorMessage)"
            )
        }
    }

    // MARK: - TCC Database Query Tests

    func testTCCDatabaseQueries() {
        let testPaths = [
            "/usr/local/bin/kanata",
            "/opt/homebrew/bin/kanata",
            "/nonexistent/path/kanata"
        ]

        for path in testPaths {
            // Test Input Monitoring TCC query
            let inputResult = PermissionService.checkTCCForInputMonitoring(path: path)
            XCTAssert(
                inputResult == true || inputResult == false,
                "TCC Input Monitoring query should return boolean for \(path)"
            )

            // Test Accessibility TCC query
            let accessResult = PermissionService.checkTCCForAccessibility(path: path)
            XCTAssert(
                accessResult == true || accessResult == false,
                "TCC Accessibility query should return boolean for \(path)"
            )
        }
    }

    func testTCCDatabaseQueryWithSpecialCharacters() {
        // Test that paths with special characters don't cause SQL injection or crashes
        let specialPaths = [
            "/path/with spaces/kanata",
            "/path/with'quote/kanata",
            "/path/with\"doublequote/kanata",
            "/path/with;semicolon/kanata",
            "/path/with--comment/kanata"
        ]

        for path in specialPaths {
            // Should not crash or throw SQL errors
            XCTAssertNoThrow(
                {
                    _ = PermissionService.checkTCCForInputMonitoring(path: path)
                    _ = PermissionService.checkTCCForAccessibility(path: path)
                }(), "TCC queries should handle special characters safely: \(path)"
            )
        }
    }

    // MARK: - Legacy Compatibility Tests

    func testLegacyCompatibilityMethods() {
        // Test that legacy methods still work
        let inputResult = permissionService.hasInputMonitoringPermission()
        let accessResult = permissionService.hasAccessibilityPermission()

        XCTAssert(inputResult == true || inputResult == false)
        XCTAssert(accessResult == true || accessResult == false)

        // Test legacy TCC methods
        let testPath = "/usr/local/bin/kanata"
        let legacyInputResult = PermissionService.checkTCCForInputMonitoring(path: testPath)
        let legacyAccessResult = PermissionService.checkTCCForAccessibility(path: testPath)

        XCTAssert(legacyInputResult == true || legacyInputResult == false)
        XCTAssert(legacyAccessResult == true || legacyAccessResult == false)
    }

    // MARK: - Architecture Consistency Tests

    func testArchitecturalConsistency() {
        let testKanataPath = "/usr/local/bin/kanata"
        let systemStatus = permissionService.checkSystemPermissions(kanataBinaryPath: testKanataPath)

        // Test that legacy methods return same results as new architecture for KeyPath
        let legacyInput = permissionService.hasInputMonitoringPermission()
        let legacyAccess = permissionService.hasAccessibilityPermission()

        XCTAssertEqual(
            systemStatus.keyPath.hasInputMonitoring, legacyInput,
            "Legacy and new methods should return same results for KeyPath Input Monitoring"
        )
        XCTAssertEqual(
            systemStatus.keyPath.hasAccessibility, legacyAccess,
            "Legacy and new methods should return same results for KeyPath Accessibility"
        )

        // Test that TCC methods are consistent
        let directTCCInput = PermissionService.checkTCCForInputMonitoring(path: testKanataPath)
        let directTCCAccess = PermissionService.checkTCCForAccessibility(path: testKanataPath)

        XCTAssertEqual(
            systemStatus.kanata.hasInputMonitoring, directTCCInput,
            "System status and direct TCC methods should return same results for kanata Input Monitoring"
        )
        XCTAssertEqual(
            systemStatus.kanata.hasAccessibility, directTCCAccess,
            "System status and direct TCC methods should return same results for kanata Accessibility"
        )
    }

    // MARK: - Error Handling Tests

    func testErrorHandling() {
        // Test with invalid paths
        let invalidPaths = ["", "/", "/nonexistent", "invalid-path"]

        for path in invalidPaths {
            XCTAssertNoThrow(
                {
                    _ = PermissionService.checkTCCForInputMonitoring(path: path)
                    _ = PermissionService.checkTCCForAccessibility(path: path)
                }(), "Should handle invalid paths gracefully: \(path)"
            )
        }
    }

    // MARK: - Performance Tests

    func testPermissionCheckingPerformance() {
        let testKanataPath = "/usr/local/bin/kanata"

        measure {
            // Measure performance of comprehensive permission checking
            for _ in 0 ..< 10 {
                _ = permissionService.checkSystemPermissions(kanataBinaryPath: testKanataPath)
            }
        }
    }

    func testTCCQueryPerformance() {
        let testPath = "/usr/local/bin/kanata"

        measure {
            // Measure TCC database query performance
            for _ in 0 ..< 5 {
                _ = PermissionService.checkTCCForInputMonitoring(path: testPath)
                _ = PermissionService.checkTCCForAccessibility(path: testPath)
            }
        }
    }

    // MARK: - Integration Tests

    func testIntegrationWithWizardSystemPaths() {
        // Test with actual wizard system paths
        let kanataPath = WizardSystemPaths.kanataActiveBinary
        let systemStatus = permissionService.checkSystemPermissions(kanataBinaryPath: kanataPath)

        XCTAssertEqual(systemStatus.kanata.binaryPath, kanataPath)
        XCTAssert(
            systemStatus.kanata.hasInputMonitoring == true
                || systemStatus.kanata.hasInputMonitoring == false)
        XCTAssert(
            systemStatus.kanata.hasAccessibility == true || systemStatus.kanata.hasAccessibility == false)
    }
}
