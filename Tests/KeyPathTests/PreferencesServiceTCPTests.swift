import XCTest
import Foundation
@testable import KeyPath

/// Comprehensive tests for PreferencesService TCP functionality
/// Tests real UserDefaults persistence, port validation, thread safety, and configuration management
@MainActor
final class PreferencesServiceTCPTests: XCTestCase {
    
    var preferencesService: PreferencesService!
    var testUserDefaults: UserDefaults!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create isolated UserDefaults for testing
        testUserDefaults = UserDefaults(suiteName: "com.keypath.tests.tcp.\(UUID().uuidString)")!
        
        // We need to access the shared instance but ensure clean state
        preferencesService = PreferencesService.shared
        
        // Clear any existing TCP settings
        clearTCPSettings()
    }
    
    override func tearDown() async throws {
        clearTCPSettings()
        testUserDefaults.removeSuite(named: testUserDefaults.suiteName!)
        preferencesService = nil
        testUserDefaults = nil
        try await super.tearDown()
    }
    
    private func clearTCPSettings() {
        UserDefaults.standard.removeObject(forKey: "KeyPath.TCP.ServerEnabled")
        UserDefaults.standard.removeObject(forKey: "KeyPath.TCP.ServerPort")
        UserDefaults.standard.synchronize()
    }
    
    // MARK: - Default Configuration Tests
    
    func testDefaultTCPConfiguration() {
        // Test that defaults are properly set
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP server should be enabled by default")
        XCTAssertEqual(preferencesService.tcpServerPort, 37000, "Default TCP port should be 37000")
        
        // Verify the convenience properties work correctly
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP server with valid defaults")
        XCTAssertEqual(preferencesService.tcpEndpoint, "127.0.0.1:37000", "TCP endpoint should be formatted correctly")
    }
    
    // MARK: - UserDefaults Persistence Tests
    
    func testTCPSettingsPersistence() {
        // Test enabling/disabling TCP server
        preferencesService.tcpServerEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled"), "TCP enabled setting should persist to UserDefaults")
        
        preferencesService.tcpServerEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled"), "TCP enabled setting should persist to UserDefaults")
        
        // Test port changes
        preferencesService.tcpServerPort = 8080
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), 8080, "TCP port should persist to UserDefaults")
        
        preferencesService.tcpServerPort = 65535
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), 65535, "Maximum valid port should persist to UserDefaults")
    }
    
    func testTCPSettingsRestoration() {
        // Manually set UserDefaults values
        UserDefaults.standard.set(false, forKey: "KeyPath.TCP.ServerEnabled")
        UserDefaults.standard.set(9999, forKey: "KeyPath.TCP.ServerPort")
        UserDefaults.standard.synchronize()
        
        // Create new instance to test restoration
        let newPreferencesService = PreferencesService()
        
        XCTAssertFalse(newPreferencesService.tcpServerEnabled, "TCP enabled setting should be restored from UserDefaults")
        XCTAssertEqual(newPreferencesService.tcpServerPort, 9999, "TCP port setting should be restored from UserDefaults")
    }
    
    // MARK: - Port Validation Tests
    
    func testPortValidation() {
        // Test valid ports
        XCTAssertTrue(preferencesService.isValidTCPPort(1024), "Port 1024 should be valid (minimum)")
        XCTAssertTrue(preferencesService.isValidTCPPort(37000), "Port 37000 should be valid (default)")
        XCTAssertTrue(preferencesService.isValidTCPPort(65535), "Port 65535 should be valid (maximum)")
        XCTAssertTrue(preferencesService.isValidTCPPort(8080), "Port 8080 should be valid (common)")
        
        // Test invalid ports
        XCTAssertFalse(preferencesService.isValidTCPPort(0), "Port 0 should be invalid")
        XCTAssertFalse(preferencesService.isValidTCPPort(1023), "Port 1023 should be invalid (below minimum)")
        XCTAssertFalse(preferencesService.isValidTCPPort(65536), "Port 65536 should be invalid (above maximum)")
        XCTAssertFalse(preferencesService.isValidTCPPort(-1), "Negative port should be invalid")
        XCTAssertFalse(preferencesService.isValidTCPPort(999999), "Very large port should be invalid")
    }
    
    func testShouldUseTCPServerLogic() {
        // Test enabled with valid port
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 8080
        XCTAssertTrue(preferencesService.shouldUseTCPServer, "Should use TCP server when enabled with valid port")
        
        // Test disabled with valid port
        preferencesService.tcpServerEnabled = false
        preferencesService.tcpServerPort = 8080
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP server when disabled even with valid port")
        
        // Test enabled with invalid port
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 500  // Invalid port
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP server when enabled with invalid port")
        
        // Test disabled with invalid port
        preferencesService.tcpServerEnabled = false
        preferencesService.tcpServerPort = 500  // Invalid port
        XCTAssertFalse(preferencesService.shouldUseTCPServer, "Should not use TCP server when disabled with invalid port")
    }
    
    // MARK: - TCP Endpoint Tests
    
    func testTCPEndpointGeneration() {
        // Test enabled state
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 9000
        XCTAssertEqual(preferencesService.tcpEndpoint, "127.0.0.1:9000", "TCP endpoint should be formatted correctly when enabled")
        
        // Test different ports
        preferencesService.tcpServerPort = 37000
        XCTAssertEqual(preferencesService.tcpEndpoint, "127.0.0.1:37000", "TCP endpoint should reflect port changes")
        
        // Test disabled state
        preferencesService.tcpServerEnabled = false
        XCTAssertNil(preferencesService.tcpEndpoint, "TCP endpoint should be nil when disabled")
    }
    
    // MARK: - Configuration Description Tests
    
    func testTCPConfigDescription() {
        // Test enabled state
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 8080
        let enabledDescription = preferencesService.tcpConfigDescription
        XCTAssertTrue(enabledDescription.contains("enabled"), "Description should indicate TCP is enabled")
        XCTAssertTrue(enabledDescription.contains("8080"), "Description should include port number")
        
        // Test disabled state
        preferencesService.tcpServerEnabled = false
        let disabledDescription = preferencesService.tcpConfigDescription
        XCTAssertTrue(disabledDescription.contains("disabled"), "Description should indicate TCP is disabled")
    }
    
    // MARK: - Reset Functionality Tests
    
    func testResetTCPSettings() {
        // Change settings from defaults
        preferencesService.tcpServerEnabled = false
        preferencesService.tcpServerPort = 9999
        
        // Verify changes
        XCTAssertFalse(preferencesService.tcpServerEnabled)
        XCTAssertEqual(preferencesService.tcpServerPort, 9999)
        
        // Reset to defaults
        preferencesService.resetTCPSettings()
        
        // Verify reset
        XCTAssertTrue(preferencesService.tcpServerEnabled, "TCP server should be enabled after reset")
        XCTAssertEqual(preferencesService.tcpServerPort, 37000, "TCP port should be default after reset")
        
        // Verify persistence of reset values
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled"), "Reset TCP enabled should persist")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), 37000, "Reset TCP port should persist")
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentTCPConfigurationAccess() async {
        let expectation = XCTestExpectation(description: "Concurrent access completes")
        expectation.expectedFulfillmentCount = 10
        
        // Launch multiple concurrent tasks to modify TCP settings
        for i in 0..<10 {
            Task {
                await MainActor.run {
                    let port = 30000 + i
                    preferencesService.tcpServerPort = port
                    preferencesService.tcpServerEnabled = i % 2 == 0
                    
                    // Verify settings are consistent
                    XCTAssertEqual(preferencesService.tcpServerPort, port, "Port should be set correctly in concurrent access")
                    XCTAssertEqual(preferencesService.tcpServerEnabled, i % 2 == 0, "Enabled state should be set correctly in concurrent access")
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testConcurrentPortValidation() async {
        let expectation = XCTestExpectation(description: "Concurrent validation completes")
        expectation.expectedFulfillmentCount = 100
        
        // Test concurrent port validation calls
        for i in 0..<100 {
            Task {
                let port = 1024 + i
                let isValid = preferencesService.isValidTCPPort(port)
                
                if port <= 65535 {
                    XCTAssertTrue(isValid, "Port \(port) should be valid")
                } else {
                    XCTAssertFalse(isValid, "Port \(port) should be invalid")
                }
                
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Edge Case Tests
    
    func testEdgeCasePortValues() {
        // Test boundary values
        XCTAssertFalse(preferencesService.isValidTCPPort(1023), "Port 1023 should be invalid (just below minimum)")
        XCTAssertTrue(preferencesService.isValidTCPPort(1024), "Port 1024 should be valid (minimum)")
        XCTAssertTrue(preferencesService.isValidTCPPort(65535), "Port 65535 should be valid (maximum)")
        XCTAssertFalse(preferencesService.isValidTCPPort(65536), "Port 65536 should be invalid (just above maximum)")
        
        // Test common ports
        XCTAssertTrue(preferencesService.isValidTCPPort(8080), "Port 8080 should be valid")
        XCTAssertTrue(preferencesService.isValidTCPPort(3000), "Port 3000 should be valid")
        XCTAssertTrue(preferencesService.isValidTCPPort(37000), "Port 37000 (default) should be valid")
    }
    
    func testUserDefaultsKeyConsistency() {
        // Verify the keys used internally match what's expected
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 12345
        
        // Check that the exact keys are used
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled"), "TCP enabled key should match")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort"), 12345, "TCP port key should match")
    }
    
    // MARK: - Performance Tests
    
    func testTCPConfigurationPerformance() {
        measure {
            for i in 0..<1000 {
                preferencesService.tcpServerPort = 30000 + (i % 1000)
                preferencesService.tcpServerEnabled = i % 2 == 0
                _ = preferencesService.shouldUseTCPServer
                _ = preferencesService.tcpEndpoint
                _ = preferencesService.tcpConfigDescription
            }
        }
    }
    
    func testPortValidationPerformance() {
        measure {
            for i in 0..<10000 {
                _ = preferencesService.isValidTCPPort(1024 + (i % 64512))
            }
        }
    }
    
    // MARK: - Real UserDefaults Integration Tests
    
    func testUserDefaultsSynchronizationBehavior() {
        // Test immediate synchronization
        preferencesService.tcpServerEnabled = false
        UserDefaults.standard.synchronize()
        
        // Verify immediate persistence
        let storedValue = UserDefaults.standard.bool(forKey: "KeyPath.TCP.ServerEnabled")
        XCTAssertFalse(storedValue, "Value should be immediately available in UserDefaults")
        
        // Test with different port
        preferencesService.tcpServerPort = 55555
        UserDefaults.standard.synchronize()
        
        let storedPort = UserDefaults.standard.integer(forKey: "KeyPath.TCP.ServerPort")
        XCTAssertEqual(storedPort, 55555, "Port should be immediately available in UserDefaults")
    }
}