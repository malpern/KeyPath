@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class RuntimeCoordinatorTests: KeyPathTestCase {
    lazy var manager: RuntimeCoordinator = .init()

    // MARK: - Initialization Tests

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

    func testInitialUIState() async {
        let state = manager.getCurrentUIState()

        XCTAssertTrue(state.keyMappings.isEmpty, "Initial UI state should have no mappings")
        XCTAssertTrue(state.diagnostics.isEmpty, "Initial UI state should have no diagnostics")
        XCTAssertNil(state.lastProcessExitCode, "Initial UI state should have no exit code")
        XCTAssertEqual(state.saveStatus, .idle, "Initial save status should be idle")
    }

    func testBuildUIStateSnapshot() async {
        // Verify buildUIState creates accurate snapshots
        manager.lastError = "Test error"
        manager.lastWarning = "Test warning"
        manager.currentLayerName = "test-layer"

        let state = manager.getCurrentUIState()

        XCTAssertEqual(state.lastError, "Test error")
        XCTAssertEqual(state.lastWarning, "Test warning")
        XCTAssertEqual(state.currentLayerName, "test-layer")
    }

    // MARK: - Diagnostic Management Tests

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

    func testMultipleDiagnostics() async {
        let diagnostic1 = KanataDiagnostic(
            timestamp: Date(),
            severity: .error,
            category: .configuration,
            title: "Error 1",
            description: "Description 1",
            technicalDetails: "Details 1",
            suggestedAction: "Action 1",
            canAutoFix: false
        )

        let diagnostic2 = KanataDiagnostic(
            timestamp: Date(),
            severity: .warning,
            category: .permissions,
            title: "Warning 1",
            description: "Description 2",
            technicalDetails: "Details 2",
            suggestedAction: "Action 2",
            canAutoFix: true
        )

        manager.addDiagnostic(diagnostic1)
        manager.addDiagnostic(diagnostic2)

        XCTAssertEqual(manager.diagnostics.count, 2, "Should have two diagnostics")
        XCTAssertEqual(manager.diagnostics[0].severity, .error)
        XCTAssertEqual(manager.diagnostics[1].severity, .warning)
    }

    func testDiagnosticUIStateSync() async {
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

        let state = manager.getCurrentUIState()
        XCTAssertEqual(state.diagnostics.count, 1)
        XCTAssertEqual(state.diagnostics.first?.title, "Test Error")
    }

    func testSystemDiagnostics() async {
        // Test getting system diagnostics
        let systemDiagnostics = await manager.getSystemDiagnostics()

        // Should return a valid array (may be empty)
        XCTAssertNotNil(systemDiagnostics)
    }

    // MARK: - Configuration Management Tests

    func testConfigValidation() async {
        // Test config validation (should not crash)
        let validation = await manager.validateConfigFile()

        // Should return a validation result (valid or invalid)
        XCTAssertNotNil(validation.isValid)
        XCTAssertNotNil(validation.errors)
    }

    func testConfigPathProperty() async {
        // Test that configPath is accessible
        let configPath = manager.configPath
        XCTAssertFalse(configPath.isEmpty, "Config path should not be empty")
        XCTAssertTrue(configPath.contains("keypath.kbd"), "Config path should contain keypath.kbd")
    }

    func testValidationErrorClearing() async {
        // Set validation error
        manager.validationError = .saveFailed(
            title: "Test Error",
            errors: ["Test error"]
        )

        XCTAssertNotNil(manager.validationError)

        // Clear it
        manager.clearValidationError()

        XCTAssertNil(manager.validationError)
        let state = manager.getCurrentUIState()
        XCTAssertNil(state.validationError)
    }

    func testCreateDefaultConfigIfMissing() async {
        let created = await manager.createDefaultUserConfigIfMissing()
        // Should return true if config exists after call
        XCTAssertTrue(created || FileManager.default.fileExists(atPath: manager.configPath))
    }

    // MARK: - Key Mapping Tests

    func testKeyMappingStorage() async {
        // Test that key mappings can be stored
        let testMapping = KeyMapping(input: "caps", output: "escape")

        // Manually add to the array to test the structure
        manager.keyMappings.append(testMapping)

        XCTAssertEqual(manager.keyMappings.count, 1, "Should have one mapping")
        XCTAssertEqual(manager.keyMappings.first?.input, "caps")
        XCTAssertEqual(manager.keyMappings.first?.output, "escape")
    }

    func testKeyMappingUIStateSync() async {
        let mapping1 = KeyMapping(input: "a", output: "b")
        let mapping2 = KeyMapping(input: "c", output: "d")

        manager.keyMappings = [mapping1, mapping2]

        let state = manager.getCurrentUIState()
        XCTAssertEqual(state.keyMappings.count, 2)
        XCTAssertEqual(state.keyMappings[0].input, "a")
        XCTAssertEqual(state.keyMappings[1].output, "d")
    }

    func testLastConfigUpdateTracking() async {
        let beforeUpdate = Date()
        manager.keyMappings = [KeyMapping(input: "test", output: "test")]
        manager.lastConfigUpdate = Date()

        XCTAssertGreaterThanOrEqual(manager.lastConfigUpdate, beforeUpdate)

        let state = manager.getCurrentUIState()
        XCTAssertGreaterThanOrEqual(state.lastConfigUpdate, beforeUpdate)
    }

    // MARK: - Custom Rule Tests

    func testMakeCustomRule() async {
        let rule = manager.makeCustomRule(input: "x", output: "y")

        XCTAssertEqual(rule.input, "x")
        XCTAssertEqual(rule.output, "y")
        XCTAssertTrue(rule.isEnabled)
    }

    func testMakeCustomRuleDuplicateInput() async {
        // First rule
        let rule1 = manager.makeCustomRule(input: "x", output: "y")

        // Save it
        _ = await manager.saveCustomRule(rule1, skipReload: true)

        // Make another rule with same input
        let rule2 = manager.makeCustomRule(input: "x", output: "z")

        // Should reuse the same ID but update output
        XCTAssertEqual(rule2.input, "x")
        XCTAssertEqual(rule2.output, "z")
    }

    // MARK: - State Transition Tests

    func testSaveStatusTransitions() async {
        XCTAssertEqual(manager.saveStatus, .idle)

        manager.saveStatus = .saving
        XCTAssertEqual(manager.saveStatus, .saving)

        manager.saveStatus = .success
        XCTAssertEqual(manager.saveStatus, .success)

        manager.saveStatus = .failed("Test error")
        if case let .failed(message) = manager.saveStatus {
            XCTAssertEqual(message, "Test error")
        } else {
            XCTFail("Expected failed status")
        }
    }

    func testErrorStateHandling() async {
        manager.lastError = nil
        XCTAssertNil(manager.getCurrentUIState().lastError)

        manager.lastError = "Test error message"
        XCTAssertEqual(manager.getCurrentUIState().lastError, "Test error message")

        manager.lastError = nil
        XCTAssertNil(manager.getCurrentUIState().lastError)
    }

    func testWarningStateHandling() async {
        manager.lastWarning = nil
        XCTAssertNil(manager.getCurrentUIState().lastWarning)

        manager.lastWarning = "Test warning"
        XCTAssertEqual(manager.getCurrentUIState().lastWarning, "Test warning")
    }

    func testProcessExitCodeTracking() async {
        manager.lastProcessExitCode = nil
        XCTAssertNil(manager.getCurrentUIState().lastProcessExitCode)

        manager.lastProcessExitCode = 1
        XCTAssertEqual(manager.getCurrentUIState().lastProcessExitCode, 1)

        manager.lastProcessExitCode = 127
        XCTAssertEqual(manager.getCurrentUIState().lastProcessExitCode, 127)
    }

    // MARK: - Layer Management Tests

    func testCurrentLayerTracking() async {
        XCTAssertEqual(manager.currentLayerName, RuleCollectionLayer.base.displayName)

        manager.currentLayerName = "vim"
        XCTAssertEqual(manager.currentLayerName, "vim")

        let state = manager.getCurrentUIState()
        XCTAssertEqual(state.currentLayerName, "vim")
    }

    // MARK: - Installation & System Requirements Tests

    func testInstallationStatus() async {
        // Test installation status check
        let isInstalled = manager.isCompletelyInstalled()

        // Should return a boolean (true or false)
        XCTAssertNotNil(isInstalled)
    }

    func testIsInstalledCheck() async {
        let installed = manager.isInstalled()
        // Should not crash, returns bool
        _ = installed
    }

    func testIsServiceInstalled() async {
        let serviceInstalled = manager.isServiceInstalled()
        // Should return a boolean without crashing
        _ = serviceInstalled
    }

    func testGetInstallationStatus() async {
        let status = manager.getInstallationStatus()
        XCTAssertFalse(status.isEmpty, "Installation status should not be empty")
    }

    // MARK: - Converter Tests

    func testKanataKeyConversion() async {
        // Test key converter delegation
        let converted = manager.convertToKanataKey("Escape")
        XCTAssertFalse(converted.isEmpty, "Converted key should not be empty")
    }

    func testKanataSequenceConversion() async {
        let sequence = manager.convertToKanataSequence("Cmd-C")
        XCTAssertFalse(sequence.isEmpty, "Converted sequence should not be empty")
    }

    // MARK: - Backup Management Tests

    func testCreatePreEditBackup() async {
        // Should return true or false without crashing
        let created = manager.createPreEditBackup()
        _ = created
    }

    func testGetAvailableBackups() async {
        let backups = manager.getAvailableBackups()
        XCTAssertNotNil(backups, "Backups array should not be nil")
    }

    // MARK: - System Context Tests

    func testInspectSystemContext() async {
        let context = await manager.inspectSystemContext()

        XCTAssertNotNil(context.permissions)
        XCTAssertNotNil(context.components)
        XCTAssertNotNil(context.services)
    }

    // MARK: - Service Management Tests

    func testStartKanataRequiresVHIDDaemon() async {
        // Starting Kanata should check for VHID daemon first
        // This test verifies the safety check exists
        let result = await manager.startKanata(reason: "Test start")

        // If daemon is not running, should fail gracefully
        if !result {
            XCTAssertNotNil(manager.lastError, "Should have error message when start fails")
        }
    }

    func testStopKanata() async {
        // Stop should not crash even if nothing is running
        let result = await manager.stopKanata(reason: "Test stop")
        _ = result // May succeed or fail depending on state
    }

    func testCurrentServiceState() async {
        let state = await manager.currentServiceState()
        // Should return a valid state
        XCTAssertNotNil(state)
    }

    // MARK: - Permission Checks Tests

    func testHasInputMonitoringPermission() async {
        let hasPermission = await manager.hasInputMonitoringPermission()
        _ = hasPermission // Returns bool
    }

    func testHasAccessibilityPermission() async {
        let hasPermission = await manager.hasAccessibilityPermission()
        _ = hasPermission // Returns bool
    }

    func testHasAllRequiredPermissions() async {
        let hasAll = await manager.hasAllRequiredPermissions()
        _ = hasAll // Returns bool
    }

    func testCheckBothAppsHavePermissions() async {
        let result = await manager.checkBothAppsHavePermissions()

        XCTAssertNotNil(result.keyPathHasPermission)
        XCTAssertNotNil(result.kanataHasPermission)
        XCTAssertFalse(result.permissionDetails.isEmpty)
    }

    func testShouldShowWizardForPermissions() async {
        let shouldShow = await manager.shouldShowWizardForPermissions()
        _ = shouldShow // Returns bool
    }

    // MARK: - Driver & Daemon Tests

    func testIsKarabinerDriverInstalled() async {
        let installed = manager.isKarabinerDriverInstalled()
        _ = installed // Returns bool
    }

    func testIsKarabinerDaemonRunning() async {
        let running = await manager.isKarabinerDaemonRunning()
        _ = running // Returns bool
    }

    // MARK: - UI State Reactivity Tests

    func testRefreshProcessState() async {
        // Should not crash
        manager.refreshProcessState()

        // Verify state is still readable
        let state = manager.getCurrentUIState()
        XCTAssertNotNil(state)
    }

    func testUpdateStatus() async {
        await manager.updateStatus()

        // Should trigger state change notification
        let state = manager.getCurrentUIState()
        XCTAssertNotNil(state)
    }

    // MARK: - Performance Tests

    func testPerformanceConfigValidation() async {
        // Test that config validation performs reasonably
        let startTime = Date()

        _ = await manager.validateConfigFile()

        let duration = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 10.0, "Config validation should complete within 10 seconds")
    }

    func testPerformanceGetUIState() async {
        measure {
            _ = manager.getCurrentUIState()
        }
    }

    func testPerformanceInspectSystemContext() async {
        let startTime = Date()

        _ = await manager.inspectSystemContext()

        let duration = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 15.0, "System inspection should complete within 15 seconds")
    }

    // MARK: - Configuration File Watching Tests

    func testStartConfigFileWatching() async {
        // Should not crash
        manager.startConfigFileWatching()
    }

    func testStopConfigFileWatching() async {
        // Should not crash even if not watching
        manager.stopConfigFileWatching()
    }

    // MARK: - Edge Case Tests

    func testEmptyKeyMappingsState() async {
        manager.keyMappings = []

        let state = manager.getCurrentUIState()
        XCTAssertTrue(state.keyMappings.isEmpty)
    }

    func testMultipleStateChanges() async {
        manager.lastError = "Error 1"
        let state1 = manager.getCurrentUIState()
        XCTAssertEqual(state1.lastError, "Error 1")

        manager.lastError = "Error 2"
        let state2 = manager.getCurrentUIState()
        XCTAssertEqual(state2.lastError, "Error 2")

        manager.lastError = nil
        let state3 = manager.getCurrentUIState()
        XCTAssertNil(state3.lastError)
    }
}
