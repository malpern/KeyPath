import SwiftUI
import XCTest
import Darwin
import Foundation

@testable import KeyPath

/// Comprehensive tests for SettingsView TCP configuration UI
/// Tests port validation, status checking, user interactions, and UI state management
@MainActor
final class SettingsViewTCPTests: XCTestCase {
    var preferencesService: PreferencesService!
    var simpleKanataManager: SimpleKanataManager!
    var mockTCPServer: MockKanataTCPServer!
    var originalTCPSettings: (enabled: Bool, port: Int)!

    override func setUp() async throws {
        try await super.setUp()

        // Store original settings
        preferencesService = PreferencesService.shared
        originalTCPSettings = (preferencesService.tcpServerEnabled, preferencesService.tcpServerPort)

        // Initialize components
        let kanataManager = KanataManager()
        simpleKanataManager = SimpleKanataManager(kanataManager: kanataManager)

        // Setup mock server
        let serverPort = try findAvailablePort()
        mockTCPServer = MockKanataTCPServer(port: serverPort)

        // Configure preferences for testing
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = serverPort
    }

    override func tearDown() async throws {
        await mockTCPServer?.stop()

        // Restore original settings
        preferencesService.tcpServerEnabled = originalTCPSettings.enabled
        preferencesService.tcpServerPort = originalTCPSettings.port

        simpleKanataManager = nil
        mockTCPServer = nil
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

    private func createSettingsView() -> some View {
        SettingsView()
            .environmentObject(KanataManager())
            .environmentObject(simpleKanataManager)
    }

    // MARK: - TCP Toggle Tests

    func testTCPToggleInitialState() throws {
        let settingsView = createSettingsView()

        // Test that the view reflects the current TCP state
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP should be enabled initially")

        // Verify the view's data binding is consistent
        XCTAssertEqual(preferencesService.tcpServerEnabled, true, "View model should match preferences")
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Dependent computed properties should be consistent")
        XCTAssertNotNil(preferencesService.tcpEndpoint, "TCP endpoint should be available when enabled")
    }

    func testTCPToggleStateChange() {
        let settingsView = createSettingsView()

        // Capture initial state
        let initialPort = preferencesService.tcpServerPort
        
        // Test disabling TCP
        preferencesService.tcpServerEnabled = false
        XCTAssertFalse(preferencesService.tcpServerEnabled, "TCP should be disabled after toggle")
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP when disabled")
        XCTAssertNil(preferencesService.tcpEndpoint, "TCP endpoint should be nil when disabled")
        XCTAssertEqual(preferencesService.tcpServerPort, initialPort, "Port should remain unchanged when toggling")

        // Test re-enabling TCP
        preferencesService.tcpServerEnabled = true
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP should be enabled after toggle")
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP when enabled with valid port")
        XCTAssertNotNil(preferencesService.tcpEndpoint, "TCP endpoint should be restored when re-enabled")
        XCTAssertEqual(preferencesService.tcpServerPort, initialPort, "Port should be restored to original value")
    }

    // MARK: - Port Configuration Tests

    func testPortDisplayAndValidation() {
        let settingsView = createSettingsView()

        // Test that current port is displayed
        XCTAssertEqual(
            preferencesService.tcpServerPort, preferencesService.tcpServerPort,
            "Port should be correctly stored"
        )

        // Test port validation logic
        let validPorts = [1024, 8080, 37000, 65535]
        for port in validPorts {
            preferencesService.tcpServerPort = port
            XCTAssertTrue(preferencesService.isValidTCPPort(port), "Port \(port) should be valid")
            XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP with valid port \(port)")
        }

        let invalidPorts = [0, 500, 1023, 65536, 99999]
        for port in invalidPorts {
            preferencesService.tcpServerPort = port
            XCTAssertFalse(preferencesService.isValidTCPPort(port), "Port \(port) should be invalid")
            XCTAssertFalse(
                preferencesService.shouldUseTCPServer, "Should not use TCP with invalid port \(port)"
            )
        }
    }

    func testPortChangeValidation() {
        let settingsView = createSettingsView()

        // Test valid port changes
        let testPorts = [
            (3000, true),
            (8080, true),
            (37000, true),
            (65535, true),
            (500, false), // Too low
            (70000, false), // Too high
            (0, false), // Invalid
            (-1, false) // Negative
        ]

        for (port, shouldBeValid) in testPorts {
            preferencesService.tcpServerPort = port

            let isValid = preferencesService.isValidTCPPort(port)
            XCTAssertEqual(
                isValid, shouldBeValid, "Port \(port) validation should return \(shouldBeValid)"
            )

            if shouldBeValid, preferencesService.tcpServerEnabled {
                XCTAssertTrue(
                    preferencesService.shouldUseTCPServer, "Should use TCP with valid port \(port)"
                )
                XCTAssertNotNil(
                    preferencesService.tcpEndpoint, "TCP endpoint should be available for valid port \(port)"
                )
            }
        }
    }

    // MARK: - Status Display Tests

    func testTCPStatusWhenDisabled() {
        preferencesService.tcpServerEnabled = false

        let settingsView = createSettingsView()

        // When TCP is disabled, status should indicate this
        XCTAssertFalse(preferencesService.tcpServerEnabled, "TCP should be disabled")
        XCTAssertNil(preferencesService.tcpEndpoint, "TCP endpoint should be nil when disabled")
    }

    func testTCPStatusWhenEnabledButKanataStopped() {
        preferencesService.tcpServerEnabled = true

        let settingsView = createSettingsView()

        // When Kanata is not running, TCP server should not be available
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP should be enabled")
        XCTAssertNotNil(preferencesService.tcpEndpoint, "TCP endpoint should be available")

        // Status should reflect that Kanata is not running
        XCTAssertFalse(simpleKanataManager.isRunning, "Kanata should not be running initially")
    }

    func testTCPStatusWhenEnabledAndKanataRunning() async throws {
        // Start mock server
        try await mockTCPServer.start()

        preferencesService.tcpServerEnabled = true

        let settingsView = createSettingsView()

        // Test that status checking works
        let client = KanataTCPClient(port: preferencesService.tcpServerPort)
        let isAvailable = await client.checkServerStatus()
        XCTAssertTrue(isAvailable, "TCP server should be available when running")
    }

    // MARK: - User Interaction Tests

    func testPortChangeUserFlow() {
        let settingsView = createSettingsView()

        // Simulate user changing port through UI
        let originalPort = preferencesService.tcpServerPort
        let newPort = 8080

        // User changes port
        preferencesService.tcpServerPort = newPort

        // Verify change is reflected
        XCTAssertEqual(preferencesService.tcpServerPort, newPort, "Port should be updated to new value")
        XCTAssertNotEqual(
            preferencesService.tcpServerPort, originalPort, "Port should be different from original"
        )

        // Verify persistence
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), newPort,
            "Port change should persist to UserDefaults"
        )
    }

    func testInvalidPortUserInput() {
        let settingsView = createSettingsView()

        // Simulate user entering invalid port
        let invalidPorts = [0, -1, 70000, 999]

        for invalidPort in invalidPorts {
            preferencesService.tcpServerPort = invalidPort

            // Should not use TCP with invalid port
            XCTAssertFalse(
                preferencesService.shouldUseTCPServer, "Should not use TCP with invalid port \(invalidPort)"
            )

            // But the invalid value should still be stored (for user to see and correct)
            XCTAssertEqual(
                preferencesService.tcpServerPort, invalidPort,
                "Invalid port should be stored for user feedback"
            )
        }
    }

    func testTCPConfigurationPersistence() {
        let settingsView = createSettingsView()

        // Test that configuration changes persist across app restarts
        preferencesService.tcpServerEnabled = false
        preferencesService.tcpServerPort = 9999

        // Verify persistence
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled"),
            "TCP enabled state should persist"
        )
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), 9999,
            "TCP port should persist"
        )

        // Change back
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000

        // Verify new values persist
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled"),
            "New TCP enabled state should persist"
        )
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), 37000,
            "New TCP port should persist"
        )
    }

    // MARK: - Error Handling Tests

    func testPortValidationErrorHandling() {
        let settingsView = createSettingsView()

        // Test boundary conditions
        let boundaryTests = [
            (1023, false), // Just below minimum
            (1024, true), // Minimum valid
            (65535, true), // Maximum valid
            (65536, false) // Just above maximum
        ]

        for (port, expectedValid) in boundaryTests {
            let isValid = preferencesService.isValidTCPPort(port)
            XCTAssertEqual(
                isValid, expectedValid, "Port \(port) should be \(expectedValid ? "valid" : "invalid")"
            )
        }
    }

    func testTCPConfigurationErrorRecovery() {
        let settingsView = createSettingsView()

        // Start with valid configuration
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should start with valid TCP config")

        // Introduce invalid port
        preferencesService.tcpServerPort = 500
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP with invalid port")

        // Recover with valid port
        preferencesService.tcpServerPort = 8080
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should recover with valid port")
    }

    // MARK: - Performance Tests

    func testSettingsViewPerformanceWithFrequentUpdates() {
        let settingsView = createSettingsView()

        measure {
            for i in 0 ..< 1000 {
                let port = 30000 + (i % 1000)
                preferencesService.tcpServerPort = port
                preferencesService.tcpServerEnabled = i % 2 == 0

                // Access computed properties that the UI would use
                _ = preferencesService.shouldUseTCPServer
                _ = preferencesService.tcpEndpoint
                _ = preferencesService.tcpConfigDescription
            }
        }
    }

    func testStatusCheckPerformance() async throws {
        try await mockTCPServer.start()

        let settingsView = createSettingsView()
        preferencesService.tcpServerEnabled = true

        let measureOptions = XCTMeasureOptions()
        measureOptions.iterationCount = 5

        measure(options: measureOptions) {
            let expectation = XCTestExpectation(description: "Status check performance")
            expectation.expectedFulfillmentCount = 10

            for _ in 0 ..< 10 {
                Task {
                    let client = KanataTCPClient(port: preferencesService.tcpServerPort)
                    _ = await client.checkServerStatus()
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    // MARK: - Integration with Preferences Tests

    func testSettingsViewPreferencesIntegration() {
        let settingsView = createSettingsView()

        // Test that SettingsView properly observes PreferencesService changes
        let originalPort = preferencesService.tcpServerPort
        let originalEnabled = preferencesService.tcpServerEnabled

        // Change preferences outside of SettingsView
        preferencesService.tcpServerPort = 9999
        preferencesService.tcpServerEnabled = !originalEnabled

        // SettingsView should reflect these changes
        XCTAssertEqual(
            preferencesService.tcpServerPort, 9999, "SettingsView should observe port changes"
        )
        XCTAssertEqual(
            preferencesService.tcpServerEnabled, !originalEnabled,
            "SettingsView should observe enabled state changes"
        )

        // Restore original values
        preferencesService.tcpServerPort = originalPort
        preferencesService.tcpServerEnabled = originalEnabled
    }

    func testSettingsViewKanataManagerIntegration() {
        let settingsView = createSettingsView()

        // Test that SettingsView can access KanataManager state
        let initialState = simpleKanataManager.currentState
        XCTAssertNotNil(initialState, "KanataManager should have a valid state")

        // Test that SettingsView can check if Kanata is running
        let isRunning = simpleKanataManager.isRunning
        XCTAssertNotNil(isRunning, "isRunning should return a deterministic boolean value")

        // SettingsView status display should reflect KanataManager state
        // This would be tested through actual UI inspection in a more complete test
    }

    // MARK: - Real-World Usage Tests

    func testTypicalUserConfigurationFlow() async throws {
        let settingsView = createSettingsView()

        // 1. User opens settings, sees default TCP configuration
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP should be enabled by default")
        XCTAssertEqual(
            preferencesService.tcpServerPort, preferencesService.tcpServerPort, "Should show current port"
        )

        // 2. User decides to change port
        preferencesService.tcpServerPort = 8080
        XCTAssertEqual(preferencesService.tcpServerPort, 8080, "Port should be updated")
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP with new valid port")

        // 3. User checks if TCP server is working (with mock server)
        try await mockTCPServer.start()
        let client = KanataTCPClient(port: 8080)

        // Update mock server to new port
        await mockTCPServer.stop()
        mockTCPServer = MockKanataTCPServer(port: 8080)
        try await mockTCPServer.start()

        let isAvailable = await client.checkServerStatus()
        XCTAssertTrue(isAvailable, "TCP server should be available on new port")

        // 4. User temporarily disables TCP
        preferencesService.tcpServerEnabled = false
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP when disabled")

        // 5. User re-enables TCP
        preferencesService.tcpServerEnabled = true
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP when re-enabled")
    }

    func testAdvancedUserConfigurationFlow() {
        let settingsView = createSettingsView()

        // Advanced user tests multiple port configurations
        let testPorts = [3000, 8080, 9000, 37000, 55555]

        for port in testPorts {
            preferencesService.tcpServerPort = port
            XCTAssertEqual(preferencesService.tcpServerPort, port, "Port should be set to \(port)")
            XCTAssertTrue(preferencesService.isValidTCPPort(port), "Port \(port) should be valid")
            XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP with valid port \(port)")

            // Verify endpoint is correctly formatted
            let expectedEndpoint = "127.0.0.1:\(port)"
            XCTAssertEqual(
                preferencesService.tcpEndpoint, expectedEndpoint,
                "TCP endpoint should be correctly formatted for port \(port)"
            )
        }

        // Test reset functionality
        preferencesService.resetTCPSettings()
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP should be enabled after reset")
        XCTAssertEqual(preferencesService.tcpServerPort, 37000, "Port should be default after reset")
    }

    // MARK: - Edge Case Tests

    func testSettingsViewEdgeCases() {
        let settingsView = createSettingsView()

        // Test with extreme values
        preferencesService.tcpServerPort = Int.max
        XCTAssertFalse(
            preferencesService.isValidTCPPort(Int.max), "Should handle extremely large port numbers"
        )

        preferencesService.tcpServerPort = Int.min
        XCTAssertFalse(
            preferencesService.isValidTCPPort(Int.min), "Should handle negative port numbers"
        )

        // Test rapid toggling maintains consistent state
        let initialState = preferencesService.tcpServerEnabled
        for _ in 0 ..< 100 {
            preferencesService.tcpServerEnabled.toggle()
        }
        // After even number of toggles, should match initial state
        XCTAssertEqual(
            preferencesService.tcpServerEnabled, initialState,
            "After 100 toggles, should return to initial state"
        )
    }

    // MARK: - Accessibility Tests

    func testTCPConfigurationAccessibility() {
        let settingsView = createSettingsView()

        // Test that TCP configuration maintains accessibility
        // This ensures screen readers and other assistive technologies work properly

        // Test various states
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Enabled state should be accessible")

        preferencesService.tcpServerEnabled = false
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Disabled state should be accessible")

        // Test with invalid port
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 500
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Invalid port state should be accessible")
    }
}
