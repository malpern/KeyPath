import XCTest
@testable import KeyPath

/// LaunchDaemon autonomous testing framework
/// Tests LaunchDaemon configuration, validation, and lifecycle
final class LaunchDaemonTests: XCTestCase {
    
    private var mockEnvironment: MockSystemEnvironment!
    
    override func setUp() async throws {
        mockEnvironment = MockSystemEnvironment()
    }
    
    override func tearDown() async throws {
        mockEnvironment = nil
    }
    
    // MARK: - LaunchDaemon Plist Tests
    
    func testLaunchDaemonPlistGeneration() throws {
        // GIVEN: Mock environment with LaunchDaemon
        mockEnvironment.setupCompleteInstallation()
        
        // WHEN: Getting plist content
        let plistContent = mockEnvironment.fileContent(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist")
        
        // THEN: Should contain correct configuration
        XCTAssertNotNil(plistContent, "Plist should exist")
        XCTAssertTrue(plistContent?.contains("com.keypath.kanata") ?? false, "Should have correct label")
        XCTAssertTrue(plistContent?.contains("kanata-cmd") ?? false, "Should reference Kanata binary")
        XCTAssertTrue(plistContent?.contains("<string>root</string>") ?? false, "Should run as root")
        XCTAssertTrue(plistContent?.contains("ProcessType") ?? false, "Should have process type")
        XCTAssertTrue(plistContent?.contains("Interactive") ?? false, "Should be interactive process")
    }
    
    func testLaunchDaemonConfiguration() throws {
        // Test required LaunchDaemon properties
        mockEnvironment.setupCompleteInstallation()
        
        let plistContent = mockEnvironment.fileContent(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist") ?? ""
        
        // Verify security configuration
        XCTAssertTrue(plistContent.contains("UserName"), "Should specify user")
        XCTAssertTrue(plistContent.contains("GroupName"), "Should specify group")
        XCTAssertTrue(plistContent.contains("wheel"), "Should use wheel group")
        
        // Verify program arguments
        XCTAssertTrue(plistContent.contains("ProgramArguments"), "Should have program arguments")
        XCTAssertTrue(plistContent.contains("--cfg"), "Should specify config file")
        
        // Verify process configuration
        XCTAssertTrue(plistContent.contains("ProcessType"), "Should specify process type")
        XCTAssertTrue(plistContent.contains("Interactive"), "Should be interactive for keyboard access")
    }
    
    // MARK: - LaunchDaemon Lifecycle Tests
    
    func testLaunchDaemonStartup() async throws {
        // GIVEN: Complete installation
        mockEnvironment.setupCompleteInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        
        // WHEN: Starting service
        await manager.startKanata()
        
        // THEN: Should be running
        XCTAssertTrue(manager.isRunning, "Service should start")
        XCTAssertNil(manager.lastError, "Should have no errors")
        
        // THEN: Process should be running as root
        let processUser = mockEnvironment.getProcessUser(command: "kanata")
        XCTAssertEqual(processUser, "root", "Should run as root user")
    }
    
    func testLaunchDaemonShutdown() async throws {
        // GIVEN: Running service
        mockEnvironment.setupCompleteInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        await manager.startKanata()
        XCTAssertTrue(manager.isRunning)
        
        // WHEN: Stopping service
        await manager.stopKanata()
        
        // THEN: Should be stopped
        XCTAssertFalse(manager.isRunning, "Service should stop")
        XCTAssertNil(manager.lastError, "Should have no errors")
    }
    
    func testLaunchDaemonRestart() async throws {
        // GIVEN: Running service
        mockEnvironment.setupCompleteInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        await manager.startKanata()
        XCTAssertTrue(manager.isRunning)
        
        // WHEN: Restarting service
        await manager.restartKanata()
        
        // THEN: Should still be running
        XCTAssertTrue(manager.isRunning, "Service should restart")
        XCTAssertNil(manager.lastError, "Should have no errors after restart")
    }
    
    // MARK: - Error Handling Tests
    
    func testLaunchDaemonMissingBinary() async throws {
        // GIVEN: LaunchDaemon without binary
        mockEnvironment.reset()
        mockEnvironment.addMockFile(
            path: "/Library/LaunchDaemons/com.keypath.kanata.plist",
            content: mockEnvironment.fileContent(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist") ?? "",
            permissions: "644",
            owner: "root"
        )
        // Binary is missing
        
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        
        // WHEN: Attempting to start
        await manager.startKanata()
        
        // THEN: Should fail gracefully
        XCTAssertFalse(manager.isRunning, "Should not be running without binary")
        XCTAssertNotNil(manager.lastError, "Should have error message")
    }
    
    func testLaunchDaemonPermissionIssues() throws {
        // GIVEN: LaunchDaemon with wrong permissions
        mockEnvironment.reset()
        mockEnvironment.addMockFile(
            path: "/Library/LaunchDaemons/com.keypath.kanata.plist",
            content: "mock-plist",
            permissions: "777", // Wrong permissions
            owner: "user" // Wrong owner
        )
        
        // THEN: Should be detectable
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        XCTAssertTrue(manager.isServiceInstalled(), "Should detect plist exists")
        
        // Note: In real system, wrong permissions would cause launchctl to fail
        // This is tested in the mock launchctl results
    }
    
    // MARK: - Integration Tests
    
    func testLaunchDaemonInstallationIntegration() async throws {
        // Test complete LaunchDaemon installation and startup
        
        // GIVEN: Clean system
        mockEnvironment.setupCleanInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        
        // WHEN: Installing
        let installSuccess = await manager.performTransparentInstallation()
        XCTAssertTrue(installSuccess, "Installation should succeed")
        
        // THEN: LaunchDaemon should be properly configured
        XCTAssertTrue(manager.isServiceInstalled(), "LaunchDaemon should be installed")
        
        // WHEN: Starting service
        await manager.startKanata()
        
        // THEN: Should run with correct privileges
        XCTAssertTrue(manager.isRunning, "Service should start")
        let processUser = mockEnvironment.getProcessUser(command: "kanata")
        XCTAssertEqual(processUser, "root", "Should run as root")
    }
    
    // MARK: - Validation Tests
    
    func testLaunchDaemonValidation() throws {
        // Test LaunchDaemon plist validation
        mockEnvironment.setupCompleteInstallation()
        
        let plistContent = mockEnvironment.fileContent(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist") ?? ""
        
        // Validate XML structure
        XCTAssertTrue(plistContent.contains("<?xml"), "Should be valid XML")
        XCTAssertTrue(plistContent.contains("<!DOCTYPE plist"), "Should be valid plist")
        XCTAssertTrue(plistContent.contains("<plist version=\"1.0\">"), "Should have correct plist version")
        
        // Validate required keys
        let requiredKeys = [
            "Label",
            "ProgramArguments", 
            "UserName",
            "GroupName",
            "ProcessType"
        ]
        
        for key in requiredKeys {
            XCTAssertTrue(plistContent.contains("<key>\(key)</key>"), "Should contain \(key)")
        }
        
        // Validate security settings
        XCTAssertTrue(plistContent.contains("<string>root</string>"), "Should specify root user")
        XCTAssertTrue(plistContent.contains("<string>wheel</string>"), "Should specify wheel group")
        XCTAssertTrue(plistContent.contains("<string>Interactive</string>"), "Should be interactive process")
    }
    
    func testLaunchDaemonSecurityConfiguration() throws {
        // Test security-specific LaunchDaemon configuration
        mockEnvironment.setupCompleteInstallation()
        
        let plistContent = mockEnvironment.fileContent(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist") ?? ""
        
        // Security validation
        XCTAssertTrue(plistContent.contains("UserName"), "Must specify user for security")
        XCTAssertTrue(plistContent.contains("root"), "Must run as root for keyboard access")
        XCTAssertTrue(plistContent.contains("GroupName"), "Must specify group for security")
        XCTAssertTrue(plistContent.contains("wheel"), "Should use wheel group")
        
        // Process type validation
        XCTAssertTrue(plistContent.contains("ProcessType"), "Must specify process type")
        XCTAssertTrue(plistContent.contains("Interactive"), "Must be interactive for UI access")
        
        // Path validation
        XCTAssertTrue(plistContent.contains("/usr/local/bin/kanata-cmd"), "Should use absolute path")
        XCTAssertTrue(plistContent.contains("/usr/local/etc/kanata"), "Should use absolute config path")
    }
    
    // MARK: - Performance Tests
    
    func testLaunchDaemonStartupPerformance() async throws {
        mockEnvironment.setupCompleteInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        await manager.startKanata()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertTrue(manager.isRunning, "Should start successfully")
        XCTAssertLessThan(timeElapsed, 3.0, "LaunchDaemon startup should be fast")
    }
}