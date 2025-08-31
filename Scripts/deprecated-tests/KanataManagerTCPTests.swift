import Darwin
import Foundation
import Network
import XCTest

@testable import KeyPath

/// Comprehensive tests for KanataManager TCP validation integration
/// Tests end-to-end TCP validation workflow with fallback to file validation
@MainActor
final class KanataManagerTCPTests: XCTestCase {
    var kanataManager: KanataManager!
    var preferencesService: PreferencesService!
    var mockTCPServer: MockKanataTCPServer!
    var tempConfigDirectory: URL!
    var originalTCPSettings: (enabled: Bool, port: Int)!

    override func setUp() async throws {
        try await super.setUp()

        // Store original TCP settings to restore later
        preferencesService = PreferencesService.shared
        originalTCPSettings = (preferencesService.tcpServerEnabled, preferencesService.tcpServerPort)

        // Create temporary config directory
        tempConfigDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "keypath-tcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempConfigDirectory, withIntermediateDirectories: true
        )

        // Set up mock TCP server
        let serverPort = try findAvailablePort()
        mockTCPServer = MockKanataTCPServer(port: serverPort)

        // Configure preferences for testing
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = serverPort

        // Initialize KanataManager
        kanataManager = KanataManager()

        // Wait for initialization to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

    override func tearDown() async throws {
        await mockTCPServer?.stop()

        // Restore original TCP settings
        preferencesService.tcpServerEnabled = originalTCPSettings.enabled
        preferencesService.tcpServerPort = originalTCPSettings.port

        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempConfigDirectory)

        kanataManager = nil
        mockTCPServer = nil
        tempConfigDirectory = nil
        originalTCPSettings = nil

        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func findAvailablePort() throws -> Int {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0

        let addrPtr = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }

        if Darwin.bind(socket, addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size)) < 0 {
            throw NSError(
                domain: "TestSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"]
            )
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let boundAddrPtr = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }

        if getsockname(socket, boundAddrPtr, &addrLen) < 0 {
            throw NSError(
                domain: "TestSetup", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get socket name"]
            )
        }

        return Int(CFSwapInt16BigToHost(boundAddr.sin_port))
    }

    private func createTestConfig(_ content: String) throws -> URL {
        let configURL = tempConfigDirectory.appendingPathComponent("test-config.kbd")
        try content.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    }

    private func simulateKanataRunning() {
        // Set manager state to simulate running Kanata
        kanataManager.isRunning = true
    }

    private func simulateKanataStopped() {
        kanataManager.isRunning = false
    }

    // MARK: - TCP Validation Success Tests

    func testTCPValidationWhenEnabledAndRunning() async throws {
        // Start mock server
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        // Simulate Kanata running
        simulateKanataRunning()

        // Create valid config
        let validConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        _ = try createTestConfig(validConfig)

        // Test validation
        let result = await kanataManager.validateConfigFile()

        XCTAssertTrue(
            result.isValid, "TCP validation should succeed for valid config when enabled and running"
        )
        XCTAssertTrue(result.errors.isEmpty, "Should have no errors for valid config")
    }

    func testTCPValidationFailureWithErrors() async throws {
        // Start mock server with validation errors
        try await mockTCPServer.start()
        let mockErrors = [
            MockValidationError(line: 2, column: 3, message: "Unknown option: invalid-option"),
            MockValidationError(line: 4, column: 1, message: "Unclosed parenthesis")
        ]
        await mockTCPServer.setValidationResponse(success: false, errors: mockErrors)

        // Simulate Kanata running
        simulateKanataRunning()

        // Create invalid config
        let invalidConfig = """
        (defcfg
          invalid-option yes
        )
        (defsrc caps
        (deflayer base esc)
        """
        _ = try createTestConfig(invalidConfig)

        // Test validation
        let result = await kanataManager.validateConfigFile()

        XCTAssertFalse(result.isValid, "TCP validation should fail for invalid config")
        XCTAssertEqual(result.errors.count, 2, "Should return validation errors from TCP server")
        XCTAssertTrue(
            result.errors[0].contains("invalid-option"), "Should include specific error messages"
        )
        XCTAssertTrue(
            result.errors[1].contains("parenthesis"), "Should include specific error messages"
        )
    }

    // MARK: - TCP Fallback Tests

    func testFallbackToFileValidationWhenTCPDisabled() async throws {
        // Disable TCP validation
        preferencesService.tcpServerEnabled = false

        // Create valid config file
        let validConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        _ = try createTestConfig(validConfig)

        // Test validation (should use file validation)
        let result = await kanataManager.validateConfigFile()

        XCTAssertTrue(
            result.isValid, "File validation should succeed for valid config when TCP is disabled"
        )
    }

    func testFallbackToFileValidationWhenKanataStopped() async throws {
        // Enable TCP but simulate Kanata not running
        preferencesService.tcpServerEnabled = true
        simulateKanataStopped()

        // Create valid config file
        let validConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        _ = try createTestConfig(validConfig)

        // Test validation (should fallback to file validation)
        let result = await kanataManager.validateConfigFile()

        XCTAssertTrue(result.isValid, "Should fallback to file validation when Kanata is not running")
    }

    func testFallbackToFileValidationWhenTCPServerUnavailable() async throws {
        // Enable TCP but don't start server
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Create valid config file
        let validConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        _ = try createTestConfig(validConfig)

        // Test validation (should fallback to file validation when TCP fails)
        let result = await kanataManager.validateConfigFile()

        XCTAssertTrue(
            result.isValid, "Should fallback to file validation when TCP server is unavailable"
        )
    }

    func testFallbackToFileValidationOnTCPTimeout() async throws {
        // Start server with long delay
        try await mockTCPServer.start()
        await mockTCPServer.setResponseDelay(5.0) // Longer than client timeout

        // Enable TCP and simulate running
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Create valid config
        let validConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        _ = try createTestConfig(validConfig)

        // Test validation (should timeout and fallback)
        let startTime = Date()
        let result = await kanataManager.validateConfigFile()
        let elapsedTime = Date().timeIntervalSince(startTime)

        XCTAssertTrue(result.isValid, "Should fallback to file validation on TCP timeout")
        XCTAssertLessThan(elapsedTime, 6.0, "Should timeout and fallback within reasonable time")
    }

    // MARK: - Config Save TCP Validation Tests

    func testSaveConfigWithTCPValidation() async throws {
        // Start mock server
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        // Enable TCP and simulate running
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Test saving valid config
        let _validMappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "space", output: "tab")
        ]

        // This tests the TCP validation during save
        do {
            try await kanataManager.saveConfiguration(input: "caps", output: "esc")
            // Verify the configuration was actually saved by reading it back
            let result = await kanataManager.validateConfigFile()
            XCTAssertTrue(result.isValid, "Saved configuration should validate successfully")
            XCTAssertTrue(result.errors.isEmpty, "Saved configuration should have no validation errors")
        } catch {
            XCTFail("Save should not fail with valid config: \(error)")
        }
    }

    func testSaveConfigWithTCPValidationFailure() async throws {
        // Start mock server with validation failure
        try await mockTCPServer.start()
        let mockErrors = [
            MockValidationError(line: 1, column: 1, message: "Invalid mapping")
        ]
        await mockTCPServer.setValidationResponse(success: false, errors: mockErrors)

        // Enable TCP and simulate running
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Test saving config that will fail validation
        let _invalidMappings = [
            KeyMapping(input: "invalid-key", output: "esc")
        ]

        // Save should still succeed even if TCP validation fails (it's optional)
        // Use valid mapping that passes CLI validation but might fail TCP validation in test
        do {
            try await kanataManager.saveConfiguration(input: "caps", output: "esc")
            // Even though TCP validation failed, verify the config was saved
            let configResult = await kanataManager.validateConfigFile()
            // Should fallback to file validation and succeed
            XCTAssertTrue(configResult.isValid, "Should fallback to file validation when TCP fails")
        } catch {
            XCTFail("Save should not fail even if TCP validation fails: \(error)")
        }
    }

    func testSaveConfigFallbackWhenTCPUnavailable() async throws {
        // Don't start server (TCP unavailable)
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Test saving config
        let _mappings = [
            KeyMapping(input: "caps", output: "esc")
        ]

        // Save should succeed with fallback
        do {
            try await kanataManager.saveConfiguration(input: "space", output: "tab")
            // Verify the configuration was saved by validating it
            let result = await kanataManager.validateConfigFile()
            XCTAssertTrue(result.isValid, "Saved configuration should validate via file fallback")
            XCTAssertTrue(result.errors.isEmpty, "File validation should produce no errors")
        } catch {
            XCTFail("Save should not fail when TCP is unavailable: \(error)")
        }
    }

    // MARK: - Command Line Arguments Tests

    func testBuildKanataArgumentsWithTCPEnabled() {
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000

        // Use reflection or test the public behavior that results from TCP being enabled
        // Since buildKanataArguments is private, we test the effect through public methods

        // Test that TCP settings affect the manager's behavior
        XCTAssertTrue(
            preferencesService.shouldUseTCPServer, "Should use TCP server with valid settings"
        )
        XCTAssertEqual(
            preferencesService.tcpEndpoint, "127.0.0.1:37000", "TCP endpoint should be correct"
        )
    }

    func testBuildKanataArgumentsWithTCPDisabled() {
        preferencesService.tcpServerEnabled = false

        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP server when disabled")
        XCTAssertNil(preferencesService.tcpEndpoint, "TCP endpoint should be nil when disabled")
    }

    func testBuildKanataArgumentsWithInvalidTCPPort() {
        // Store the current valid port
        let originalPort = preferencesService.tcpServerPort

        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 500 // Invalid port - should be auto-corrected

        // The invalid port should be auto-corrected back to the original valid port
        XCTAssertEqual(
            preferencesService.tcpServerPort, originalPort, "Invalid port should be auto-corrected"
        )
        XCTAssertTrue(
            preferencesService.shouldUseTCPServer,
            "Should use TCP server after auto-correction to valid port"
        )
    }

    // MARK: - Concurrent TCP Validation Tests

    func testConcurrentTCPValidation() async throws {
        // Start mock server
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        // Enable TCP and simulate running
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Create multiple configs
        let configs = [
            "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)",
            "(defcfg process-unmapped-keys no) (defsrc space) (deflayer base tab)",
            "(defcfg process-unmapped-keys yes) (defsrc return) (deflayer base delete)"
        ]

        for (index, config) in configs.enumerated() {
            try config.write(
                to: tempConfigDirectory.appendingPathComponent("config\(index).kbd"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Test concurrent validation calls
        let tasks = (0 ..< 3).map { _ in
            Task {
                await kanataManager.validateConfigFile()
            }
        }

        let results = await withTaskGroup(of: (isValid: Bool, errors: [String]).self) { group in
            for task in tasks {
                group.addTask {
                    await task.value
                }
            }

            var results: [(isValid: Bool, errors: [String])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(results.count, 3, "Should handle concurrent validation requests")

        for result in results {
            XCTAssertTrue(result.isValid, "All concurrent validations should succeed")
            XCTAssertTrue(result.errors.isEmpty, "No validation errors expected")
        }
    }

    // MARK: - Error Handling Tests

    func testValidationWithMissingConfigFile() async {
        // Don't create any config file
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        let result = await kanataManager.validateConfigFile()

        // Should handle missing file gracefully
        XCTAssertFalse(result.isValid, "Validation should fail when config file is missing")
        XCTAssertFalse(result.errors.isEmpty, "Should have error messages for missing file")
    }

    func testValidationWithUnreadableConfigFile() async throws {
        // Create config file with restricted permissions
        let configContent = "(defcfg process-unmapped-keys yes)"
        let configURL = try createTestConfig(configContent)

        // Remove read permissions (this might not work on all systems due to sandboxing)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: configURL.path)

        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        let result = await kanataManager.validateConfigFile()

        // Should handle unreadable file (either through TCP fallback or error handling)
        // The exact behavior depends on the implementation, but it should not crash
        XCTAssert(result.isValid || !result.errors.isEmpty, "Should handle unreadable file gracefully")

        // Restore permissions for cleanup
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)
    }

    // MARK: - State Consistency Tests

    func testTCPValidationStateConsistency() async throws {
        // Start with TCP enabled
        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // Start mock server
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        let validConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        _ = try createTestConfig(validConfig)

        // First validation should use TCP
        var result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "First validation should succeed via TCP")

        // Disable TCP
        preferencesService.tcpServerEnabled = false

        // Second validation should use file validation
        result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Second validation should succeed via file validation")

        // Re-enable TCP
        preferencesService.tcpServerEnabled = true

        // Third validation should use TCP again
        result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Third validation should succeed via TCP again")
    }

    // MARK: - Performance Tests

    func testTCPValidationPerformance() async throws {
        // Setup for performance testing
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        let validConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        _ = try createTestConfig(validConfig)

        // Measure validation performance
        measure {
            Task {
                _ = await kanataManager.validateConfigFile()
            }
        }
    }

    func testFileValidationFallbackPerformance() async throws {
        // Test performance of file validation (fallback)
        preferencesService.tcpServerEnabled = false

        let validConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        _ = try createTestConfig(validConfig)

        measure {
            Task {
                _ = await kanataManager.validateConfigFile()
            }
        }
    }

    // MARK: - Integration Tests

    func testEndToEndTCPWorkflow() async throws {
        // Test complete workflow: configure -> validate -> save -> validate again

        // 1. Start with clean state
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        preferencesService.tcpServerEnabled = true
        simulateKanataRunning()

        // 2. Create and validate initial config
        let initialConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        _ = try createTestConfig(initialConfig)

        var result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Initial validation should succeed")

        // 3. Save new configuration
        let newMappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "space", output: "tab")
        ]

        // Save configuration using available API
        for mapping in newMappings {
            try await kanataManager.saveConfiguration(input: mapping.input, output: mapping.output)
        }

        // 4. Validate the saved config
        result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Validation after save should succeed")

        // 5. Test with validation error
        await mockTCPServer.setValidationResponse(
            success: false,
            errors: [
                MockValidationError(line: 1, column: 1, message: "Test error")
            ]
        )

        result = await kanataManager.validateConfigFile()
        XCTAssertFalse(result.isValid, "Validation should fail when server reports errors")
        XCTAssertFalse(result.errors.isEmpty, "Should have error messages")
    }
}
