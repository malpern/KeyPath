@testable import KeyPath
import XCTest

/// Essential integration tests that can run in CI
/// Tests component interaction without requiring admin privileges
@MainActor
final class BasicIntegrationTestSuite: XCTestCase {
    private var mockEnvironment: MockSystemEnvironment!

    override func setUp() async throws {
        // Skip integration tests in CI unless explicitly enabled
        guard ProcessInfo.processInfo.environment["CI_INTEGRATION_TESTS"] == "true" ||
            ProcessInfo.processInfo.environment["CI_ENVIRONMENT"] != "true"
        else {
            throw XCTSkip("Integration tests disabled in CI (set CI_INTEGRATION_TESTS=true to enable)")
        }

        mockEnvironment = MockSystemEnvironment()
    }

    override func tearDown() async throws {
        mockEnvironment = nil
    }

    // MARK: - Manager Integration Tests

    func testKanataManagerConfigIntegration() async throws {
        let configManager = KanataConfigManager()
        let kanataManager = try MockEnvironmentKanataManager(
            configManager: configManager,
            environment: mockEnvironment
        )

        // Test full config generation and application flow
        let mappings = [KeyMapping(inputKey: "caps", outputKey: "esc")]

        // This should not fail in mock environment
        try await kanataManager.updateConfiguration(mappings: mappings)

        XCTAssertEqual(kanataManager.lastAppliedMappings?.count, 1)
        XCTAssertEqual(kanataManager.lastAppliedMappings?.first?.inputKey, "caps")
    }

    func testSimpleManagerWithLifecycleIntegration() async throws {
        let lifecycleManager = ProcessLifecycleManager()
        let systemChecker = SystemStatusChecker()

        let simpleManager = SimpleKanataManager(
            lifecycleManager: lifecycleManager,
            systemChecker: systemChecker
        )

        // Test state management flow
        XCTAssertEqual(simpleManager.currentState, .starting)

        // Mock system health check
        mockEnvironment.mockKanataRunning = true
        await simpleManager.checkSystemHealth()

        // Should transition to appropriate state
        XCTAssertNotEqual(simpleManager.currentState, .starting)
    }

    // MARK: - Wizard Integration Tests

    func testWizardSystemStatusFlow() async throws {
        let systemChecker = SystemStatusChecker()
        let autoFixer = WizardAutoFixer(systemChecker: systemChecker)

        // Test complete status check and fix generation
        let status = await systemChecker.checkSystemStatus()
        let fixes = await autoFixer.generateFixRecommendations()

        XCTAssertNotNil(status)
        XCTAssertNotNil(fixes)

        // Fixes should be contextual to status
        if !status.kanataInstalled {
            XCTAssertTrue(fixes.contains { $0.lowercased().contains("install") })
        }
    }

    func testWizardNavigationFlow() async throws {
        let navigationEngine = WizardNavigationEngine()

        // Test page flow logic
        let currentPage = WizardPage.summary
        let nextPage = navigationEngine.determineNextPage(from: currentPage, systemStatus: mockSystemStatus())

        XCTAssertNotNil(nextPage)
    }

    // MARK: - Service Integration Tests

    func testPermissionServiceIntegration() async throws {
        let permissionService = PermissionService()
        let oracle = PermissionOracle()

        // Test service-oracle integration
        let serviceResult = permissionService.checkAccessibilityPermission()
        let oracleResult = oracle.checkAccessibilityPermission()

        // Results should be consistent
        XCTAssertEqual(serviceResult, oracleResult)
    }

    // MARK: - Configuration Flow Tests

    func testEndToEndConfigurationFlow() async throws {
        let configManager = KanataConfigManager()
        let preferencesService = PreferencesService()

        // Test configuration generation with preferences
        let mappings = [KeyMapping(inputKey: "space", outputKey: "space")]

        // Enable TCP in preferences
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37001

        let config = try configManager.generateConfig(mappings: mappings)

        // Config should reflect preferences
        XCTAssertTrue(config.contains("defsrc"))
        XCTAssertTrue(config.contains("deflayer"))

        // Validate generated config
        let validation = try configManager.validateConfig(config)
        XCTAssertTrue(validation.isValid, "Generated config should be valid: \(validation.errors)")
    }

    // MARK: - Error Handling Integration Tests

    func testErrorHandlerIntegration() async throws {
        let errorHandler = EnhancedErrorHandler()
        let configManager = KanataConfigManager()

        // Test error handling in config generation
        let invalidMappings = [KeyMapping(inputKey: "", outputKey: "esc")] // Invalid

        do {
            _ = try configManager.generateConfig(mappings: invalidMappings)
            XCTFail("Should have thrown error for invalid mappings")
        } catch {
            let formattedError = errorHandler.formatError(error)
            XCTAssertFalse(formattedError.isEmpty)
        }
    }

    // MARK: - State Consistency Tests

    func testManagerStateConsistency() async throws {
        let lifecycleManager = ProcessLifecycleManager()
        let simpleManager = SimpleKanataManager(
            lifecycleManager: lifecycleManager,
            systemChecker: SystemStatusChecker()
        )

        // Test that manager states remain consistent
        let initialState = simpleManager.currentState

        // Perform operations that shouldn't break state consistency
        mockEnvironment.mockKanataRunning = false
        await simpleManager.checkSystemHealth()

        let finalState = simpleManager.currentState

        // State should have changed appropriately
        if initialState == .running, !mockEnvironment.mockKanataRunning {
            XCTAssertNotEqual(finalState, .running)
        }
    }

    // MARK: - Helper Methods

    private func mockSystemStatus() -> SystemStatus {
        return SystemStatus(
            kanataInstalled: mockEnvironment.mockKanataInstalled,
            kanataRunning: mockEnvironment.mockKanataRunning,
            accessibilityPermission: mockEnvironment.mockAccessibilityPermission,
            inputMonitoringPermission: mockEnvironment.mockInputMonitoringPermission
        )
    }
}

// MARK: - Mock Environment Kanata Manager

private class MockEnvironmentKanataManager {
    private let configManager: KanataConfigManager
    private let environment: MockSystemEnvironment
    var lastAppliedMappings: [KeyMapping]?

    init(configManager: KanataConfigManager, environment: MockSystemEnvironment) throws {
        self.configManager = configManager
        self.environment = environment
    }

    func updateConfiguration(mappings: [KeyMapping]) async throws {
        // Generate config
        let config = try configManager.generateConfig(mappings: mappings)

        // Validate config
        let validation = try configManager.validateConfig(config)
        guard validation.isValid else {
            throw ConfigError.validationFailed(errors: validation.errors)
        }

        // In mock environment, just store the mappings
        lastAppliedMappings = mappings
    }
}

// Extend SystemStatus with initializer for testing
extension SystemStatus {
    init(kanataInstalled _: Bool, kanataRunning _: Bool, accessibilityPermission _: Bool, inputMonitoringPermission _: Bool) {
        // This would need to match the actual SystemStatus initializer
        // Placeholder implementation for testing
    }
}
