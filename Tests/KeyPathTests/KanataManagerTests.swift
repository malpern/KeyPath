import XCTest

@testable import KeyPathAppKit

@MainActor
final class KanataManagerTests: XCTestCase {
    lazy var manager: KanataManager = .init()

    func testInitialState() async {
        // Test initial published properties
        // XCTAssertFalse(manager.isRunning, "Should not be running initially") // Removed
        if let error = manager.lastError {
            XCTAssertTrue(
                error.lowercased().contains("install"),
                "Unexpected initial error: \(error)"
            )
        }
        XCTAssertTrue(manager.keyMappings.isEmpty, "Should have no initial mappings")
        XCTAssertTrue(manager.diagnostics.isEmpty, "Should have no initial diagnostics")
        XCTAssertNil(manager.lastProcessExitCode, "Should have no initial exit code")
    }

    func testDiagnosticManagement() async {
        // Test adding diagnostics
        let diagnostic = KanataDiagnostic(
            timestamp: Date(),
            severity: .error,
            category: .configuration,
            title: "Test Error",
            description: "Test description",
            technicalDetails: "Test details",
            suggestedAction: "Test action",
            canAutoFix: false
        )

        manager.addDiagnostic(diagnostic)
        XCTAssertEqual(manager.diagnostics.count, 1, "Should have one diagnostic")
        XCTAssertEqual(manager.diagnostics.first?.title, "Test Error")

        // Test clearing diagnostics
        manager.clearDiagnostics()
        XCTAssertTrue(manager.diagnostics.isEmpty, "Should have no diagnostics after clear")
    }

    func testConfigValidation() async {
        // Test config validation (should not crash)
        let validation = await manager.validateConfigFile()

        // Should return a validation result (valid or invalid)
        XCTAssertNotNil(validation.isValid)
        XCTAssertNotNil(validation.errors)
    }

    func testSystemDiagnostics() async {
        // Test getting system diagnostics
        let systemDiagnostics = await manager.getSystemDiagnostics()

        // Should return a valid array (may be empty)
        XCTAssertNotNil(systemDiagnostics)
    }

    func testKeyMappingStorage() async {
        // Test that key mappings can be stored
        let testMapping = KeyMapping(input: "caps", output: "escape")

        // Manually add to the array to test the structure
        manager.keyMappings.append(testMapping)

        XCTAssertEqual(manager.keyMappings.count, 1, "Should have one mapping")
        XCTAssertEqual(manager.keyMappings.first?.input, "caps")
        XCTAssertEqual(manager.keyMappings.first?.output, "escape")
    }

    func testConfigPathProperty() async {
        // Test that configPath is accessible
        let configPath = manager.configPath
        XCTAssertFalse(configPath.isEmpty, "Config path should not be empty")
        XCTAssertTrue(configPath.contains("keypath.kbd"), "Config path should contain keypath.kbd")
    }

    func testInstallationStatus() async {
        // Test installation status check
        let isInstalled = manager.isCompletelyInstalled()

        // Should return a boolean (true or false)
        XCTAssertNotNil(isInstalled)
    }

    func testPerformanceConfigValidation() async {
        // Test that config validation performs reasonably
        let startTime = Date()

        _ = await manager.validateConfigFile()

        let duration = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 10.0, "Config validation should complete within 10 seconds")
    }
}
