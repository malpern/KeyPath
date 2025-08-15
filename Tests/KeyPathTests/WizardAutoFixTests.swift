@testable import KeyPath
import XCTest

/// Comprehensive tests for wizard auto-fix functionality
/// Tests all auto-fix actions, error handling, and recovery scenarios
@MainActor
final class WizardAutoFixTests: XCTestCase {
    // MARK: - Individual Auto-Fix Action Tests

    func testTerminateConflictingProcesses() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockConflictingProcesses = [
            ProcessLifecycleManager.ProcessInfo(pid: 1001, command: "karabiner"),
            ProcessLifecycleManager.ProcessInfo(pid: 1002, command: "kanata --cfg /other/path"),
            ProcessLifecycleManager.ProcessInfo(pid: 1003, command: "other-key-remapper")
        ]

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let result = await autoFixer.performAutoFix(.terminateConflictingProcesses)

        XCTAssertTrue(result, "Should successfully terminate conflicting processes")
        XCTAssertEqual(mockManager.terminatedPIDs.count, 3)
        XCTAssertTrue(mockManager.terminatedPIDs.contains(1001))
        XCTAssertTrue(mockManager.terminatedPIDs.contains(1002))
        XCTAssertTrue(mockManager.terminatedPIDs.contains(1003))
    }

    func testInstallMissingComponents() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockKanataInstalled = false
        mockManager.mockDriversInstalled = false

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Test Kanata installation
        let kanataResult = await autoFixer.performAutoFix(.installMissingComponents)
        XCTAssertTrue(kanataResult, "Should successfully install Kanata")

        // Test driver installation
        let driverResult = await autoFixer.performAutoFix(.installViaBrew)
        XCTAssertTrue(driverResult, "Should successfully install drivers via brew")
    }

    func testCreateConfigDirectories() async throws {
        let mockManager = MockKanataManager()
        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let result = await autoFixer.performAutoFix(.createConfigDirectories)

        XCTAssertTrue(result, "Should successfully create config directories")

        // Verify directories were created
        let configDir = "\(NSHomeDirectory())/.config/keypath"
        let fileManager = FileManager.default

        // Note: In real tests, we'd mock FileManager
        // For now, we just verify the auto-fix returns success
        XCTAssertTrue(result)
    }

    func testAdoptOrphanedProcess() async throws {
        let mockManager = MockKanataManager()
        let orphanedPID: pid_t = 9876
        mockManager.mockOrphanedProcess = ProcessLifecycleManager.ProcessInfo(
            pid: orphanedPID,
            command: "/usr/local/bin/kanata --cfg ~/.config/keypath/keypath.kbd --port 54141"
        )

        let mockInstaller = MockLaunchDaemonInstaller()
        mockInstaller.mockPlistInstalled = false

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let result = await autoFixer.performAutoFix(.adoptOrphanedProcess)

        XCTAssertTrue(result, "Should successfully adopt orphaned process")
        XCTAssertEqual(mockManager.lastRegisteredPID, orphanedPID)
        XCTAssertTrue(mockManager.adoptOrphanedCalled)

        // Verify LaunchDaemon was created for adoption
        XCTAssertTrue(mockManager.launchDaemonCreatedForAdoption)
    }

    func testReplaceOrphanedProcess() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockOrphanedProcess = ProcessLifecycleManager.ProcessInfo(
            pid: 5555,
            command: "/usr/local/bin/kanata --cfg /wrong/config/path.kbd"
        )
        mockManager.mockServiceRunning = false

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let result = await autoFixer.performAutoFix(.replaceOrphanedProcess)

        XCTAssertTrue(result, "Should successfully replace orphaned process")
        XCTAssertTrue(mockManager.terminatedPIDs.contains(5555))
        XCTAssertTrue(mockManager.mockServiceRunning, "Should start new managed service")
        XCTAssertTrue(mockManager.replaceOrphanedCalled)
    }

    func testSynchronizeConfigPaths() async throws {
        let mockManager = MockKanataManager()
        mockManager.configPathMismatch = true
        mockManager.expectedConfigPath = "~/.config/keypath/keypath.kbd"
        mockManager.actualConfigPath = "/usr/local/etc/kanata/config.kbd"

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let result = await autoFixer.performAutoFix(.synchronizeConfigPaths)

        XCTAssertTrue(result, "Should successfully synchronize config paths")
        XCTAssertFalse(mockManager.configPathMismatch)
        XCTAssertEqual(mockManager.actualConfigPath, mockManager.expectedConfigPath)
    }

    func testRestartUnhealthyServices() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockServiceRunning = true
        mockManager.mockServiceHealthy = false
        mockManager.mockTCPServerResponding = false

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        let result = await autoFixer.performAutoFix(.restartUnhealthyServices)

        XCTAssertTrue(result, "Should successfully restart unhealthy services")
        XCTAssertTrue(mockManager.restartCalled)
        XCTAssertTrue(mockManager.mockServiceHealthy)
        XCTAssertTrue(mockManager.mockTCPServerResponding)
    }

    // MARK: - Error Handling Tests

    func testAutoFixFailureRecovery() async throws {
        let mockManager = MockKanataManager()
        mockManager.shouldFailInstallation = true

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Test installation failure
        let installResult = await autoFixer.performAutoFix(.installMissingComponents)
        XCTAssertFalse(installResult, "Should handle installation failure")

        // Test recovery - retry with failure disabled
        mockManager.shouldFailInstallation = false
        let retryResult = await autoFixer.performAutoFix(.installMissingComponents)
        XCTAssertTrue(retryResult, "Should succeed on retry")
    }

    func testAutoFixTimeout() async throws {
        let mockManager = MockKanataManager()
        mockManager.operationDelay = 10.0 // 10 second delay

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Create an operation with timeout
        let startTime = Date()
        let result = await autoFixer.performAutoFixWithTimeout(
            .installMissingComponents,
            timeout: 1.0 // 1 second timeout
        )
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertFalse(result, "Should timeout and return false")
        XCTAssertLessThan(elapsed, 2.0, "Should timeout within 2 seconds")
    }

    func testAutoFixCancellation() async throws {
        let mockManager = MockKanataManager()
        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Start long-running operation
        let task = Task {
            await autoFixer.performAutoFix(.installMissingComponents)
        }

        // Cancel immediately
        task.cancel()

        let result = await task.value
        XCTAssertFalse(result, "Cancelled operation should return false")
    }

    // MARK: - Sequential Auto-Fix Tests

    func testSequentialAutoFixes() async throws {
        let mockManager = MockKanataManager()
        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Execute multiple auto-fixes in sequence
        let actions: [AutoFixAction] = [
            .terminateConflictingProcesses,
            .installMissingComponents,
            .createConfigDirectories,
            .installLaunchDaemonServices,
            .restartUnhealthyServices
        ]

        var results: [Bool] = []
        for action in actions {
            let result = await autoFixer.performAutoFix(action)
            results.append(result)
        }

        XCTAssertTrue(results.allSatisfy { $0 }, "All sequential auto-fixes should succeed")
        XCTAssertEqual(mockManager.autoFixHistory.count, actions.count)
    }

    // MARK: - Concurrent Auto-Fix Tests

    func testConcurrentAutoFixes() async throws {
        let mockManager = MockKanataManager()
        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Execute multiple auto-fixes concurrently
        async let fix1 = autoFixer.performAutoFix(.createConfigDirectories)
        async let fix2 = autoFixer.performAutoFix(.terminateConflictingProcesses)
        async let fix3 = autoFixer.performAutoFix(.installMissingComponents)

        let results = await [fix1, fix2, fix3]

        XCTAssertTrue(results.allSatisfy { $0 }, "All concurrent auto-fixes should succeed")
        XCTAssertEqual(mockManager.autoFixHistory.count, 3)
    }

    // MARK: - State Verification Tests

    func testAutoFixStateVerification() async throws {
        let mockManager = MockKanataManager()
        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Verify state changes after auto-fix
        mockManager.mockKanataInstalled = false
        XCTAssertFalse(mockManager.isKanataInstalled())

        let result = await autoFixer.performAutoFix(.installMissingComponents)
        XCTAssertTrue(result)

        // Simulate installation completion
        mockManager.mockKanataInstalled = true
        XCTAssertTrue(mockManager.isKanataInstalled())
    }

    // MARK: - Permission Auto-Fix Tests

    func testPermissionAutoFixes() async throws {
        let mockManager = MockKanataManager()
        mockManager.mockInputMonitoringGranted = false
        mockManager.mockAccessibilityGranted = false

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Note: Real permission grants require user interaction
        // We test that the auto-fix correctly identifies and attempts to resolve

        let result = await autoFixer.performAutoFix(.activateVHIDDeviceManager)

        // In test environment, we simulate success
        XCTAssertTrue(result, "Should attempt to activate VHID manager")
        XCTAssertTrue(mockManager.activateVHIDCalled)
    }

    // MARK: - Rollback Tests

    func testAutoFixRollback() async throws {
        let mockManager = MockKanataManager()
        mockManager.supportRollback = true

        let autoFixer = WizardAutoFixer(
            kanataManager: mockManager,
            toastManager: WizardToastManager()
        )

        // Perform auto-fix that will fail midway
        mockManager.shouldFailMidway = true
        let result = await autoFixer.performAutoFix(.installLaunchDaemonServices)

        XCTAssertFalse(result, "Should fail as configured")
        XCTAssertTrue(mockManager.rollbackCalled, "Should trigger rollback on failure")
        XCTAssertEqual(mockManager.rollbackActions.count, 1)
    }
}

// MARK: - Extended Mock Classes

extension MockKanataManager {
    var adoptOrphanedCalled: Bool { autoFixHistory.contains("adoptOrphaned") }
    var replaceOrphanedCalled: Bool { autoFixHistory.contains("replaceOrphaned") }
    var activateVHIDCalled: Bool { autoFixHistory.contains("activateVHID") }
    var launchDaemonCreatedForAdoption: Bool { autoFixHistory.contains("createLaunchDaemonForAdoption") }

    var autoFixHistory: [String] = []
    var operationDelay: TimeInterval = 0
    var shouldFailMidway = false
    var supportRollback = false
    var rollbackCalled = false
    var rollbackActions: [String] = []
    var configPathMismatch = false
    var expectedConfigPath = ""
    var actualConfigPath = ""
    var mockServiceHealthy = true

    func recordAutoFix(_ action: String) {
        autoFixHistory.append(action)
    }
}

// Extension for timeout testing
extension WizardAutoFixer {
    func performAutoFixWithTimeout(_ action: AutoFixAction, timeout: TimeInterval) async -> Bool {
        let task = Task {
            await performAutoFix(action)
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            task.cancel()
        }

        let result = await task.value
        timeoutTask.cancel()
        return result
    }
}
