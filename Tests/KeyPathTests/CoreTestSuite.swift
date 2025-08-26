@testable import KeyPath
import XCTest

/// Core test suite combining essential functionality tests
/// Replaces scattered test files with focused, CI-friendly tests
@MainActor
final class CoreTestSuite: XCTestCase {
    private var mockEnvironment: MockSystemEnvironment!

    override func setUp() async throws {
        mockEnvironment = MockSystemEnvironment()
    }

    override func tearDown() async throws {
        mockEnvironment = nil
    }

    // MARK: - Configuration Management Tests

    func testKanataConfigGeneration() async throws {
        let manager = KanataConfigManager()
        let mapping = KeyMapping(inputKey: "caps", outputKey: "escape")

        let config = try manager.generateConfig(mappings: [mapping])

        XCTAssertTrue(config.contains("defsrc"))
        XCTAssertTrue(config.contains("deflayer"))
        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("esc"))
    }

    func testConfigValidation() async throws {
        let manager = KanataConfigManager()

        // Valid config
        let validConfig = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps)
        (deflayer base esc)
        """

        let result = try manager.validateConfig(validConfig)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    // MARK: - Manager State Tests

    func testSimpleKanataManagerStates() async throws {
        let manager = SimpleKanataManager(
            lifecycleManager: mockEnvironment.lifecycleManager,
            systemChecker: mockEnvironment.systemChecker
        )

        // Initial state
        XCTAssertEqual(manager.currentState, .starting)

        // Mock successful start
        mockEnvironment.mockKanataRunning = true
        await manager.checkSystemHealth()

        XCTAssertEqual(manager.currentState, .running)
    }

    func testProcessLifecycleBasics() async throws {
        let manager = ProcessLifecycleManager()

        // Test PID detection
        let mockProcess = MockProcess(pid: 12345, isRunning: true)
        mockEnvironment.mockProcess = mockProcess

        let isRunning = manager.isKanataRunning()
        XCTAssertTrue(isRunning)
    }

    // MARK: - Permission Service Tests

    func testPermissionChecking() async throws {
        let service = PermissionService()

        // Mock permission states
        mockEnvironment.mockAccessibilityPermission = true
        mockEnvironment.mockInputMonitoringPermission = false

        let accessibility = service.checkAccessibilityPermission()
        let inputMonitoring = service.checkInputMonitoringPermission()

        XCTAssertTrue(accessibility)
        XCTAssertFalse(inputMonitoring)
    }

    // MARK: - TCP Integration Tests

    func testTCPClientConnection() async throws {
        let client = KanataTCPClient()

        // Test connection failure (expected in CI)
        do {
            _ = try await client.connect(to: 37000)
            XCTFail("Should not connect in test environment")
        } catch {
            // Expected failure in CI
            XCTAssertTrue(error is KanataTCPClient.TCPError)
        }
    }

    // MARK: - Wizard Core Logic Tests

    func testSystemStatusDetection() async throws {
        let checker = SystemStatusChecker()

        // Mock system states
        mockEnvironment.mockKanataInstalled = true
        mockEnvironment.mockKanataRunning = false

        let status = await checker.checkSystemStatus()

        XCTAssertTrue(status.kanataInstalled)
        XCTAssertFalse(status.kanataRunning)
    }

    func testAutoFixerDecisionMaking() async throws {
        let fixer = WizardAutoFixer(systemChecker: mockEnvironment.systemChecker)

        // Test fix recommendation
        mockEnvironment.mockKanataInstalled = false
        let recommendations = await fixer.generateFixRecommendations()

        XCTAssertTrue(recommendations.contains { $0.contains("install") })
    }

    // MARK: - Error Handling Tests

    func testEnhancedErrorHandlerFormatting() throws {
        let handler = EnhancedErrorHandler()
        let error = NSError(domain: "TestError", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        let formatted = handler.formatError(error)

        XCTAssertTrue(formatted.contains("Test error"))
        XCTAssertTrue(formatted.contains("123"))
    }

    // MARK: - Utilities Tests

    func testAppRestarter() throws {
        let restarter = AppRestarter()

        // Test validation only (don't actually restart in tests)
        XCTAssertNoThrow(restarter.validateRestartCapability())
    }

    func testLoggingConfiguration() throws {
        let logger = Logger.shared

        // Test logger initialization
        XCTAssertNotNil(logger)
        XCTAssertNoThrow(logger.info("Test log message"))
    }
}

// MARK: - Mock Classes for Testing

private class MockProcess {
    let pid: Int32
    let isRunning: Bool

    init(pid: Int32, isRunning: Bool) {
        self.pid = pid
        self.isRunning = isRunning
    }
}
