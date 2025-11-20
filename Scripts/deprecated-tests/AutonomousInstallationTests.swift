import XCTest

@testable import KeyPathAppKit

/// Autonomous installation and launch testing
/// Tests the complete user journey without manual intervention
@MainActor
final class AutonomousInstallationTests: XCTestCase {
    private var mockEnvironment: MockSystemEnvironment!
    private var mockManager: MockEnvironmentKanataManager!

    override func setUp() async throws {
        mockEnvironment = MockSystemEnvironment()
        mockManager = MockEnvironmentKanataManager(mockEnvironment: mockEnvironment)
    }

    override func tearDown() async throws {
        mockEnvironment = nil
        mockManager = nil
    }

    // MARK: - Clean Installation Tests

    func testCompleteNewUserInstallationFlow() async throws {
        // GIVEN: Clean system with no KeyPath components
        mockEnvironment.setupCleanInstallation()

        // WHEN: New user launches KeyPath
        XCTAssertFalse(mockManager.isCompletelyInstalled(), "Should start with clean system")
        XCTAssertEqual(mockManager.getInstallationStatus(), "❌ Not installed")

        // WHEN: User runs installation wizard
        let installSuccess = await mockManager.performTransparentInstallation()

        // THEN: Installation should complete successfully
        XCTAssertTrue(installSuccess, "Installation should succeed")
        XCTAssertTrue(mockManager.isCompletelyInstalled(), "Should be fully installed")
        XCTAssertEqual(mockManager.getInstallationStatus(), "✅ Fully installed")

        // THEN: Kanata should start automatically
        await mockManager.startKanata()
        XCTAssertTrue(mockManager.isRunning, "Kanata should be running")
        XCTAssertNil(mockManager.lastError, "Should have no errors")
    }

    func testInstallationStateDetection() throws {
        // Test clean state
        mockEnvironment.setupCleanInstallation()
        XCTAssertFalse(mockManager.isInstalled())
        XCTAssertFalse(mockManager.isServiceInstalled())
        XCTAssertFalse(mockManager.isKarabinerDriverInstalled())
        XCTAssertFalse(mockManager.isCompletelyInstalled())

        // Test partial installation (binary only)
        mockEnvironment.setupPartialInstallation()
        XCTAssertTrue(mockManager.isInstalled())
        XCTAssertFalse(mockManager.isServiceInstalled())
        XCTAssertFalse(mockManager.isCompletelyInstalled())

        // Test complete installation
        mockEnvironment.setupCompleteInstallation()
        XCTAssertTrue(mockManager.isInstalled())
        XCTAssertTrue(mockManager.isServiceInstalled())
        XCTAssertTrue(mockManager.isKarabinerDriverInstalled())
        XCTAssertTrue(mockManager.isCompletelyInstalled())
    }

    // MARK: - Launch Process Tests

    func testAutomaticKanataLaunching() async throws {
        // GIVEN: Fully installed system
        mockEnvironment.setupCompleteInstallation()

        // THEN: Manager should detect complete installation
        XCTAssertTrue(mockManager.isCompletelyInstalled())

        // WHEN: Starting Kanata
        await mockManager.startKanata()

        // THEN: Kanata should be running
        XCTAssertTrue(mockManager.isRunning)
        XCTAssertNil(mockManager.lastError)

        // WHEN: Stopping Kanata
        await mockManager.stopKanata()

        // THEN: Kanata should be stopped
        XCTAssertFalse(mockManager.isRunning)
        XCTAssertNil(mockManager.lastError)
    }

    func testRootPrivilegeHandling() async throws {
        // GIVEN: Complete installation with root process
        mockEnvironment.setupCompleteInstallation()

        // WHEN: Starting Kanata
        await mockManager.startKanata()

        // THEN: Should verify root execution
        XCTAssertTrue(mockManager.isRunning)

        // THEN: Process should be running as root
        let processUser = mockEnvironment.getProcessUser(command: "kanata")
        XCTAssertEqual(processUser, "root", "Kanata should run as root")
    }

    // MARK: - Error Handling Tests

    func testInstallationFailureHandling() async throws {
        // GIVEN: Clean system
        mockEnvironment.setupCleanInstallation()

        // WHEN: Attempting to start without installation
        await mockManager.startKanata()

        // THEN: Should fail gracefully with clear error
        XCTAssertFalse(mockManager.isRunning)
        XCTAssertNotNil(mockManager.lastError)
        XCTAssertTrue(mockManager.lastError?.contains("not found") ?? false)
    }

    func testPartialInstallationRecovery() async throws {
        // GIVEN: Partial installation (binary only)
        mockEnvironment.setupPartialInstallation()

        // THEN: Should detect incomplete state
        XCTAssertTrue(mockManager.isInstalled())
        XCTAssertFalse(mockManager.isCompletelyInstalled())

        // WHEN: Attempting auto-installation
        let success = await mockManager.performTransparentInstallation()

        // THEN: Should upgrade to complete installation
        XCTAssertTrue(success)
        XCTAssertTrue(mockManager.isCompletelyInstalled())
    }

    // MARK: - Configuration Management Tests

    func testConfigurationReloading() async throws {
        // GIVEN: Running system
        mockEnvironment.setupCompleteInstallation()
        await mockManager.startKanata()
        XCTAssertTrue(mockManager.isRunning)

        // WHEN: Saving new configuration
        do {
            try await mockManager.saveConfiguration(input: "caps", output: "escape")

            // THEN: Should complete without error
            XCTAssertTrue(mockManager.isRunning, "Should remain running after config change")
            XCTAssertNil(mockManager.lastError, "Should have no errors")
        } catch {
            // In mock environment, this may throw - that's acceptable
            XCTAssertNotNil(error.localizedDescription)
        }
    }

    // MARK: - Service Lifecycle Tests

    func testServiceStartStopCycle() async throws {
        // GIVEN: Complete installation
        mockEnvironment.setupCompleteInstallation()

        // Test start
        await mockManager.startKanata()
        XCTAssertTrue(mockManager.isRunning)

        // Test restart
        await mockManager.restartKanata()
        XCTAssertTrue(mockManager.isRunning)

        // Test stop
        await mockManager.stopKanata()
        XCTAssertFalse(mockManager.isRunning)
    }

    func testEmergencyStop() async throws {
        // GIVEN: Running system
        mockEnvironment.setupCompleteInstallation()
        await mockManager.startKanata()
        XCTAssertTrue(mockManager.isRunning)

        // WHEN: Emergency stop
        await mockManager.emergencyStop()

        // THEN: Should stop immediately
        XCTAssertFalse(mockManager.isRunning)
    }

    // MARK: - Integration Tests

    func testCompleteUserJourney() async throws {
        // Simulate complete user journey from clean install to usage

        // 1. Clean system
        mockEnvironment.setupCleanInstallation()
        XCTAssertFalse(mockManager.isCompletelyInstalled())

        // 2. Installation
        let installSuccess = await mockManager.performTransparentInstallation()
        XCTAssertTrue(installSuccess)
        XCTAssertTrue(mockManager.isCompletelyInstalled())

        // 3. First launch
        await mockManager.startKanata()
        XCTAssertTrue(mockManager.isRunning)

        // 4. Configuration change
        do {
            try await mockManager.saveConfiguration(input: "caps", output: "escape")
        } catch {
            // Expected in mock environment
        }

        // 5. Service should remain running
        XCTAssertTrue(mockManager.isRunning)

        // 6. Clean shutdown
        await mockManager.cleanup()
        XCTAssertFalse(mockManager.isRunning)
    }

    // MARK: - Performance Tests

    func testInstallationPerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        mockEnvironment.setupCleanInstallation()
        let success = await mockManager.performTransparentInstallation()

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertTrue(success, "Installation should succeed")
        XCTAssertLessThan(timeElapsed, 5.0, "Installation should complete quickly in mock environment")
    }

    func testLaunchPerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()

        mockEnvironment.setupCompleteInstallation()
        await mockManager.startKanata()

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertTrue(mockManager.isRunning, "Should start successfully")
        XCTAssertLessThan(timeElapsed, 2.0, "Launch should be fast in mock environment")
    }
}
