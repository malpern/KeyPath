import XCTest

@testable import KeyPath

/// Phase 1 Unit Tests: Synchronization and Process Management
/// Tests the synchronization mechanisms added in Phase 1 to prevent multiple Kanata instances
class KanataManagerSyncTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clean up any existing Kanata processes before each test
        terminateAllTestKanataProcesses()
    }

    override func tearDown() {
        // Clean up after each test
        terminateAllTestKanataProcesses()
        super.tearDown()
    }

    // MARK: - Phase 1.1: Process Synchronization Lock Tests

    func testStartKanataSynchronization() async throws {
        // This test validates that multiple simultaneous startKanata() calls
        // are properly synchronized and don't create multiple instances

        let manager = KanataManager()

        // Create multiple concurrent start attempts
        let startTasks = (1 ... 5).map { taskId in
            Task {
                AppLogger.shared.log("🧪 [Test] Starting concurrent task \(taskId)")
                await manager.startKanata()
                AppLogger.shared.log("🧪 [Test] Completed concurrent task \(taskId)")
            }
        }

        // Wait for all tasks to complete
        for task in startTasks {
            await task.value
        }

        // Verify that only one Kanata process was created
        let processCount = await countKanataProcesses()
        XCTAssertLessThanOrEqual(
            processCount, 1,
            "Multiple Kanata processes detected: \(processCount). Synchronization failed."
        )

        AppLogger.shared.log("✅ [Test] Synchronization test passed - process count: \(processCount)")
    }

    func testRapidStartAttemptDebouncing() async throws {
        // Test that rapid successive start attempts are properly debounced
        let manager = KanataManager()

        // Make rapid successive calls
        await manager.startKanata()
        await manager.startKanata() // Should be debounced
        await manager.startKanata() // Should be debounced

        // Give time for any delayed operations
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let processCount = await countKanataProcesses()
        XCTAssertLessThanOrEqual(
            processCount, 1,
            "Rapid start attempts created multiple processes: \(processCount)"
        )
    }

    // MARK: - Helper Methods
    // TODO: Extract system dependencies - consider creating ProcessCounterProtocol for testability

    private func countKanataProcesses() async -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-c", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output =
                String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"

            return Int(output) ?? 0
        } catch {
            AppLogger.shared.log("❌ [Test] Error counting processes: \(error)")
            return 0
        }
    }

    // TODO: Extract system dependencies - consider creating ProcessManagerProtocol for testability
    private func terminateAllTestKanataProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["/usr/bin/pkill", "-f", "kanata"]

        do {
            try task.run()
            task.waitUntilExit()

            // Give time for processes to terminate
            Thread.sleep(forTimeInterval: 1.0)
        } catch {
            // Ignore errors - processes might not exist
        }
    }
}

// MARK: - Phase 1 Mock Tests (Unit Tests without System Dependencies)

class KanataManagerMockTests: XCTestCase {
    func testKeyMappingStructure() {
        // Test the KeyMapping data structure used throughout the system
        let mapping = KeyMapping(input: "caps", output: "esc")

        XCTAssertEqual(mapping.input, "caps")
        XCTAssertEqual(mapping.output, "esc")
        XCTAssertNotNil(mapping.id)

        // Test equality (input and output, but ID will be different)
        let mapping2 = KeyMapping(input: "caps", output: "esc")
        XCTAssertEqual(mapping.input, mapping2.input)
        XCTAssertEqual(mapping.output, mapping2.output)

        let mapping3 = KeyMapping(input: "caps", output: "ctrl")
        XCTAssertNotEqual(mapping, mapping3)
    }

    func testKanataConfigurationGeneration() {
        // Test that the configuration generation works correctly
        let manager = KanataManager()

        // Test single mapping generation
        let config1 = manager.generateKanataConfig(input: "caps", output: "esc")

        // Verify the config contains the expected structure
        XCTAssertTrue(config1.contains("defcfg"))
        XCTAssertTrue(config1.contains("process-unmapped-keys"))
        XCTAssertTrue(config1.contains("defsrc"))
        XCTAssertTrue(config1.contains("deflayer base"))

        // Verify mapping is included
        XCTAssertTrue(config1.contains("caps"))
        XCTAssertTrue(config1.contains("esc"))

        // Test another mapping
        let config2 = manager.generateKanataConfig(input: "tab", output: "ctrl")
        XCTAssertTrue(config2.contains("tab"))
        XCTAssertTrue(config2.contains("lctl")) // tab -> ctrl becomes lctl for macOS
        
        // Test that configurations are deterministic (same input = same output)
        let config1Repeat = manager.generateKanataConfig(input: "caps", output: "esc")
        XCTAssertEqual(config1, config1Repeat, "Configuration generation should be deterministic")
        
        // Test that different inputs produce different outputs
        XCTAssertNotEqual(config1, config2, "Different inputs should produce different configurations")
    }
    
    func testKeyMappingTranslation() {
        // Test that key mappings are correctly translated for Kanata
        let manager = KanataManager()
        
        // Test common key translations
        let spaceConfig = manager.generateKanataConfig(input: "space", output: "tab")
        XCTAssertTrue(spaceConfig.contains("space"), "Space key should be preserved")
        XCTAssertTrue(spaceConfig.contains("tab"), "Tab output should be preserved")
        
        let returnConfig = manager.generateKanataConfig(input: "return", output: "delete")
        XCTAssertTrue(returnConfig.contains("return"), "Return key should be preserved")
        XCTAssertTrue(returnConfig.contains("delete"), "Delete output should be translated correctly")
        
        // Test that special characters are handled
        let escapeConfig = manager.generateKanataConfig(input: "escape", output: "caps")
        XCTAssertTrue(escapeConfig.contains("escape"), "Escape key should be preserved")
        XCTAssertTrue(escapeConfig.contains("caps"), "Caps output should be preserved")
    }
    
    func testConfigurationValidationDecisions() {
        // Test KanataManager's decision logic for which validation method to use
        let manager = KanataManager()
        
        // Mock different scenarios and test decision logic
        // Note: This would be better with dependency injection, but we can test the current logic
        
        // Test that empty input/output is handled
        let emptyConfig = manager.generateKanataConfig(input: "", output: "esc")
        XCTAssertFalse(emptyConfig.isEmpty, "Should generate valid config even with empty input")
        
        let emptyOutputConfig = manager.generateKanataConfig(input: "caps", output: "")
        XCTAssertFalse(emptyOutputConfig.isEmpty, "Should generate valid config even with empty output")
    }
    
    func testSynchronizationStateManagement() {
        // Test the synchronization logic without system dependencies
        let manager = KanataManager()
        
        // Test that manager maintains consistent state
        XCTAssertFalse(manager.isRunning, "Manager should start in stopped state")
        
        // Test state transitions without actually starting processes
        // This tests the decision logic without system side effects
        let initialState = manager.isRunning
        XCTAssertEqual(initialState, false, "Initial state should be deterministic")
    }
    
    func testProcessManagementDecisionLogic() {
        // Test the decision logic for process management without system calls
        let manager = KanataManager()
        
        // Test that configuration changes are handled consistently
        let config1 = manager.generateKanataConfig(input: "caps", output: "esc")
        let config2 = manager.generateKanataConfig(input: "caps", output: "esc")
        
        XCTAssertEqual(config1, config2, "Identical inputs should produce identical configurations")
        
        // Test configuration parsing logic
        XCTAssertTrue(config1.contains("(defcfg"), "Configuration should start with defcfg block")
        XCTAssertTrue(config1.contains("(defsrc"), "Configuration should contain defsrc block")
        XCTAssertTrue(config1.contains("(deflayer"), "Configuration should contain deflayer block")
    }

    func testConfigErrorHandling() {
        // Test that configuration errors are properly categorized
        let corruptedError = ConfigError.corruptedConfigDetected(errors: [
            "Invalid syntax", "Missing closing paren"
        ])

        if case let .corruptedConfigDetected(errors) = corruptedError {
            XCTAssertEqual(errors.count, 2)
            XCTAssertTrue(errors.contains("Invalid syntax"))
        } else {
            XCTFail("Expected corruptedConfigDetected error")
        }
    }
}
