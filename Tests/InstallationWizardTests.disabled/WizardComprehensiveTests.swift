@testable import KeyPath
import XCTest

/// Comprehensive test suite for Installation Wizard functionality
/// These tests ensure the wizard correctly handles all system states, auto-fixes, and user interactions
@MainActor
final class WizardComprehensiveTests: XCTestCase {
    // MARK: - State Detection Tests

    /// Test that wizard correctly detects all possible system states
    func testSystemStateDetection() async throws {
        let detector = SystemStateDetector(
            kanataManager: MockKanataManager(),
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )

        // Test: Clean system with nothing installed
        let cleanState = await detector.detectSystemState()
        XCTAssertEqual(cleanState.state, .missingComponents(missing: []))
        XCTAssertTrue(cleanState.issues.contains { $0.category == .installation })

        // Test: Partially installed state
        let partialMock = MockKanataManager()
        partialMock.mockKanataInstalled = true
        partialMock.mockDriversInstalled = false
        let partialDetector = SystemStateDetector(
            kanataManager: partialMock,
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )
        let partialState = await partialDetector.detectSystemState()
        XCTAssertNotEqual(partialState.state, .active)
        XCTAssertFalse(partialState.issues.isEmpty)

        // Test: Fully operational state
        let fullMock = MockKanataManager()
        fullMock.mockKanataInstalled = true
        fullMock.mockDriversInstalled = true
        fullMock.mockServiceRunning = true
        fullMock.mockPermissionsGranted = true
        let fullDetector = SystemStateDetector(
            kanataManager: fullMock,
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )
        let fullState = await fullDetector.detectSystemState()
        XCTAssertEqual(fullState.state, .active)
        XCTAssertTrue(fullState.issues.isEmpty)
    }

    /// Test orphaned process detection logic
    func testOrphanedProcessDetection() async throws {
        let detector = SystemStateDetector(
            kanataManager: MockKanataManager(),
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )

        // Test: No orphaned process
        let noOrphanResult = detector.computeOrphanedProcessAutoFixWithMocks(
            orphanedProcess: nil,
            configPath: "/test/config.kbd",
            launchDaemonInstalled: true
        )
        XCTAssertNil(noOrphanResult.autoFix)
        XCTAssertTrue(noOrphanResult.issues.isEmpty)

        // Test: Orphaned process with config mismatch - should replace
        let mismatchProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 1234,
            command: "/usr/local/bin/kanata --cfg /wrong/path.kbd"
        )
        let mismatchResult = detector.computeOrphanedProcessAutoFixWithMocks(
            orphanedProcess: mismatchProcess,
            configPath: "/test/config.kbd",
            launchDaemonInstalled: true
        )
        XCTAssertEqual(mismatchResult.autoFix, .replaceOrphanedProcess)
        XCTAssertTrue(mismatchResult.issues.contains { $0.identifier == .service(.orphanedProcess) })

        // Test: Orphaned process with matching config - should adopt
        let matchingProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 5678,
            command: "/usr/local/bin/kanata --cfg /test/config.kbd --port 54141"
        )
        let matchResult = detector.computeOrphanedProcessAutoFixWithMocks(
            orphanedProcess: matchingProcess,
            configPath: "/test/config.kbd",
            launchDaemonInstalled: false
        )
        XCTAssertEqual(matchResult.autoFix, .adoptOrphanedProcess)
        XCTAssertTrue(matchResult.issues.contains { $0.identifier == .service(.orphanedProcess) })
    }

    /// Test Karabiner conflict detection
    func testKarabinerConflictDetection() async throws {
        let detector = SystemStateDetector(
            kanataManager: MockKanataManager(),
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )

        // Simulate Karabiner running
        let mockManager = MockKanataManager()
        mockManager.mockKarabinerRunning = true

        let conflictDetector = SystemStateDetector(
            kanataManager: mockManager,
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )
        let state = await conflictDetector.detectSystemState()

        XCTAssertTrue(state.issues.contains { $0.category == .conflicts })
        XCTAssertTrue(state.issues.contains { $0.identifier == .conflict(.karabinerRunning) })
    }

    // MARK: - Auto-Fix Workflow Tests

    /// Test complete auto-fix workflow for missing components
    func testAutoFixMissingComponents() async throws {
        let autoFixer = WizardAutoFixer(
            kanataManager: MockKanataManager(),
            toastManager: WizardToastManager()
        )

        // Test: Install missing Kanata
        let installResult = await autoFixer.performAutoFix(.installMissingComponents)
        XCTAssertTrue(installResult, "Should successfully handle component installation")

        // Test: Install LaunchDaemon services
        let daemonResult = await autoFixer.performAutoFix(.installLaunchDaemonServices)
        XCTAssertTrue(daemonResult, "Should successfully handle daemon installation")

        // Test: Create config directories
        let dirResult = await autoFixer.performAutoFix(.createConfigDirectories)
        XCTAssertTrue(dirResult, "Should successfully handle directory creation")
    }

    /// Test orphaned process adoption workflow
    func testOrphanedProcessAdoption() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockOrphanedProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 9999,
            command: "/usr/local/bin/kanata --cfg /test/config.kbd"
        )

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Test adoption workflow
        let adoptResult = await autoFixer.performAutoFix(.adoptOrphanedProcess)
        XCTAssertTrue(adoptResult, "Should successfully adopt orphaned process")

        // Verify the process was properly registered
        XCTAssertNotNil(mockManager.lastRegisteredPID)
        XCTAssertEqual(mockManager.lastRegisteredPID, 9999)
    }

    /// Test conflict resolution workflow
    func testConflictResolution() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockKarabinerRunning = true
        mockManager.mockConflictingProcesses = [
            ProcessLifecycleManager.ProcessInfo(pid: 111, command: "karabiner"),
            ProcessLifecycleManager.ProcessInfo(pid: 222, command: "kanata --cfg /other/path")
        ]

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Test terminating conflicting processes
        let terminateResult = await autoFixer.performAutoFix(.terminateConflictingProcesses)
        XCTAssertTrue(terminateResult, "Should successfully terminate conflicts")

        // Verify processes were terminated
        XCTAssertTrue(mockManager.terminatedPIDs.contains(111))
        XCTAssertTrue(mockManager.terminatedPIDs.contains(222))
    }

    // MARK: - Navigation and State Transition Tests

    /// Test wizard navigation logic based on system state
    func testWizardNavigationLogic() async throws {
        let coordinator = WizardNavigationCoordinator()
        let engine = coordinator.navigationEngine

        // Test: Critical issues should navigate to appropriate page
        let criticalIssues = [
            WizardIssue(
                identifier: .permission(.inputMonitoring),
                category: .permissions,
                severity: .critical,
                title: "Input Monitoring Required",
                message: "Grant permission",
                autoFixAction: nil
            )
        ]

        let targetPage = engine.determineTargetPage(
            for: .missingPermissions(missing: []),
            issues: criticalIssues
        )
        XCTAssertEqual(targetPage, .inputMonitoring)

        // Test: Multiple issues should prioritize correctly
        let multipleIssues = [
            WizardIssue(
                identifier: .conflict(.karabinerRunning),
                category: .conflicts,
                severity: .critical,
                title: "Karabiner Running",
                message: "Terminate Karabiner",
                autoFixAction: .terminateConflictingProcesses
            ),
            WizardIssue(
                identifier: .component(.kanataNotInstalled),
                category: .installation,
                severity: .error,
                title: "Kanata Not Installed",
                message: "Install Kanata",
                autoFixAction: .installMissingComponents
            )
        ]

        let priorityPage = engine.determineTargetPage(
            for: .missingComponents(missing: []),
            issues: multipleIssues
        )
        XCTAssertEqual(priorityPage, .conflicts, "Conflicts should be handled first")
    }

    /// Test state interpretation for UI display
    func testStateInterpretation() async throws {
        let interpreter = WizardStateInterpreter()

        // Test: Not installed state
        let notInstalledInfo = interpreter.getStateInfo(for: .missingComponents(missing: []))
        XCTAssertEqual(notInstalledInfo.title, "Welcome to KeyPath")
        XCTAssertEqual(notInstalledInfo.icon, "keyboard")
        XCTAssertEqual(notInstalledInfo.color.description, WizardDesign.Colors.warning.description)

        // Test: Fully operational state
        let operationalInfo = interpreter.getStateInfo(for: .active)
        XCTAssertEqual(operationalInfo.title, "KeyPath is Ready")
        XCTAssertEqual(operationalInfo.icon, "checkmark.circle.fill")
        XCTAssertEqual(operationalInfo.color.description, WizardDesign.Colors.success.description)

        // Test: Needs help state
        let needsHelpInfo = interpreter.getStateInfo(for: .conflictsDetected(conflicts: []))
        XCTAssertEqual(needsHelpInfo.title, "Action Required")
        XCTAssertEqual(needsHelpInfo.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(needsHelpInfo.color.description, WizardDesign.Colors.error.description)
    }

    // MARK: - Permission Handling Tests

    /// Test permission status detection and remediation
    func testPermissionHandling() async throws {
        let mockManager = MockKanataManager()

        // Test: No permissions granted
        mockManager.mockInputMonitoringGranted = false
        mockManager.mockAccessibilityGranted = false

        let detector = SystemStateDetector(
            kanataManager: mockManager,
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )
        let state = await detector.detectSystemState()

        XCTAssertTrue(state.issues.contains { $0.identifier == .permission(.inputMonitoring) })
        XCTAssertTrue(state.issues.contains { $0.identifier == .permission(.accessibility) })

        // Test: Partial permissions
        mockManager.mockInputMonitoringGranted = true
        mockManager.mockAccessibilityGranted = false

        let partialState = await detector.detectSystemState()
        XCTAssertFalse(partialState.issues.contains { $0.identifier == .permission(.inputMonitoring) })
        XCTAssertTrue(partialState.issues.contains { $0.identifier == .permission(.accessibility) })
    }

    // MARK: - Service Management Tests

    /// Test service lifecycle management
    func testServiceLifecycle() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockServiceRunning = false

        // Test: Start service
        let startResult = await mockManager.startKanata()
        XCTAssertTrue(mockManager.mockServiceRunning)

        // Test: Stop service
        await mockManager.stopKanata()
        XCTAssertFalse(mockManager.mockServiceRunning)

        // Test: Restart service
        mockManager.mockServiceRunning = true
        await mockManager.restartKanata()
        XCTAssertTrue(mockManager.restartCalled)
    }

    /// Test TCP server validation
    func testTCPServerValidation() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockTCPServerResponding = false

        let detector = SystemStateDetector(
            kanataManager: mockManager,
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )

        // Test: TCP server not responding
        let tcpDownState = await detector.detectSystemState()
        XCTAssertTrue(tcpDownState.issues.contains { $0.identifier == .service(.tcpServerNotResponding) })

        // Test: TCP server responding
        mockManager.mockTCPServerResponding = true
        let tcpUpState = await detector.detectSystemState()
        XCTAssertFalse(tcpUpState.issues.contains { $0.identifier == .service(.tcpServerNotResponding) })
    }

    // MARK: - Error Recovery Tests

    /// Test wizard's ability to recover from various error states
    func testErrorRecovery() async throws {
        let autoFixer = WizardAutoFixer(
            kanataManager: MockKanataManager(),
            toastManager: WizardToastManager()
        )

        // Test: Recovery from installation failure
        let mockManager = MockKanataManager()
        mockManager.shouldFailInstallation = true
        let failAutoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let installResult = await failAutoFixer.performAutoFix(.installMissingComponents)
        XCTAssertFalse(installResult, "Should handle installation failure gracefully")

        // Test: Recovery from permission denial
        mockManager.shouldFailPermissionGrant = true
        let permResult = await failAutoFixer.performAutoFix(.activateVHIDDeviceManager)
        XCTAssertFalse(permResult, "Should handle permission denial gracefully")
    }

    // MARK: - Integration Tests

    /// Test complete wizard flow from uninstalled to operational
    func testCompleteWizardFlow() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockKanataInstalled = false
        mockManager.mockDriversInstalled = false
        mockManager.mockServiceRunning = false
        mockManager.mockPermissionsGranted = false

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Step 1: Install components
        let installResult = await autoFixer.performAutoFix(.installMissingComponents)
        XCTAssertTrue(installResult)
        mockManager.mockKanataInstalled = true

        // Step 2: Install drivers
        let driverResult = await autoFixer.performAutoFix(.installViaBrew)
        XCTAssertTrue(driverResult)
        mockManager.mockDriversInstalled = true

        // Step 3: Grant permissions (simulated)
        mockManager.mockPermissionsGranted = true

        // Step 4: Install daemon
        let daemonResult = await autoFixer.performAutoFix(.installLaunchDaemonServices)
        XCTAssertTrue(daemonResult)

        // Step 5: Start service
        await mockManager.startKanata()
        XCTAssertTrue(mockManager.mockServiceRunning)

        // Verify final state
        let detector = SystemStateDetector(
            kanataManager: mockManager,
            launchDaemonInstaller: WizardMockLaunchDaemonInstaller()
        )
        let finalState = await detector.detectSystemState()
        XCTAssertEqual(finalState.state, .active)
        XCTAssertTrue(finalState.issues.isEmpty)
    }

    /// Test wizard's handling of concurrent operations
    func testConcurrentOperations() async throws {
        let operationManager = WizardAsyncOperationManager()
        var completedOperations: [String] = []

        // Create multiple concurrent operations
        let operation1 = WizardOperation(
            id: "test_op_1",
            name: "Test Operation 1",
            canRunConcurrently: true,
            execute: {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                completedOperations.append("op1")
                return true
            }
        )

        let operation2 = WizardOperation(
            id: "test_op_2",
            name: "Test Operation 2",
            canRunConcurrently: true,
            execute: {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                completedOperations.append("op2")
                return true
            }
        )

        // Execute concurrently
        async let result1 = operationManager.execute(operation: operation1) { (_: Bool) in }
        async let result2 = operationManager.execute(operation: operation2) { (_: Bool) in }

        _ = await (result1, result2)

        // Verify both operations completed
        XCTAssertEqual(completedOperations.count, 2)
        XCTAssertTrue(completedOperations.contains("op1"))
        XCTAssertTrue(completedOperations.contains("op2"))

        // Verify operation manager state
        XCTAssertFalse(operationManager.hasRunningOperations)
        XCTAssertEqual(operationManager.runningOperations.count, 0)
    }
}

// MARK: - Mock Objects

/// Mock KanataManager for testing
@MainActor
class MockKanataManager: KanataManager {
    var mockKanataInstalled = false
    var mockDriversInstalled = false
    var mockServiceRunning = false
    var mockPermissionsGranted = false
    var mockInputMonitoringGranted = true
    var mockAccessibilityGranted = true
    var mockKarabinerRunning = false
    var mockTCPServerResponding = true
    var mockOrphanedProcess: ProcessLifecycleManager.ProcessInfo?
    var mockConflictingProcesses: [ProcessLifecycleManager.ProcessInfo] = []

    var shouldFailInstallation = false
    var shouldFailPermissionGrant = false
    var restartCalled = false
    var lastRegisteredPID: pid_t?
    var terminatedPIDs: [pid_t] = []
    
    // AutoFix tracking properties
    var autoFixHistory: [String] = []
    var operationDelay: TimeInterval = 0
    var shouldFailMidway = false
    var supportRollback = false
    var rollbackCalled = false
    var rollbackActions: [String] = []
    var configPathMismatch = false
    var expectedConfigPath = ""
    var actualConfigPath = ""

    override func isKanataInstalled() -> Bool {
        mockKanataInstalled
    }

    override func isCompletelyInstalled() -> Bool {
        mockKanataInstalled && mockDriversInstalled
    }

    override var isRunning: Bool {
        get { mockServiceRunning }
        set { mockServiceRunning = newValue }
    }

    override func startKanata() async -> Bool {
        mockServiceRunning = true
        return true
    }

    override func stopKanata() async {
        mockServiceRunning = false
    }

    override func restartKanata() async {
        restartCalled = true
        mockServiceRunning = false
        try? await Task.sleep(nanoseconds: 100_000_000)
        mockServiceRunning = true
    }
}

/// Mock LaunchDaemonInstaller for comprehensive wizard testing
class WizardMockLaunchDaemonInstaller: LaunchDaemonInstaller {
    var mockPlistInstalled = false
    var mockServiceRunning = false

    override func isKanataPlistInstalled() -> Bool {
        mockPlistInstalled
    }

    override func createAllLaunchDaemonServices() async -> Bool {
        mockPlistInstalled = true
        return !shouldFailInstallation
    }

    var shouldFailInstallation = false
}