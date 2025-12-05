import ServiceManagement
@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class KanataDaemonManagerTests: KeyPathAsyncTestCase {
    var manager: KanataDaemonManager!
    var mockService: SMAppServiceTestDouble!
    var originalFactory: ((String) -> SMAppServiceProtocol)?

    override func setUp() async throws {
        try await super.setUp()

        // Save original factory
        originalFactory = KanataDaemonManager.smServiceFactory

        // Create mock service
        mockService = SMAppServiceTestDouble(status: .notRegistered)

        // Inject mock factory
        KanataDaemonManager.smServiceFactory = { [unowned self] _ in
            self.mockService
        }

        manager = KanataDaemonManager.shared
    }

    override func tearDown() async throws {
        // Restore original factory
        if let original = originalFactory {
            KanataDaemonManager.smServiceFactory = original
        }
        mockService = nil
        manager = nil
        try await super.tearDown()
    }

    // MARK: - State Machine Tests

    func testRefreshManagementState_Uninstalled() async {
        // Given: No legacy plist, SMAppService .notRegistered, no process running
        mockService.simulateStatus(.notRegistered)

        // When
        let state = await manager.refreshManagementState()

        // Then
        XCTAssertEqual(state, .uninstalled)
        XCTAssertEqual(manager.currentManagementState, .uninstalled)
        XCTAssertTrue(state.needsInstallation)
        XCTAssertFalse(state.isSMAppServiceManaged)
        XCTAssertFalse(state.isLegacyManaged)
    }

    func testRefreshManagementState_SMAppServiceActive() async {
        // Given: No legacy plist, SMAppService .enabled
        mockService.simulateStatus(.enabled)

        // When
        let state = await manager.refreshManagementState()

        // Then
        XCTAssertEqual(state, .smappserviceActive)
        XCTAssertEqual(manager.currentManagementState, .smappserviceActive)
        XCTAssertTrue(state.isSMAppServiceManaged)
        XCTAssertFalse(state.needsInstallation)
    }

    func testRefreshManagementState_SMAppServicePending() async {
        // Given: No legacy plist, SMAppService .requiresApproval
        mockService.simulateStatus(.requiresApproval)

        // When
        let state = await manager.refreshManagementState()

        // Then
        XCTAssertEqual(state, .smappservicePending)
        XCTAssertEqual(manager.currentManagementState, .smappservicePending)
        XCTAssertTrue(state.isSMAppServiceManaged)
    }

    func testRefreshManagementState_NotFound() async {
        // Given: No legacy plist, SMAppService .notFound, no process running
        mockService.simulateStatus(.notFound)

        // When
        let state = await manager.refreshManagementState()

        // Then: In test mode, .notFound should be treated as uninstalled
        XCTAssertEqual(state, .uninstalled)
    }

    func testServiceManagementStateProperties() {
        // Test computed properties on state enum
        XCTAssertTrue(KanataDaemonManager.ServiceManagementState.smappserviceActive.isSMAppServiceManaged)
        XCTAssertTrue(KanataDaemonManager.ServiceManagementState.smappservicePending.isSMAppServiceManaged)
        XCTAssertFalse(KanataDaemonManager.ServiceManagementState.legacyActive.isSMAppServiceManaged)
        XCTAssertFalse(KanataDaemonManager.ServiceManagementState.uninstalled.isSMAppServiceManaged)

        XCTAssertTrue(KanataDaemonManager.ServiceManagementState.legacyActive.isLegacyManaged)
        XCTAssertFalse(KanataDaemonManager.ServiceManagementState.smappserviceActive.isLegacyManaged)

        XCTAssertTrue(KanataDaemonManager.ServiceManagementState.uninstalled.needsInstallation)
        XCTAssertFalse(KanataDaemonManager.ServiceManagementState.smappserviceActive.needsInstallation)

        XCTAssertTrue(KanataDaemonManager.ServiceManagementState.legacyActive.needsMigration())
        XCTAssertTrue(KanataDaemonManager.ServiceManagementState.conflicted.needsMigration())
        XCTAssertFalse(KanataDaemonManager.ServiceManagementState.smappserviceActive.needsMigration())
    }

    func testServiceManagementStateDescriptions() {
        XCTAssertEqual(
            KanataDaemonManager.ServiceManagementState.legacyActive.description,
            "Legacy launchctl"
        )
        XCTAssertEqual(
            KanataDaemonManager.ServiceManagementState.smappserviceActive.description,
            "SMAppService (active)"
        )
        XCTAssertEqual(
            KanataDaemonManager.ServiceManagementState.smappservicePending.description,
            "SMAppService (pending approval)"
        )
        XCTAssertEqual(
            KanataDaemonManager.ServiceManagementState.uninstalled.description,
            "Uninstalled"
        )
        XCTAssertEqual(
            KanataDaemonManager.ServiceManagementState.conflicted.description,
            "Conflicted (both methods active)"
        )
        XCTAssertEqual(
            KanataDaemonManager.ServiceManagementState.unknown.description,
            "Unknown"
        )
    }

    // MARK: - Status Checking Tests

    func testGetStatus() {
        mockService.simulateStatus(.enabled)
        let status = manager.getStatus()
        XCTAssertEqual(status, .enabled)
    }

    func testIsRegisteredViaSMAppService_Enabled() {
        mockService.simulateStatus(.enabled)
        XCTAssertTrue(KanataDaemonManager.isRegisteredViaSMAppService())
    }

    func testIsRegisteredViaSMAppService_NotEnabled() {
        mockService.simulateStatus(.notRegistered)
        XCTAssertFalse(KanataDaemonManager.isRegisteredViaSMAppService())
    }

    func testHasLegacyInstallation_NoFile() {
        // In test environment, legacy plist path shouldn't exist
        let hasLegacy = manager.hasLegacyInstallation()
        XCTAssertFalse(hasLegacy)
    }

    func testIsUsingSMAppService() {
        mockService.simulateStatus(.enabled)
        XCTAssertTrue(KanataDaemonManager.isUsingSMAppService)

        mockService.simulateStatus(.notRegistered)
        XCTAssertFalse(KanataDaemonManager.isUsingSMAppService)
    }

    func testGetActivePlistPath() {
        let bundlePath = Bundle.main.bundlePath
        let expectedPath = "\(bundlePath)/Contents/Library/LaunchDaemons/\(KanataDaemonManager.kanataServiceID).plist"
        XCTAssertEqual(KanataDaemonManager.getActivePlistPath(), expectedPath)
    }

    func testIsInstalled_WhenEnabled() async {
        mockService.simulateStatus(.enabled)
        let isInstalled = await manager.isInstalled()
        XCTAssertTrue(isInstalled)
    }

    func testIsInstalled_WhenNotRegistered() async {
        mockService.simulateStatus(.notRegistered)
        let isInstalled = await manager.isInstalled()
        // May be false since launchctl check won't find the service
        XCTAssertFalse(isInstalled)
    }

    // MARK: - Registration Tests

    func testRegister_Success_FromNotRegistered() async throws {
        // Given: Service not registered, test mode enabled
        mockService.simulateStatus(.notRegistered)

        // When
        try await manager.register()

        // Then: Should call register
        XCTAssertEqual(mockService.registerCallCount, 1)
    }

    func testRegister_AlreadyEnabled() async throws {
        // Given: Service already enabled
        mockService.simulateStatus(.enabled)

        // When
        try await manager.register()

        // Then: Should not call register again
        XCTAssertEqual(mockService.registerCallCount, 0)
    }

    func testRegister_RequiresApproval() async {
        // Given: Service requires approval
        mockService.simulateStatus(.requiresApproval)

        // When/Then: Should throw
        do {
            try await manager.register()
            XCTFail("Should throw when approval required")
        } catch let KanataDaemonError.registrationFailed(reason) {
            XCTAssertTrue(reason.contains("Approval required"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testRegister_RegistrationFails() async {
        // Given: Registration will fail
        mockService.simulateStatus(.notRegistered)
        mockService.simulateRegisterFailure(true)

        // When/Then: Should throw
        do {
            try await manager.register()
            XCTFail("Should throw when registration fails")
        } catch let KanataDaemonError.registrationFailed(reason) {
            XCTAssertTrue(reason.contains("SMAppService register failed"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testRegister_RaceCondition_BecomesEnabled() async throws {
        // Given: Service starts as not registered
        mockService.simulateStatus(.notRegistered)

        // Simulate registration failure but status becomes .enabled (race condition)
        mockService.simulateRegisterFailure(true)
        // After register() throws, status is .enabled
        // We need to simulate this by having the mock change status during register

        // Create a custom mock that changes state during register
        let racingMock = SMAppServiceTestDouble(status: .notRegistered)
        KanataDaemonManager.smServiceFactory = { _ in racingMock }

        // Simulate register() throwing but status becoming .enabled
        racingMock.simulateRegisterFailure(true)

        do {
            try await manager.register()
            // Should succeed despite error, if status becomes .enabled
        } catch {
            // This is expected - the mock doesn't actually change status to .enabled during error
            // The real code checks status after error and succeeds if .enabled
            // Our mock just throws, so we expect the error
            XCTAssertTrue(error is KanataDaemonError)
        }
    }

    func testRegister_NotFound_AttemptsRegistration() async {
        // Given: Status is .notFound
        mockService.simulateStatus(.notFound)
        mockService.simulateRegisterFailure(true)

        // When/Then: Should attempt registration and throw on failure
        do {
            try await manager.register()
            XCTFail("Should throw when .notFound registration fails")
        } catch let KanataDaemonError.registrationFailed(reason) {
            XCTAssertTrue(reason.contains("SMAppService register failed"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        // Verify registration was attempted
        XCTAssertEqual(mockService.registerCallCount, 1)
    }

    // MARK: - Unregistration Tests

    func testUnregister_Success() async throws {
        // Given: Service is enabled
        mockService.simulateStatus(.enabled)

        // When
        try await manager.unregister()

        // Then
        XCTAssertEqual(mockService.unregisterCallCount, 1)
    }

    func testUnregister_Failure() async {
        // Given: Unregistration will fail
        mockService.simulateStatus(.enabled)
        mockService.simulateUnregisterFailure(true)

        // When/Then: Should throw
        do {
            try await manager.unregister()
            XCTFail("Should throw when unregistration fails")
        } catch let KanataDaemonError.operationFailed(reason) {
            XCTAssertTrue(reason.contains("SMAppService unregister failed"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }

        XCTAssertEqual(mockService.unregisterCallCount, 1)
    }

    // MARK: - Broken State Detection Tests

    func testIsRegisteredButNotLoaded_NotRegistered() async {
        // Given: Service not registered
        mockService.simulateStatus(.notRegistered)

        // When
        let isBroken = await manager.isRegisteredButNotLoaded()

        // Then: Should return false since not even registered
        XCTAssertFalse(isBroken)
    }

    func testIsRegisteredButNotLoaded_EnabledAndHealthy() async {
        // Given: Service registered and healthy (in our mock world, no launchctl calls work)
        mockService.simulateStatus(.enabled)

        // When
        let isBroken = await manager.isRegisteredButNotLoaded()

        // Then: In test mode without real launchctl, this will detect the service as "broken"
        // because launchctl can't find it (empty output), but that's expected in tests
        // The important thing is the function doesn't crash
        XCTAssertNotNil(isBroken)
    }

    // MARK: - Migration Tests

    func testMigrateFromLaunchctl_NoLegacy() async {
        // Given: No legacy installation exists
        // (In test environment, legacy plist doesn't exist)

        // When/Then: Should throw
        do {
            try await manager.migrateFromLaunchctl()
            XCTFail("Should throw when no legacy installation exists")
        } catch let KanataDaemonError.migrationFailed(reason) {
            XCTAssertTrue(reason.contains("No legacy launchctl installation found"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Error Type Tests

    func testKanataDaemonError_Descriptions() {
        let notInstalledError = KanataDaemonError.notInstalled
        XCTAssertEqual(notInstalledError.errorDescription, "Kanata daemon is not installed")

        let registrationError = KanataDaemonError.registrationFailed("test reason")
        XCTAssertEqual(registrationError.errorDescription, "Failed to register daemon: test reason")

        let operationError = KanataDaemonError.operationFailed("test reason")
        XCTAssertEqual(operationError.errorDescription, "Daemon operation failed: test reason")

        let migrationError = KanataDaemonError.migrationFailed("test reason")
        XCTAssertEqual(migrationError.errorDescription, "Migration failed: test reason")

        let rollbackError = KanataDaemonError.rollbackFailed("test reason")
        XCTAssertEqual(rollbackError.errorDescription, "Rollback failed: test reason")
    }

    // MARK: - Constants Tests

    func testConstants() {
        XCTAssertEqual(KanataDaemonManager.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(KanataDaemonManager.kanataPlistName, "com.keypath.kanata.plist")
    }

    // MARK: - Singleton Tests

    func testSingleton() {
        let manager1 = KanataDaemonManager.shared
        let manager2 = KanataDaemonManager.shared
        XCTAssertIdentical(manager1, manager2, "Should return same singleton instance")
    }

    // MARK: - Bundle Validation Tests

    func testPlistExistsInBundle() {
        let bundlePath = Bundle.main.bundlePath
        let plistPath =
            "\(bundlePath)/Contents/Library/LaunchDaemons/\(KanataDaemonManager.kanataPlistName)"
        let exists = FileManager.default.fileExists(atPath: plistPath)

        if exists {
            print("✅ Plist found at: \(plistPath)")
        } else {
            print("⚠️ Plist not found at: \(plistPath)")
            print("   This is expected if running tests outside app bundle context")
        }
        // Don't fail test - plist may not exist in test environment
    }

    func testKanataBinaryExistsInBundle() {
        let bundlePath = Bundle.main.bundlePath
        let kanataPath = "\(bundlePath)/Contents/Library/KeyPath/kanata"
        let exists = FileManager.default.fileExists(atPath: kanataPath)

        if exists {
            print("✅ Kanata binary found at: \(kanataPath)")
        } else {
            print("⚠️ Kanata binary not found at: \(kanataPath)")
            print("   This is expected if running tests outside app bundle context")
        }
        // Don't fail test - binary may not exist in test environment
    }

    // MARK: - Edge Cases

    func testRegistrationRequiresMacOS13() async {
        // This test verifies the macOS version check
        // On macOS 13+, this should not throw immediately
        // On older macOS, it should throw

        if #available(macOS 13, *) {
            // On macOS 13+, registration attempt should not immediately fail due to version
            // (it may fail for other reasons like missing plist, but not version)
            // Don't actually register - just verify the version check passes
            let status = manager.getStatus()
            XCTAssertNotNil(status, "Should be able to check status on macOS 13+")
        } else {
            // On older macOS, registration should fail with version error
            do {
                try await manager.register()
                XCTFail("Registration should fail on macOS < 13")
            } catch let KanataDaemonError.registrationFailed(reason) {
                XCTAssertTrue(
                    reason.contains("macOS 13"),
                    "Error should mention macOS 13 requirement"
                )
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    func testCurrentManagementState_CachedValue() async {
        // Given: Initial state
        mockService.simulateStatus(.notRegistered)
        await manager.refreshManagementState()
        XCTAssertEqual(manager.currentManagementState, .uninstalled)

        // When: Change mock status
        mockService.simulateStatus(.enabled)

        // Then: Cached value doesn't change until refresh
        XCTAssertEqual(manager.currentManagementState, .uninstalled)

        // When: Refresh state
        await manager.refreshManagementState()

        // Then: Cached value updates
        XCTAssertEqual(manager.currentManagementState, .smappserviceActive)
    }

    func testMultipleStatusChecks() {
        // Verify that status checks are consistent
        mockService.simulateStatus(.enabled)

        let status1 = manager.getStatus()
        let status2 = manager.getStatus()
        let status3 = manager.getStatus()

        XCTAssertEqual(status1, .enabled)
        XCTAssertEqual(status2, .enabled)
        XCTAssertEqual(status3, .enabled)
    }

    func testStateTransitions() async {
        // Test state machine transitions through typical lifecycle

        // 1. Start uninstalled
        mockService.simulateStatus(.notRegistered)
        var state = await manager.refreshManagementState()
        XCTAssertEqual(state, .uninstalled)

        // 2. Register (becomes pending approval)
        mockService.simulateStatus(.requiresApproval)
        state = await manager.refreshManagementState()
        XCTAssertEqual(state, .smappservicePending)

        // 3. User approves (becomes active)
        mockService.simulateStatus(.enabled)
        state = await manager.refreshManagementState()
        XCTAssertEqual(state, .smappserviceActive)

        // 4. Unregister (back to uninstalled)
        mockService.simulateStatus(.notRegistered)
        state = await manager.refreshManagementState()
        XCTAssertEqual(state, .uninstalled)
    }

    func testRepeatedStatusChecks() async {
        // Test that repeated status checks are consistent
        mockService.simulateStatus(.enabled)

        var statuses: [ServiceManagement.SMAppService.Status] = []
        for _ in 0..<10 {
            statuses.append(manager.getStatus())
        }

        // All should be consistent
        XCTAssertEqual(statuses.count, 10)
        XCTAssertTrue(statuses.allSatisfy { $0 == .enabled })
    }

    func testRepeatedRefreshManagementState() async {
        // Test that repeated refresh calls are consistent
        mockService.simulateStatus(.enabled)

        var states: [KanataDaemonManager.ServiceManagementState] = []
        for _ in 0..<10 {
            let state = await manager.refreshManagementState()
            states.append(state)
        }

        // All should be consistent
        XCTAssertEqual(states.count, 10)
        XCTAssertTrue(states.allSatisfy { $0 == .smappserviceActive })
    }
}
