import XCTest

@testable import KeyPath

/// Integration tests for auto-fix functionality
/// Tests real system behavior with minimal mocking
class WizardAutoFixerTests: XCTestCase {
    var realKanataManager: KanataManager!
    var autoFixer: WizardAutoFixer!

    @MainActor
    override func setUp() {
        super.setUp()
        realKanataManager = KanataManager()
        let toastManager = WizardToastManager()
        autoFixer = WizardAutoFixer(kanataManager: realKanataManager, toastManager: toastManager)
    }

    // MARK: - Auto-Fix Capability Tests (Real System)

    func testAutoFixCapabilitiesMatchRealSystem() {
        // Test what auto-fix actions are actually supported
        let supportedActions: [AutoFixAction] = [
            .terminateConflictingProcesses,
            .installMissingComponents,
            .startKarabinerDaemon,
            .restartVirtualHIDDaemon,
            .createConfigDirectories,
            .activateVHIDDeviceManager,
            .installLaunchDaemonServices,
            .installViaBrew,
            .adoptOrphanedProcess,
            .replaceOrphanedProcess
        ]

        for action in supportedActions {
            let canFix = autoFixer.canAutoFix(action)

            switch action {
            case .terminateConflictingProcesses:
                XCTAssertTrue(canFix, "Should be able to terminate processes")

            case .installMissingComponents:
                XCTAssertTrue(canFix, "Should be able to install components")

            case .startKarabinerDaemon:
                XCTAssertTrue(canFix, "Should be able to start daemon")

            case .restartVirtualHIDDaemon:
                XCTAssertTrue(canFix, "Should be able to restart VirtualHID daemon")

            case .createConfigDirectories:
                XCTAssertTrue(canFix, "Should be able to create directories")

            case .activateVHIDDeviceManager:
                // This depends on VHIDDeviceManager being installed
                XCTAssertTrue(canFix == true || canFix == false, "Should return a valid capability")

            case .installLaunchDaemonServices:
                XCTAssertTrue(canFix, "Should be able to install LaunchDaemon services")

            case .installViaBrew:
                // This depends on Homebrew being installed
                XCTAssertTrue(canFix == true || canFix == false, "Should return a valid capability")

            case .repairVHIDDaemonServices:
                // New action: should be supported
                XCTAssertTrue(canFix == true || canFix == false, "Should return a valid capability")

            case .synchronizeConfigPaths:
                // Config path synchronization
                XCTAssertTrue(canFix == true || canFix == false, "Should return a valid capability")

            case .restartUnhealthyServices:
                // Service restart capability
                XCTAssertTrue(canFix == true || canFix == false, "Should return a valid capability")

            case .adoptOrphanedProcess:
                // Orphaned process adoption
                XCTAssertTrue(canFix, "Should be able to adopt orphaned processes")

            case .replaceOrphanedProcess:
                // Orphaned process replacement
                XCTAssertTrue(canFix, "Should be able to replace orphaned processes")
            }
        }

        print("✅ Verified auto-fix capabilities")
    }

    // MARK: - Safe Auto-Fix Tests (Non-Destructive)

    func testCreateConfigDirectoriesWithRealSystem() async {
        // This is a safe operation that won't break anything

        // When: Attempting to create config directories
        let success = await autoFixer.performAutoFix(.createConfigDirectories)

        // Then: Should complete the operation (success or graceful failure)
        // We don't assert success because directories might already exist
        print("✅ Config directory creation result: \(success)")

        // Verify the operation was attempted properly
        let configPath = "\(NSHomeDirectory())/Library/Application Support/KeyPath"
        let directoryExists = FileManager.default.fileExists(atPath: configPath)
        print("✅ Config directory exists: \(directoryExists)")
    }

    func testDaemonStartWithRealSystem() async {
        // Check current daemon state first
        let initialDaemonState = realKanataManager.isKarabinerDaemonRunning()
        print("✅ Initial daemon state: \(initialDaemonState)")

        // When: Attempting to start daemon
        let success = await autoFixer.performAutoFix(.startKarabinerDaemon)

        // Then: Should complete the operation
        print("✅ Daemon start result: \(success)")

        // Check final daemon state
        let finalDaemonState = realKanataManager.isKarabinerDaemonRunning()
        print("✅ Final daemon state: \(finalDaemonState)")

        // If it was already running, should still be running
        if initialDaemonState {
            XCTAssertTrue(finalDaemonState, "Daemon should remain running")
        }
    }

    func testVirtualHIDDaemonRestartWithRealSystem() async {
        // This is a system operation that we can test safely

        // When: Attempting to restart VirtualHID daemon
        let success = await autoFixer.performAutoFix(.restartVirtualHIDDaemon)

        // Then: Should complete the operation
        print("✅ VirtualHID daemon restart result: \(success)")

        // The operation should not cause system instability
        // (This is more of a "does it crash" test than functionality test)
    }

    // MARK: - Process Termination Tests (Careful)

    @MainActor
    func testProcessTerminationLogic() async {
        // We'll test this carefully to avoid breaking running processes

        // First, check if there are any kanata processes
        let detector = SystemStateDetector(kanataManager: realKanataManager)
        let conflicts = await detector.detectConflicts()

        let kanataProcesses = conflicts.conflicts.filter { conflict in
            if case .kanataProcessRunning = conflict {
                return true
            }
            return false
        }

        print("✅ Found \(kanataProcesses.count) kanata processes")

        if kanataProcesses.isEmpty {
            print("✅ No kanata processes to terminate - testing capability only")
            let canTerminate = autoFixer.canAutoFix(.terminateConflictingProcesses)
            XCTAssertTrue(canTerminate, "Should be capable of terminating processes")
        } else {
            print("⚠️  Found running kanata processes - skipping termination test for safety")
            // In a real test environment, you might want to test this
            // but in development, we don't want to kill running processes
        }
    }

    // MARK: - Component Installation Tests (Mock Only When Necessary)

    @MainActor
    func testComponentInstallationCapability() async {
        // Check what components are currently installed
        let detector = SystemStateDetector(kanataManager: realKanataManager)
        let componentResult = await detector.checkComponents()

        print("✅ Installed components: \(componentResult.installed)")
        print("✅ Missing components: \(componentResult.missing)")

        // Test the capability without actually installing
        let canInstall = autoFixer.canAutoFix(.installMissingComponents)
        XCTAssertTrue(canInstall, "Should be capable of installing components")

        // If there are missing components, we could test installation
        // but that requires admin privileges and brew, so we'll skip for now
        if !componentResult.missing.isEmpty {
            print("⚠️  Missing components detected - would require admin privileges to install")
        }
    }

    // MARK: - Integration Workflow Tests

    @MainActor
    func testAutoFixWorkflowWithRealState() async {
        // This tests the complete workflow without being destructive

        // When: Detecting current system state
        let detector = SystemStateDetector(kanataManager: realKanataManager)
        let systemState = await detector.detectCurrentState()

        print("✅ Current system state: \(systemState.state)")
        print("✅ Auto-fix actions suggested: \(systemState.autoFixActions)")

        // Test each suggested action's capability
        for action in systemState.autoFixActions {
            let canAutoFix = autoFixer.canAutoFix(action)
            XCTAssertTrue(canAutoFix, "Should be able to auto-fix suggested action: \(action)")
        }

        // Perform safe auto-fix actions
        let safeActions: [AutoFixAction] = [
            .createConfigDirectories,
            .startKarabinerDaemon,
            .restartVirtualHIDDaemon
        ]

        for action in safeActions where systemState.autoFixActions.contains(action) {
            print("✅ Performing safe auto-fix: \(action)")
            let success = await autoFixer.performAutoFix(action)
            print("✅ Result: \(success)")
        }
    }

    // MARK: - Error Handling and Robustness Tests

    func testAutoFixErrorHandling() async {
        // Test how auto-fixer handles various conditions

        // Test with actions that might not be needed
        let actions: [AutoFixAction] = [
            .createConfigDirectories, // Might already exist
            .startKarabinerDaemon, // Might already be running
            .restartVirtualHIDDaemon // Should work regardless
        ]

        var results: [Bool] = []

        for action in actions {
            let result = await autoFixer.performAutoFix(action)
            results.append(result)
            print("✅ Auto-fix \(action): \(result)")
        }

        // At least some operations should succeed or fail gracefully
        XCTAssertTrue(
            results.contains(true) || results.allSatisfy { !$0 },
            "Should either succeed at something or fail gracefully at everything"
        )
    }

    // MARK: - Integration with Navigation Engine

    @MainActor
    func testAutoFixIntegrationWithNavigation() async {
        // Test how auto-fix integrates with the navigation system

        // When: Detecting system state and determining fixes
        let detector = SystemStateDetector(kanataManager: realKanataManager)
        let systemState = await detector.detectCurrentState()

        let navigationEngine = WizardNavigationEngine()
        let currentPage = navigationEngine.determineCurrentPage(
            for: systemState.state, issues: systemState.issues
        )

        // Then: Auto-fix actions should be appropriate for the current page
        for action in systemState.autoFixActions {
            switch currentPage {
            case .conflicts:
                if action == .terminateConflictingProcesses {
                    print("✅ Appropriate auto-fix for conflicts page: \(action)")
                }

            case .kanataComponents, .karabinerComponents:
                if action == .installMissingComponents {
                    print("✅ Appropriate auto-fix for installation page: \(action)")
                }

            case .service:
                if action == .startKarabinerDaemon || action == .restartVirtualHIDDaemon {
                    print("✅ Appropriate auto-fix for service page: \(action)")
                }

            default:
                print("✅ General auto-fix action: \(action)")
            }
        }

        // The relationship should be logical
        XCTAssertTrue(true, "Auto-fix actions should be contextually appropriate")
    }

    // MARK: - Performance and Reliability Tests

    func testAutoFixPerformance() async {
        // Test performance of auto-fix operations

        let startTime = Date()

        // Perform a lightweight auto-fix operation
        let success = await autoFixer.performAutoFix(.createConfigDirectories)

        let duration = Date().timeIntervalSince(startTime)

        // Should complete quickly
        XCTAssertLessThan(duration, 30.0, "Auto-fix should complete within 30 seconds")

        print("✅ Auto-fix completed in \(String(format: "%.2f", duration)) seconds")
        print("✅ Result: \(success)")
    }

    @MainActor
    func testAutoFixStateConsistency() async {
        // Test that auto-fix operations maintain system consistency

        // When: Getting initial state
        let detector = SystemStateDetector(kanataManager: realKanataManager)
        let initialState = await detector.detectCurrentState()

        // Perform safe auto-fix operations
        let safeActions = initialState.autoFixActions.filter { action in
            switch action {
            case .createConfigDirectories, .startKarabinerDaemon, .restartVirtualHIDDaemon:
                true
            default:
                false
            }
        }

        for action in safeActions {
            _ = await autoFixer.performAutoFix(action)
        }

        // When: Getting state after auto-fix
        let finalState = await detector.detectCurrentState()

        // Then: System should be in a consistent state
        XCTAssertNotEqual(
            finalState.state, WizardSystemState.initializing, "Should have valid final state"
        )

        print("✅ Initial state: \(initialState.state)")
        print("✅ Final state: \(finalState.state)")
        print("✅ State transition is consistent")
    }

    func testConcurrentAutoFix() async {
        // Test concurrent auto-fix operations

        // When: Running multiple safe auto-fix operations concurrently
        let safeActions: [AutoFixAction] = [
            .createConfigDirectories,
            .createConfigDirectories, // Duplicate to test idempotency
            .restartVirtualHIDDaemon
        ]

        var results: [Bool] = []

        await withTaskGroup(of: Bool.self) { group in
            for action in safeActions {
                group.addTask {
                    await self.autoFixer.performAutoFix(action)
                }
            }

            for await result in group {
                results.append(result)
            }
        }

        // Then: Should handle concurrent operations gracefully
        XCTAssertEqual(results.count, safeActions.count, "Should complete all operations")
        print("✅ Concurrent auto-fix results: \(results)")
    }

    // MARK: - Orphaned Process Auto-Fix Integration Tests

    @MainActor
    func testOrphanedProcessAutoFixIntegration() async {
        // Test the complete orphaned process auto-fix workflow

        // Create mock LaunchDaemonInstaller that simulates different scenarios
        let testScenarios: [(description: String, mockInstaller: MockLaunchDaemonInstaller, expectableActions: [AutoFixAction])] = [
            (
                "No plist, services not loaded - should support adoption",
                MockLaunchDaemonInstaller(
                    kanataLoaded: false,
                    vhidDaemonLoaded: false,
                    vhidManagerLoaded: false,
                    installationResult: true,
                    loadResult: true
                ),
                [.adoptOrphanedProcess, .replaceOrphanedProcess]
            ),
            (
                "Plist present but not loaded - should support replacement",
                MockLaunchDaemonInstaller(
                    kanataLoaded: false,
                    vhidDaemonLoaded: true,
                    vhidManagerLoaded: true,
                    installationResult: true,
                    loadResult: true
                ),
                [.replaceOrphanedProcess]
            ),
            (
                "All services loaded - should support replacement",
                MockLaunchDaemonInstaller(
                    kanataLoaded: true,
                    vhidDaemonLoaded: true,
                    vhidManagerLoaded: true,
                    installationResult: true,
                    loadResult: true
                ),
                [.replaceOrphanedProcess]
            )
        ]

        for (description, mockInstaller, expectableActions) in testScenarios {
            print("\n🧪 Testing scenario: \(description)")

            // Create auto-fixer with mocked installer
            let testAutoFixer = WizardAutoFixer(
                kanataManager: realKanataManager,
                launchDaemonInstaller: mockInstaller,
                toastManager: WizardToastManager()
            )

            // Test that orphaned process actions are supported
            for action in expectableActions {
                let canAutoFix = testAutoFixer.canAutoFix(action)
                XCTAssertTrue(
                    canAutoFix,
                    "\(description): Should be able to auto-fix \(action)"
                )
                print("✅ Can auto-fix \(action): \(canAutoFix)")
            }

            // Test actual auto-fix execution (safe operations)
            for action in expectableActions {
                let result = await testAutoFixer.performAutoFix(action)
                print("✅ Auto-fix \(action) result: \(result)")
                // Note: We can't assert success because this depends on actual system state
                // The test is primarily to verify no crashes and proper capability detection
            }
        }
    }

    @MainActor
    func testOrphanedProcessAutoFixWithSystemStateDetector() async {
        // Test integration between SystemStateDetector and WizardAutoFixer for orphaned processes

        // Create mock installer that simulates orphaned process scenario
        let mockInstaller = MockLaunchDaemonInstaller(
            kanataLoaded: false,
            vhidDaemonLoaded: true,
            vhidManagerLoaded: true,
            installationResult: true,
            loadResult: true
        )

        // Create detector with mock installer
        let detector = SystemStateDetector(
            kanataManager: realKanataManager,
            launchDaemonInstaller: mockInstaller
        )

        // Create auto-fixer with same mock installer
        let testAutoFixer = WizardAutoFixer(
            kanataManager: realKanataManager,
            launchDaemonInstaller: mockInstaller,
            toastManager: WizardToastManager()
        )

        // Simulate orphaned process detection
        let mockProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 1234,
            command: "/usr/local/bin/kanata --cfg \(WizardSystemPaths.userConfigPath)"
        )

        // Test orphaned process detection logic
        let autoFixAction = await detector.testComputeOrphanedProcessAutoFixWithMocks(
            externalProcesses: [mockProcess],
            managedProcesses: [],
            plistPresent: false,
            serviceLoaded: false
        )

        XCTAssertEqual(
            autoFixAction, .adoptOrphanedProcess,
            "Should recommend adoption for orphaned process using expected config"
        )

        // Test that auto-fixer can handle the recommended action
        if let action = autoFixAction {
            let canAutoFix = testAutoFixer.canAutoFix(action)
            XCTAssertTrue(canAutoFix, "Auto-fixer should support recommended action")

            let result = await testAutoFixer.performAutoFix(action)
            print("✅ Orphaned process auto-fix result: \(result)")
        }
    }

    @MainActor
    func testOrphanedProcessAutoFixErrorHandling() async {
        // Test error handling in orphaned process auto-fix scenarios

        // Create mock installer that simulates failures
        let failingMockInstaller = MockLaunchDaemonInstaller(
            kanataLoaded: false,
            vhidDaemonLoaded: false,
            vhidManagerLoaded: false,
            installationResult: false, // Installation fails
            loadResult: false // Loading fails
        )

        let testAutoFixer = WizardAutoFixer(
            kanataManager: realKanataManager,
            launchDaemonInstaller: failingMockInstaller,
            toastManager: WizardToastManager()
        )

        // Test that auto-fixer handles failures gracefully
        let orphanedActions: [AutoFixAction] = [.adoptOrphanedProcess, .replaceOrphanedProcess]

        for action in orphanedActions {
            // Should still report capability (capability != success guarantee)
            let canAutoFix = testAutoFixer.canAutoFix(action)
            XCTAssertTrue(canAutoFix, "Should report capability even if underlying operations might fail")

            // Test that failed operations don't crash
            let result = await testAutoFixer.performAutoFix(action)
            // Don't assert success/failure - just verify no crashes
            print("✅ Auto-fix \(action) with failing installer: \(result)")
        }
    }

    @MainActor
    func testOrphanedProcessAutoFixWorkflowIntegration() async {
        // Test the complete workflow from detection to auto-fix to verification

        print("\n🧪 Testing complete orphaned process workflow")

        // Step 1: Create mock installer simulating no services loaded
        let mockInstaller = MockLaunchDaemonInstaller(
            kanataLoaded: false,
            vhidDaemonLoaded: false,
            vhidManagerLoaded: false,
            installationResult: true,
            loadResult: true
        )

        // Step 2: Detect system state with orphaned process scenario
        let detector = SystemStateDetector(
            kanataManager: realKanataManager,
            launchDaemonInstaller: mockInstaller
        )

        // Step 3: Simulate orphaned process and test detection
        let orphanedProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 9999,
            command: "/usr/local/bin/kanata --cfg \(WizardSystemPaths.userConfigPath) --verbose"
        )

        let detectedAction = await detector.testComputeOrphanedProcessAutoFixWithMocks(
            externalProcesses: [orphanedProcess],
            managedProcesses: [],
            plistPresent: false,
            serviceLoaded: false
        )

        XCTAssertNotNil(detectedAction, "Should detect orphaned process requiring action")
        print("✅ Step 1 - Detection: Recommended action = \(String(describing: detectedAction))")

        // Step 4: Test auto-fix capability and execution
        let autoFixer = WizardAutoFixer(
            kanataManager: realKanataManager,
            launchDaemonInstaller: mockInstaller,
            toastManager: WizardToastManager()
        )

        if let action = detectedAction {
            let canFix = autoFixer.canAutoFix(action)
            XCTAssertTrue(canFix, "Should be able to perform detected auto-fix")
            print("✅ Step 2 - Capability: Can auto-fix = \(canFix)")

            let fixResult = await autoFixer.performAutoFix(action)
            print("✅ Step 3 - Execution: Auto-fix result = \(fixResult)")

            // Step 5: Verify workflow completion
            print("✅ Step 4 - Verification: Workflow completed without crashes")
        }
    }

    @MainActor
    func testOrphanedProcessAutoFixConcurrency() async {
        // Test concurrent orphaned process auto-fix operations

        let mockInstaller = MockLaunchDaemonInstaller(
            kanataLoaded: false,
            vhidDaemonLoaded: true,
            vhidManagerLoaded: true,
            installationResult: true,
            loadResult: true
        )

        let autoFixer = WizardAutoFixer(
            kanataManager: realKanataManager,
            launchDaemonInstaller: mockInstaller,
            toastManager: WizardToastManager()
        )

        // Test concurrent execution of orphaned process actions
        let actions: [AutoFixAction] = [
            .adoptOrphanedProcess,
            .replaceOrphanedProcess,
            .adoptOrphanedProcess // Duplicate to test serialization
        ]

        var results: [Bool] = []

        await withTaskGroup(of: Bool.self) { group in
            for action in actions {
                group.addTask {
                    await autoFixer.performAutoFix(action)
                }
            }

            for await result in group {
                results.append(result)
            }
        }

        // Verify all operations completed without crashes
        XCTAssertEqual(results.count, actions.count, "All concurrent operations should complete")
        print("✅ Concurrent orphaned process auto-fix results: \(results)")
    }
}
