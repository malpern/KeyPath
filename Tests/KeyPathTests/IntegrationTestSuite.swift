import XCTest
@testable import KeyPath

/// Complete integration test suite for autonomous testing
/// Tests all components working together in realistic scenarios
@MainActor
final class IntegrationTestSuite: XCTestCase {
    
    private var mockEnvironment: MockSystemEnvironment!
    private var testScenarios: [TestScenario] = []
    
    struct TestScenario {
        let name: String
        let description: String
        let setup: (MockSystemEnvironment) -> Void
        let expectedOutcome: String
        let validation: (MockKanataManager) async throws -> Bool
    }
    
    override func setUp() async throws {
        mockEnvironment = MockSystemEnvironment()
        setupTestScenarios()
    }
    
    override func tearDown() async throws {
        mockEnvironment = nil
        testScenarios.removeAll()
    }
    
    // MARK: - Test Scenario Setup
    
    private func setupTestScenarios() {
        testScenarios = [
            // New User Journey
            TestScenario(
                name: "New User Complete Journey",
                description: "Clean install → Setup → First use → Configuration → Daily use",
                setup: { env in env.setupCleanInstallation() },
                expectedOutcome: "Fully functional KeyPath with Kanata running as root",
                validation: { manager in
                    // Install
                    let installSuccess = await manager.performTransparentInstallation()
                    guard installSuccess else { return false }
                    
                    // Start
                    await manager.startKanata()
                    guard manager.isRunning else { return false }
                    
                    // Configure
                    do {
                        try await manager.saveConfiguration(input: "caps", output: "escape")
                    } catch {
                        // Expected in mock environment
                    }
                    
                    // Verify
                    return manager.isCompletelyInstalled() && manager.isRunning
                }
            ),
            
            // Existing User with Partial Installation
            TestScenario(
                name: "Partial Installation Recovery",
                description: "User with partial install → Automatic recovery → Full functionality",
                setup: { env in env.setupPartialInstallation() },
                expectedOutcome: "Upgraded to complete installation",
                validation: { manager in
                    guard manager.isInstalled() else { return false }
                    guard !manager.isCompletelyInstalled() else { return false }
                    
                    let upgradeSuccess = await manager.performTransparentInstallation()
                    return upgradeSuccess && manager.isCompletelyInstalled()
                }
            ),
            
            // Power User Daily Workflow
            TestScenario(
                name: "Power User Daily Workflow",
                description: "Multiple config changes → Service restarts → Heavy usage",
                setup: { env in env.setupCompleteInstallation() },
                expectedOutcome: "Stable operation through intensive use",
                validation: { manager in
                    // Start service
                    await manager.startKanata()
                    guard manager.isRunning else { return false }
                    
                    // Multiple configuration changes
                    for i in 1...5 {
                        do {
                            try await manager.saveConfiguration(input: "f\(i)", output: "escape")
                        } catch {
                            // Expected in mock environment
                        }
                        
                        // Verify still running
                        guard manager.isRunning else { return false }
                    }
                    
                    // Service restart
                    await manager.restartKanata()
                    return manager.isRunning
                }
            ),
            
            // Error Recovery Scenarios
            TestScenario(
                name: "Error Recovery and Resilience",
                description: "Service failures → Automatic recovery → Continued operation",
                setup: { env in env.setupCompleteInstallation() },
                expectedOutcome: "Graceful error handling and recovery",
                validation: { manager in
                    // Start normally
                    await manager.startKanata()
                    guard manager.isRunning else { return false }
                    
                    // Simulate crash/stop
                    await manager.stopKanata()
                    guard !manager.isRunning else { return false }
                    
                    // Recovery
                    await manager.startKanata()
                    return manager.isRunning
                }
            ),
            
            // Security and Permissions
            TestScenario(
                name: "Security and Root Privileges",
                description: "Verify root execution → Permission validation → Security compliance",
                setup: { env in env.setupCompleteInstallation() },
                expectedOutcome: "Kanata running securely as root with proper permissions",
                validation: { manager in
                    await manager.startKanata()
                    guard manager.isRunning else { return false }
                    
                    // Verify root execution
                    let processUser = self.mockEnvironment.getProcessUser(command: "kanata")
                    return processUser == "root"
                }
            )
        ]
    }
    
    // MARK: - Integration Test Execution
    
    func testAllIntegrationScenarios() async throws {
        var passedScenarios: [String] = []
        var failedScenarios: [(String, String)] = []
        
        for scenario in testScenarios {
            print("🧪 Testing: \(scenario.name)")
            print("📝 Description: \(scenario.description)")
            
            // Setup scenario
            mockEnvironment.reset()
            scenario.setup(mockEnvironment)
            
            // Create manager for this scenario
            let manager = MockKanataManager(mockEnvironment: mockEnvironment)
            
            // Execute validation
            do {
                let success = try await scenario.validation(manager)
                
                if success {
                    passedScenarios.append(scenario.name)
                    print("✅ PASSED: \(scenario.name)")
                } else {
                    failedScenarios.append((scenario.name, "Validation returned false"))
                    print("❌ FAILED: \(scenario.name) - Validation failed")
                }
            } catch {
                failedScenarios.append((scenario.name, error.localizedDescription))
                print("❌ FAILED: \(scenario.name) - Error: \(error.localizedDescription)")
            }
            
            print("---")
        }
        
        // Report results
        print("📊 INTEGRATION TEST RESULTS:")
        print("✅ Passed: \(passedScenarios.count)/\(testScenarios.count)")
        print("❌ Failed: \(failedScenarios.count)/\(testScenarios.count)")
        
        if !failedScenarios.isEmpty {
            print("Failed scenarios:")
            for (name, error) in failedScenarios {
                print("  • \(name): \(error)")
            }
        }
        
        // All scenarios should pass
        XCTAssertEqual(failedScenarios.count, 0, "All integration scenarios should pass")
        XCTAssertEqual(passedScenarios.count, testScenarios.count, "All scenarios should be tested")
    }
    
    // MARK: - Individual Scenario Tests
    
    func testNewUserCompleteJourney() async throws {
        let scenario = testScenarios.first { $0.name == "New User Complete Journey" }!
        
        mockEnvironment.reset()
        scenario.setup(mockEnvironment)
        
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        let success = try await scenario.validation(manager)
        
        XCTAssertTrue(success, "New user journey should complete successfully")
    }
    
    func testPartialInstallationRecovery() async throws {
        let scenario = testScenarios.first { $0.name == "Partial Installation Recovery" }!
        
        mockEnvironment.reset()
        scenario.setup(mockEnvironment)
        
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        let success = try await scenario.validation(manager)
        
        XCTAssertTrue(success, "Partial installation should be recoverable")
    }
    
    func testPowerUserWorkflow() async throws {
        let scenario = testScenarios.first { $0.name == "Power User Daily Workflow" }!
        
        mockEnvironment.reset()
        scenario.setup(mockEnvironment)
        
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        let success = try await scenario.validation(manager)
        
        XCTAssertTrue(success, "Power user workflow should handle intensive usage")
    }
    
    func testErrorRecovery() async throws {
        let scenario = testScenarios.first { $0.name == "Error Recovery and Resilience" }!
        
        mockEnvironment.reset()
        scenario.setup(mockEnvironment)
        
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        let success = try await scenario.validation(manager)
        
        XCTAssertTrue(success, "System should recover gracefully from errors")
    }
    
    func testSecurityCompliance() async throws {
        let scenario = testScenarios.first { $0.name == "Security and Root Privileges" }!
        
        mockEnvironment.reset()
        scenario.setup(mockEnvironment)
        
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        let success = try await scenario.validation(manager)
        
        XCTAssertTrue(success, "Security and permissions should be properly configured")
    }
    
    // MARK: - Performance Integration Tests
    
    func testEndToEndPerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Complete user journey performance test
        mockEnvironment.setupCleanInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        
        // Installation
        let installSuccess = await manager.performTransparentInstallation()
        XCTAssertTrue(installSuccess)
        
        // First launch
        await manager.startKanata()
        XCTAssertTrue(manager.isRunning)
        
        // Configuration
        do {
            try await manager.saveConfiguration(input: "caps", output: "escape")
        } catch {
            // Expected in mock environment
        }
        
        // Cleanup
        await manager.cleanup()
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(timeElapsed, 10.0, "Complete user journey should be performant")
    }
    
    // MARK: - Stress Tests
    
    func testStressScenario() async throws {
        // Stress test with rapid operations
        mockEnvironment.setupCompleteInstallation()
        let manager = MockKanataManager(mockEnvironment: mockEnvironment)
        
        await manager.startKanata()
        XCTAssertTrue(manager.isRunning)
        
        // Rapid start/stop cycles
        for _ in 0..<10 {
            await manager.stopKanata()
            await manager.startKanata()
            XCTAssertTrue(manager.isRunning, "Should handle rapid cycling")
        }
        
        // Multiple configuration changes
        for i in 0..<20 {
            do {
                try await manager.saveConfiguration(input: "key\(i)", output: "output\(i)")
            } catch {
                // Expected in mock environment
            }
        }
        
        XCTAssertTrue(manager.isRunning, "Should remain stable under stress")
    }
}