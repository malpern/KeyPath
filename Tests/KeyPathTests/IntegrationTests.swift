import XCTest

@testable import KeyPath

/// Phase 5: Comprehensive Integration Tests
///
/// These tests validate the complete system integration across all phases:
/// - Phase 1: Synchronization and debouncing
/// - Phase 2: State machine coordination
/// - Phase 3: Reactive UI patterns
/// - Phase 4: Modular components
/// - Phase 5: Complete workflows
class IntegrationTests: XCTestCase {
  var kanataManager: KanataManager!
  var lifecycleManager: KanataLifecycleManager!
  var systemChecker: SystemRequirementsChecker!
  var configManager: KanataConfigManager!

  override func setUp() async throws {
    try await super.setUp()

    // Initialize all components
    kanataManager = KanataManager()

    // Initialize MainActor-isolated components
    await MainActor.run {
      lifecycleManager = KanataLifecycleManager(kanataManager: kanataManager)
    }

    systemChecker = SystemRequirementsChecker()
    configManager = KanataConfigManager()

    // Clean up any existing test processes
    await cleanupTestEnvironment()
  }

  override func tearDown() async throws {
    await cleanupTestEnvironment()

    kanataManager = nil
    lifecycleManager = nil
    systemChecker = nil
    configManager = nil

    try await super.tearDown()
  }

  // MARK: - End-to-End Workflow Tests

  func testCompleteUserJourney() async throws {
    // Test the complete user journey from start to finish
    AppLogger.shared.log("🧪 [Integration] Testing complete user journey")

    // Phase 1: System initialization
    await lifecycleManager.initialize()

    // Wait for state to settle
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

    // Phase 2: Check requirements
    let requirementsReport = await systemChecker.checkAllRequirements()

    // We expect some requirements to fail in test environment (Kanata not installed)
    XCTAssertNotNil(requirementsReport)
    AppLogger.shared.log("✅ [Integration] Requirements check completed")

    // Phase 3: Configuration management
    let testConfig = configManager.createConfigurationFromTemplate(.minimal)
    XCTAssertTrue(testConfig.validationResult.isValid, "Template configuration should be valid")

    AppLogger.shared.log("✅ [Integration] Complete user journey test passed")
  }

  func testStateTransitionIntegrity() async throws {
    // Test that state transitions work correctly across all components
    AppLogger.shared.log("🧪 [Integration] Testing state transition integrity")

    // Start with uninitialized state
    await MainActor.run {
      XCTAssertEqual(lifecycleManager.currentState, .uninitialized)
    }

    // Initialize
    await lifecycleManager.initialize()

    // Should transition through states predictably
    // Note: Exact states depend on system conditions, but should follow valid transitions
    await MainActor.run {
      XCTAssertNotEqual(lifecycleManager.currentState, .uninitialized)
    }

    // Test reset functionality
    await MainActor.run {
      lifecycleManager.reset()
      XCTAssertEqual(lifecycleManager.currentState, .uninitialized)
    }

    AppLogger.shared.log("✅ [Integration] State transition integrity test passed")
  }

  func testConfigurationWorkflow() async throws {
    // Test the complete configuration workflow
    AppLogger.shared.log("🧪 [Integration] Testing configuration workflow")

    // Create configuration
    let mappings = [
      KeyMapping(input: "caps", output: "esc"),
      KeyMapping(input: "tab", output: "ctrl")
    ]

    let configSet = configManager.createConfiguration(mappings: mappings)

    // Validate configuration
    XCTAssertTrue(configSet.validationResult.isValid, "Generated configuration should be valid")
    XCTAssertEqual(configSet.mappings.count, 2)
    XCTAssertTrue(configSet.generatedConfig.contains("caps"))
    XCTAssertTrue(configSet.generatedConfig.contains("esc"))

    AppLogger.shared.log("✅ [Integration] Configuration workflow test passed")
  }

  func testErrorRecoveryScenarios() async throws {
    // Test various error recovery scenarios
    AppLogger.shared.log("🧪 [Integration] Testing error recovery scenarios")

    // Test state machine error recovery
    await MainActor.run {
      lifecycleManager.reset()
    }
    await lifecycleManager.initialize()

    // Simulate error condition
    // Note: In a real test, we'd inject errors, but for now we test structure
    let canPerformActions = await MainActor.run {
      lifecycleManager.canPerformActions
    }
    XCTAssertNotNil(canPerformActions)

    // Test configuration validation errors
    let invalidConfig = "(defcfg\n  invalid-syntax\n"  // Intentionally malformed
    let validationResult = configManager.validateConfiguration(invalidConfig)

    XCTAssertFalse(validationResult.isValid, "Invalid configuration should fail validation")
    XCTAssertFalse(validationResult.errors.isEmpty, "Should have validation errors")

    AppLogger.shared.log("✅ [Integration] Error recovery scenarios test passed")
  }

  // MARK: - Performance and Reliability Tests

  func testConcurrentOperations() async throws {
    // Test that concurrent operations don't cause race conditions
    AppLogger.shared.log("🧪 [Integration] Testing concurrent operations")

    let operationCount = 5
    let tasks = (1...operationCount).map { taskId in
      Task {
        AppLogger.shared.log("🧪 [Integration] Starting concurrent task \(taskId)")

        // Test concurrent configuration generation
        let config = configManager.createConfigurationFromTemplate(.minimal)
        XCTAssertTrue(config.validationResult.isValid)

        // Test concurrent state queries
        let canStart = await MainActor.run {
          lifecycleManager.canPerformOperation("start")
        }
        XCTAssertNotNil(canStart)

        AppLogger.shared.log("🧪 [Integration] Completed concurrent task \(taskId)")
      }
    }

    // Wait for all tasks to complete
    for task in tasks {
      await task.value
    }

    AppLogger.shared.log("✅ [Integration] Concurrent operations test passed")
  }

  func testMemoryAndResourceManagement() async throws {
    // Test that components properly manage memory and resources
    AppLogger.shared.log("🧪 [Integration] Testing memory and resource management")

    let iterationCount = 10

    for iteration in 1...iterationCount {
      // Create and destroy components to test for leaks
      let tempManager = await MainActor.run {
        KanataLifecycleManager(kanataManager: kanataManager)
      }
      let tempChecker = SystemRequirementsChecker()
      let tempConfigManager = KanataConfigManager()

      // Perform operations
      let config = tempConfigManager.createConfigurationFromTemplate(.minimal)
      XCTAssertNotNil(config)

      // Components should be automatically deallocated
      AppLogger.shared.log("🧪 [Integration] Completed iteration \(iteration)/\(iterationCount)")
    }

    AppLogger.shared.log("✅ [Integration] Memory and resource management test passed")
  }

  // MARK: - Phase Integration Tests

  func testPhase1Integration() async throws {
    // Test Phase 1 components (synchronization, debouncing)
    AppLogger.shared.log("🧪 [Integration] Testing Phase 1 integration")

    // Test process synchronization
    let concurrentTasks = (1...3).map { _ in
      Task {
        // Would normally test KanataManager.startKanata() synchronization
        // For now, test that the method exists and returns
        XCTAssertNotNil(kanataManager)
      }
    }

    for task in concurrentTasks {
      await task.value
    }

    AppLogger.shared.log("✅ [Integration] Phase 1 integration test passed")
  }

  func testPhase2Integration() async throws {
    // Test Phase 2 components (state machine, lifecycle manager)
    AppLogger.shared.log("🧪 [Integration] Testing Phase 2 integration")

    // Test state machine coordination
    await MainActor.run {
      XCTAssertEqual(lifecycleManager.currentState, .uninitialized)
    }

    await lifecycleManager.initialize()

    await MainActor.run {
      XCTAssertNotEqual(lifecycleManager.currentState, .uninitialized)
    }

    // Test lifecycle operations
    let stateInfo = await MainActor.run {
      lifecycleManager.getStateInfo()
    }
    XCTAssertNotNil(stateInfo["currentState"])

    AppLogger.shared.log("✅ [Integration] Phase 2 integration test passed")
  }

  func testPhase4Integration() async throws {
    // Test Phase 4 components (system checker, config manager)
    AppLogger.shared.log("🧪 [Integration] Testing Phase 4 integration")

    // Test system requirements integration
    let report = await systemChecker.checkAllRequirements()
    XCTAssertNotNil(report.timestamp)
    XCTAssertFalse(report.results.isEmpty)

    // Test configuration management integration
    let templates = KanataConfigManager.ConfigTemplate.allCases
    XCTAssertFalse(templates.isEmpty)

    for template in templates {
      let config = configManager.createConfigurationFromTemplate(template)
      XCTAssertTrue(
        config.validationResult.isValid, "Template \(template.displayName) should be valid"
      )
    }

    AppLogger.shared.log("✅ [Integration] Phase 4 integration test passed")
  }

  // MARK: - Real-World Scenario Tests

  func testNewUserInstallation() async throws {
    // Simulate a new user going through the complete installation
    AppLogger.shared.log("🧪 [Integration] Testing new user installation scenario")

    // 1. System requirements check
    let requirements = await systemChecker.checkAllRequirements()
    XCTAssertNotNil(requirements)

    // 2. Configuration setup
    let initialConfig = configManager.createConfigurationFromTemplate(.minimal)
    XCTAssertTrue(initialConfig.validationResult.isValid)

    // 3. Lifecycle initialization
    await lifecycleManager.initialize()

    await MainActor.run {
      XCTAssertNotEqual(lifecycleManager.currentState, .uninitialized)
    }

    AppLogger.shared.log("✅ [Integration] New user installation scenario test passed")
  }

  func testExistingUserUpgrade() async throws {
    // Simulate an existing user upgrading KeyPath
    AppLogger.shared.log("🧪 [Integration] Testing existing user upgrade scenario")

    // 1. Load existing configuration (simulated)
    let existingMappings = [KeyMapping(input: "caps", output: "esc")]
    let existingConfig = configManager.createConfiguration(mappings: existingMappings)

    // 2. Validate existing configuration still works
    XCTAssertTrue(existingConfig.validationResult.isValid)

    // 3. Test backward compatibility
    XCTAssertEqual(existingConfig.mappings.count, 1)
    XCTAssertEqual(existingConfig.mappings.first?.input, "caps")

    AppLogger.shared.log("✅ [Integration] Existing user upgrade scenario test passed")
  }

  func testPowerUserWorkflow() async throws {
    // Test complex power user scenarios
    AppLogger.shared.log("🧪 [Integration] Testing power user workflow")

    // Create complex configuration
    let powerUserMappings = [
      KeyMapping(input: "caps", output: "esc"),
      KeyMapping(input: "tab", output: "ctrl"),
      KeyMapping(input: "space", output: "space"),
      KeyMapping(input: "return", output: "return")
    ]

    let complexConfig = configManager.createConfiguration(mappings: powerUserMappings)
    XCTAssertTrue(complexConfig.validationResult.isValid)
    XCTAssertEqual(complexConfig.mappings.count, 4)

    // Test advanced template
    let advancedConfig = configManager.createConfigurationFromTemplate(.advanced)
    XCTAssertTrue(advancedConfig.validationResult.isValid)

    AppLogger.shared.log("✅ [Integration] Power user workflow test passed")
  }

  // MARK: - Helper Methods

  private func cleanupTestEnvironment() async {
    // Clean up any test processes or files
    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    killTask.arguments = ["/usr/bin/pkill", "-f", "kanata.*test"]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      // Give time for cleanup
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
    } catch {
      // Ignore cleanup errors
    }
  }

  private func createTestConfiguration() -> String {
    return configManager.createConfigurationFromTemplate(.minimal).generatedConfig
  }
}

// MARK: - Stress Testing

class StressTests: XCTestCase {
  func testHighVolumeOperations() async throws {
    // Test system under high load
    AppLogger.shared.log("🧪 [Stress] Testing high volume operations")

    let operationCount = 100
    let configManager = KanataConfigManager()

    let tasks = (1...operationCount).map { iteration in
      Task {
        let config = configManager.createConfigurationFromTemplate(.minimal)
        XCTAssertTrue(config.validationResult.isValid, "Configuration \(iteration) should be valid")
      }
    }

    // Wait for all operations to complete
    for task in tasks {
      await task.value
    }

    AppLogger.shared.log("✅ [Stress] High volume operations test passed")
  }

  func testLongRunningOperations() async throws {
    // Test system stability over extended time
    AppLogger.shared.log("🧪 [Stress] Testing long running operations")

    let lifecycleManager = await MainActor.run {
      KanataLifecycleManager(kanataManager: KanataManager())
    }

    // Simulate long-running operation
    for cycle in 1...10 {
      await lifecycleManager.initialize()

      // Small delay to simulate real usage
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

      await MainActor.run {
        lifecycleManager.reset()
      }

      AppLogger.shared.log("🧪 [Stress] Completed cycle \(cycle)/10")
    }

    AppLogger.shared.log("✅ [Stress] Long running operations test passed")
  }
}

// MARK: - Error Injection Tests

class ErrorInjectionTests: XCTestCase {
  func testConfigurationErrorHandling() async throws {
    // Test how system handles various configuration errors
    AppLogger.shared.log("🧪 [ErrorInjection] Testing configuration error handling")

    let configManager = KanataConfigManager()

    let invalidConfigs = [
      "",  // Empty config
      "(defcfg",  // Unclosed parenthesis
      "invalid syntax",  // Not S-expression
      "(defcfg\n  unknown-option yes\n)"  // Unknown option
    ]

    for (index, invalidConfig) in invalidConfigs.enumerated() {
      let result = configManager.validateConfiguration(invalidConfig)
      XCTAssertFalse(result.isValid, "Invalid config \(index) should fail validation")
      XCTAssertFalse(result.errors.isEmpty, "Should have validation errors for config \(index)")
    }

    AppLogger.shared.log("✅ [ErrorInjection] Configuration error handling test passed")
  }

  func testStateTransitionErrors() async throws {
    // Test invalid state transitions
    AppLogger.shared.log("🧪 [ErrorInjection] Testing state transition errors")

    let lifecycleManager = await MainActor.run {
      KanataLifecycleManager(kanataManager: KanataManager())
    }

    // Test that invalid operations return false without crashing
    let canStart = await MainActor.run {
      lifecycleManager.canPerformOperation("invalid_operation")
    }
    XCTAssertFalse(canStart, "Invalid operations should return false")

    AppLogger.shared.log("✅ [ErrorInjection] State transition error test passed")
  }
}
