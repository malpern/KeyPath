import Darwin
import Foundation
import Network
import XCTest

@testable import KeyPath

/// Comprehensive integration tests for TCP server implementation
/// Tests concurrent access, performance, real-world scenarios, and component interaction
@MainActor
final class TCPIntegrationTests: XCTestCase {
    var preferencesService: PreferencesService!
    var kanataManager: KanataManager!
    var launchDaemonInstaller: LaunchDaemonInstaller!
    var mockTCPServer: MockKanataTCPServer!
    var originalTCPSettings: (enabled: Bool, port: Int)!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Store original settings
        preferencesService = PreferencesService.shared
        originalTCPSettings = (preferencesService.tcpServerEnabled, preferencesService.tcpServerPort)

        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tcp-integration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Initialize components
        kanataManager = KanataManager()
        launchDaemonInstaller = LaunchDaemonInstaller()

        // Setup mock server
        let serverPort = try findAvailablePort()
        mockTCPServer = MockKanataTCPServer(port: serverPort)

        // Configure preferences
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = serverPort

        // Wait for initialization
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

    override func tearDown() async throws {
        await mockTCPServer?.stop()

        // Restore original settings
        preferencesService.tcpServerEnabled = originalTCPSettings.enabled
        preferencesService.tcpServerPort = originalTCPSettings.port

        // Clean up
        try? FileManager.default.removeItem(at: tempDirectory)

        kanataManager = nil
        launchDaemonInstaller = nil
        mockTCPServer = nil
        tempDirectory = nil
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

    private func createTestConfig(_ content: String) throws {
        let configURL = tempDirectory.appendingPathComponent("keypath.kbd")
        try content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - End-to-End Workflow Tests

    func testCompleteConfigurationWorkflow() async throws {
        // Test the complete workflow: preferences -> validation -> plist generation

        // 1. Start mock server
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        // 2. Configure preferences
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = preferencesService.tcpServerPort

        // 3. Verify preferences are correctly applied
        XCTAssertTrue(
            preferencesService.shouldUseTCPServer, "Preferences should indicate TCP should be used"
        )
        XCTAssertNotNil(preferencesService.tcpEndpoint, "TCP endpoint should be available")

        // 4. Test client can connect to server
        let client = KanataTCPClient(port: preferencesService.tcpServerPort)
        let serverAvailable = await client.checkServerStatus()
        XCTAssertTrue(serverAvailable, "Client should be able to connect to mock server")

        // 5. Test configuration validation
        let testConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps space)
        (deflayer base esc tab)
        """
        try createTestConfig(testConfig)

        // Simulate Kanata running for TCP validation
        kanataManager.isRunning = true

        let validationResult = await kanataManager.validateConfigFile()
        XCTAssertTrue(validationResult.isValid, "Configuration validation should succeed")

        // 6. Test plist generation includes TCP arguments
        let plistData = try generateMockPlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        let arguments = plist["ProgramArguments"] as! [String]

        XCTAssertTrue(arguments.contains("--tcp-port"), "LaunchDaemon plist should include TCP port")
        XCTAssertTrue(
            arguments.contains(String(preferencesService.tcpServerPort)),
            "Plist should contain correct port number"
        )
    }

    func testWorkflowWithTCPDisabled() async throws {
        // Test workflow when TCP is disabled

        // 1. Disable TCP
        preferencesService.tcpServerEnabled = false

        // 2. Verify preferences reflect disabled state
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP when disabled")
        XCTAssertNil(preferencesService.tcpEndpoint, "TCP endpoint should be nil when disabled")

        // 3. Test configuration validation falls back to file validation
        let testConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """
        try createTestConfig(testConfig)

        let validationResult = await kanataManager.validateConfigFile()
        XCTAssertTrue(validationResult.isValid, "File validation should succeed when TCP is disabled")

        // 4. Test plist generation excludes TCP arguments
        let plistData = try generateMockPlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        let arguments = plist["ProgramArguments"] as! [String]

        XCTAssertFalse(
            arguments.contains("--tcp-port"),
            "LaunchDaemon plist should not include TCP port when disabled"
        )
    }

    func testWorkflowWithInvalidPort() throws {
        // Test workflow with invalid TCP port

        // 1. Set invalid port
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 500 // Invalid port

        // 2. Verify preferences correctly identify invalid port
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP with invalid port")
        XCTAssertNil(preferencesService.tcpEndpoint, "TCP endpoint should be nil with invalid port")

        // 3. Test plist generation excludes TCP arguments for invalid port
        let plistData = try generateMockPlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        let arguments = plist["ProgramArguments"] as! [String]

        XCTAssertFalse(
            arguments.contains("--tcp-port"), "LaunchDaemon plist should not include invalid TCP port"
        )
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentTCPOperations() async throws {
        // Test multiple concurrent TCP operations

        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        let testConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        try createTestConfig(testConfig)

        kanataManager.isRunning = true

        // Create multiple concurrent tasks
        let taskCount = 10
        let tasks = (0 ..< taskCount).map { index in
            Task {
                // Test different operations concurrently
                switch index % 4 {
                case 0:
                    // Validation
                    return await kanataManager.validateConfigFile().isValid
                case 1:
                    // Status check
                    let client = KanataTCPClient(port: preferencesService.tcpServerPort)
                    return await client.checkServerStatus()
                case 2:
                    // Preferences access
                    return preferencesService.shouldUseTCPServer
                case 3:
                    // Config generation
                    return !preferencesService.tcpConfigDescription.isEmpty
                default:
                    return true
                }
            }
        }

        // Wait for all tasks to complete
        let results = await withTaskGroup(of: Bool.self) { group in
            for task in tasks {
                group.addTask {
                    await task.value
                }
            }

            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(results.count, taskCount, "All concurrent tasks should complete")

        for (index, result) in results.enumerated() {
            XCTAssertTrue(result, "Concurrent task \(index) should succeed")
        }
    }

    func testConcurrentPreferencesModification() async {
        // Test concurrent modification of TCP preferences

        let taskCount = 20
        let expectation = XCTestExpectation(description: "Concurrent preferences modification")
        expectation.expectedFulfillmentCount = taskCount

        // Launch concurrent preference modifications
        for i in 0 ..< taskCount {
            Task {
                await MainActor.run {
                    let port = 30000 + i
                    preferencesService.tcpServerPort = port
                    preferencesService.tcpServerEnabled = i % 2 == 0

                    // Verify consistency
                    if preferencesService.tcpServerEnabled, preferencesService.isValidTCPPort(port) {
                        XCTAssertTrue(
                            preferencesService.shouldUseTCPServer,
                            "Should use TCP with valid settings in task \(i)"
                        )
                    }
                }
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    // MARK: - Performance Tests

    func testTCPValidationPerformanceUnderLoad() async throws {
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        let testConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        try createTestConfig(testConfig)

        kanataManager.isRunning = true

        // Measure performance with multiple validations
        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 5

        measure(options: measureOptions) {
            let validationCount = 50
            let expectation = XCTestExpectation(description: "Performance test")
            expectation.expectedFulfillmentCount = validationCount

            for _ in 0 ..< validationCount {
                Task {
                    _ = await kanataManager.validateConfigFile()
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testPreferencesPerformanceUnderLoad() {
        // Test preferences service performance with high load

        measure {
            for i in 0 ..< 10000 {
                let port = 1024 + (i % 64512)
                _ = preferencesService.isValidTCPPort(port)
                _ = preferencesService.tcpConfigDescription

                if i % 100 == 0 {
                    preferencesService.tcpServerPort = port
                }
            }
        }
    }

    func testMemoryUsageUnderLoad() async throws {
        // Test memory usage with sustained TCP operations

        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        let testConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        try createTestConfig(testConfig)

        kanataManager.isRunning = true

        // Perform sustained operations
        for _ in 0 ..< 1000 {
            // Mix of different operations
            _ = await kanataManager.validateConfigFile()
            _ = preferencesService.shouldUseTCPServer
            _ = preferencesService.tcpEndpoint

            let client = KanataTCPClient(port: preferencesService.tcpServerPort)
            _ = await client.checkServerStatus()

            // Brief pause to allow cleanup
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }

        // Verify system is in good state after sustained load
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "TCP preferences should remain consistent after load")
        XCTAssertNotNil(preferencesService.tcpEndpoint, "TCP endpoint should still be available")

        // Verify TCP client is still functional
        let client = KanataTCPClient(port: preferencesService.tcpServerPort)
        let stillAvailable = await client.checkServerStatus()
        XCTAssertTrue(stillAvailable, "TCP server should still be responsive after sustained operations")
    }

    // MARK: - Error Recovery Tests

    func testTCPServerRecoveryWorkflow() async throws {
        // Test recovery when TCP server becomes unavailable and then available again

        let testConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        try createTestConfig(testConfig)

        kanataManager.isRunning = true

        // 1. Start with working TCP server
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        var result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Initial TCP validation should succeed")

        // 2. Stop server (simulate failure)
        await mockTCPServer.stop()

        result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Should fallback to file validation when TCP fails")

        // 3. Restart server (simulate recovery)
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Should recover and use TCP validation again")
    }

    func testInvalidConfigRecovery() async throws {
        // Test recovery from invalid configurations

        try await mockTCPServer.start()

        kanataManager.isRunning = true

        // 1. Start with invalid config
        await mockTCPServer.setValidationResponse(
            success: false,
            errors: [
                MockValidationError(line: 1, column: 1, message: "Invalid configuration")
            ]
        )

        let invalidConfig = "(defcfg invalid-option yes)"
        try createTestConfig(invalidConfig)

        var result = await kanataManager.validateConfigFile()
        XCTAssertFalse(result.isValid, "Invalid config should fail validation")

        // 2. Fix config
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        let validConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        try createTestConfig(validConfig)

        result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Valid config should pass validation after fix")
    }

    // MARK: - Real-World Scenario Tests

    func testTypicalUserWorkflow() async throws {
        // Simulate a typical user workflow

        // 1. User opens app, TCP is enabled by default
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP should be enabled by default")
        XCTAssertEqual(preferencesService.tcpServerPort, 37000, "Default TCP port should be 37000")

        // 2. User checks TCP server status (Kanata not running yet)
        let client = KanataTCPClient(port: preferencesService.tcpServerPort)
        var serverAvailable = await client.checkServerStatus()
        XCTAssertFalse(serverAvailable, "TCP server should not be available when Kanata is not running")

        // 3. User starts Kanata (simulated by starting mock server)
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])
        kanataManager.isRunning = true

        serverAvailable = await client.checkServerStatus()
        XCTAssertTrue(serverAvailable, "TCP server should be available when Kanata is running")

        // 4. User creates key mapping
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "space", output: "tab")
        ]

        // 5. Save configuration (includes TCP validation)
        do {
            for mapping in mappings {
                try await kanataManager.saveConfiguration(input: mapping.input, output: mapping.output)
            }
            // Verify all mappings were saved correctly
            let validationResult = await kanataManager.validateConfigFile()
            XCTAssertTrue(validationResult.isValid, "All saved mappings should create valid configuration")
            XCTAssertTrue(validationResult.errors.isEmpty, "Saved configuration should have no errors")
        } catch {
            XCTFail("Configuration save should not fail: \(error)")
        }

        // 6. Validate final configuration
        let result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Final configuration should be valid")
    }

    func testDeveloperAdvancedWorkflow() async throws {
        // Simulate advanced developer workflow with custom TCP settings

        // 1. Developer changes TCP port
        preferencesService.tcpServerPort = 8080

        // 2. Restart mock server on new port
        await mockTCPServer.stop()
        mockTCPServer = MockKanataTCPServer(port: 8080)
        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        // 3. Test connectivity on new port
        let client = KanataTCPClient(port: 8080)
        let serverAvailable = await client.checkServerStatus()
        XCTAssertTrue(serverAvailable, "Should connect to custom TCP port")

        // 4. Test complex configuration
        let complexConfig = """
        (defcfg
          process-unmapped-keys yes
          log-level debug
        )

        (defsrc
          caps a s d f g h j k l
        )

        (deflayer base
          esc  a s d f g h j k l
        )

        (deflayer nav
          _    left down up right _ _ _ _ _
        )
        """

        try complexConfig.write(
            to: tempDirectory.appendingPathComponent("keypath.kbd"),
            atomically: true,
            encoding: .utf8
        )

        kanataManager.isRunning = true
        let result = await kanataManager.validateConfigFile()
        XCTAssertTrue(result.isValid, "Complex configuration should validate successfully")

        // 5. Test disabling TCP temporarily
        preferencesService.tcpServerEnabled = false
        let fileResult = await kanataManager.validateConfigFile()
        XCTAssertTrue(fileResult.isValid, "Should fallback to file validation")

        // 6. Re-enable TCP
        preferencesService.tcpServerEnabled = true
        let tcpResult = await kanataManager.validateConfigFile()
        XCTAssertTrue(tcpResult.isValid, "Should return to TCP validation")
    }

    // MARK: - Stress Tests

    func testHighConcurrencyStress() async throws {
        // Stress test with high concurrency

        try await mockTCPServer.start()
        await mockTCPServer.setValidationResponse(success: true, errors: [])

        let testConfig = "(defcfg process-unmapped-keys yes) (defsrc caps) (deflayer base esc)"
        try createTestConfig(testConfig)

        kanataManager.isRunning = true

        // Launch many concurrent operations
        let taskCount = 100
        let expectation = XCTestExpectation(description: "High concurrency stress test")
        expectation.expectedFulfillmentCount = taskCount

        for i in 0 ..< taskCount {
            Task {
                let operationType = i % 5

                switch operationType {
                case 0:
                    _ = await kanataManager.validateConfigFile()
                case 1:
                    let client = KanataTCPClient(port: preferencesService.tcpServerPort)
                    _ = await client.checkServerStatus()
                case 2:
                    preferencesService.tcpServerPort = 30000 + (i % 1000)
                case 3:
                    _ = preferencesService.shouldUseTCPServer
                case 4:
                    _ = try? generateMockPlistData()
                default:
                    break
                }

                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 30.0)
    }

    // MARK: - Helper Methods

    private func generateMockPlistData() throws -> Data {
        var arguments = ["/opt/homebrew/bin/kanata"]

        if preferencesService.shouldUseTCPServer {
            arguments.append("--tcp-port")
            arguments.append(String(preferencesService.tcpServerPort))
        }

        arguments.append("--cfg")
        arguments.append("/Users/test/.config/keypath/keypath.kbd")

        let plist: [String: Any] = [
            "Label": "com.keypath.kanata",
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": true
        ]

        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
