import XCTest
import SwiftUI
import Observation
@testable import KeyPath

final class SecurityManagerTests: XCTestCase {
    var securityManager: SecurityManager!

    override func setUp() {
        super.setUp()
        securityManager = SecurityManager()
    }

    override func tearDown() {
        securityManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(securityManager)

        // The security manager should have performed an initial environment check
        // The actual values depend on the system state, so we just verify they're set
        XCTAssertNotNil(securityManager.isKanataInstalled)
        XCTAssertNotNil(securityManager.hasConfigAccess)
        XCTAssertNotNil(securityManager.needsSudoPermission)
    }

    // MARK: - Environment Check Tests

    func testCheckEnvironment() {
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess

        // Call checkEnvironment again
        securityManager.checkEnvironment()

        // States should be consistent (unless system changed between calls)
        // This tests that the method doesn't crash and maintains consistency
        XCTAssertEqual(securityManager.isKanataInstalled, initialKanataState)
        XCTAssertEqual(securityManager.hasConfigAccess, initialConfigState)
    }

    func testForceRefresh() {
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess

        // Force refresh should update states
        securityManager.forceRefresh()

        // States should be rechecked (might be same or different)
        XCTAssertEqual(securityManager.isKanataInstalled, initialKanataState)
        XCTAssertEqual(securityManager.hasConfigAccess, initialConfigState)
    }

    // MARK: - Published Properties Tests

    func testObservableProperties() {
        // Test that observable properties are accessible and have valid values
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess
        let initialSudoState = securityManager.needsSudoPermission

        // Properties should be accessible (Boolean values are valid)
        XCTAssertNotNil(initialKanataState)
        XCTAssertNotNil(initialConfigState)
        XCTAssertNotNil(initialSudoState)

        // Test that forceRefresh works without throwing
        XCTAssertNoThrow(securityManager.forceRefresh())

        // Values after refresh should still be valid
        XCTAssertNotNil(securityManager.isKanataInstalled)
        XCTAssertNotNil(securityManager.hasConfigAccess)
        XCTAssertNotNil(securityManager.needsSudoPermission)
    }

    // MARK: - Rule Installation Permission Tests

    func testCanInstallRulesWithBothPermissions() {
        // Simulate having both Kanata and config access
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = true

        XCTAssertTrue(securityManager.canInstallRules())
    }

    func testCanInstallRulesWithoutKanata() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = true

        XCTAssertFalse(securityManager.canInstallRules())
    }

    func testCanInstallRulesWithoutConfigAccess() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = false

        XCTAssertFalse(securityManager.canInstallRules())
    }

    func testCanInstallRulesWithoutBothPermissions() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = false

        XCTAssertFalse(securityManager.canInstallRules())
    }

    // MARK: - Confirmation Tests

    func testRequestConfirmation() {
        let expectation = self.expectation(description: "Confirmation requested")

        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test confirmation"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Test rule for confirmation"
        )

        securityManager.requestConfirmation(for: rule) { confirmed in
            // The current implementation auto-confirms
            XCTAssertTrue(confirmed)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    // MARK: - Setup Instructions Tests

    func testGetSetupInstructionsWithNoKanata() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = true
        securityManager.needsSudoPermission = false

        let instructions = securityManager.getSetupInstructions()

        XCTAssertTrue(instructions.contains("Kanata Not Found"))
        XCTAssertTrue(instructions.contains("github.com/jtroo/kanata"))
        XCTAssertTrue(instructions.contains("/usr/local/bin/"))
        XCTAssertFalse(instructions.contains("Configuration Setup"))
        XCTAssertFalse(instructions.contains("Sudo Access Required"))
    }

    func testGetSetupInstructionsWithNoConfigAccess() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = false
        securityManager.needsSudoPermission = false

        let instructions = securityManager.getSetupInstructions()

        XCTAssertFalse(instructions.contains("Kanata Not Found"))
        XCTAssertTrue(instructions.contains("Configuration Setup"))
        XCTAssertTrue(instructions.contains("~/.config/kanata/kanata.kbd"))
        XCTAssertFalse(instructions.contains("Sudo Access Required"))
    }

    func testGetSetupInstructionsWithSudoRequired() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = true
        securityManager.needsSudoPermission = true

        let instructions = securityManager.getSetupInstructions()

        XCTAssertFalse(instructions.contains("Kanata Not Found"))
        XCTAssertFalse(instructions.contains("Configuration Setup"))
        XCTAssertTrue(instructions.contains("Sudo Access Required"))
        XCTAssertTrue(instructions.contains("password"))
    }

    func testGetSetupInstructionsWithAllIssues() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = false
        securityManager.needsSudoPermission = true

        let instructions = securityManager.getSetupInstructions()

        XCTAssertTrue(instructions.contains("Kanata Not Found"))
        XCTAssertTrue(instructions.contains("Configuration Setup"))
        XCTAssertTrue(instructions.contains("Sudo Access Required"))
    }

    func testGetSetupInstructionsWithEverythingWorking() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = true
        securityManager.needsSudoPermission = false

        let instructions = securityManager.getSetupInstructions()

        XCTAssertTrue(instructions.isEmpty)
    }

    // MARK: - Integration Tests

    func testCompleteSecurityFlow() {
        // Test the complete security flow
        let initialCanInstall = securityManager.canInstallRules()

        // Create a test rule
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Complete flow test"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a b)",
            confidence: .medium,
            explanation: "Test rule for complete flow"
        )

        if initialCanInstall {
            // If we can install rules, test the confirmation flow
            let expectation = self.expectation(description: "Confirmation flow")

            securityManager.requestConfirmation(for: rule) { confirmed in
                XCTAssertTrue(confirmed) // Auto-confirms in current implementation
                expectation.fulfill()
            }

            waitForExpectations(timeout: 1.0, handler: nil)
        } else {
            // If we can't install rules, verify we get appropriate instructions
            let instructions = securityManager.getSetupInstructions()
            XCTAssertFalse(instructions.isEmpty)

            // Instructions should contain helpful information
            XCTAssertTrue(
                instructions.contains("Kanata") ||
                instructions.contains("Configuration") ||
                instructions.contains("Sudo")
            )
        }
    }

    // MARK: - State Consistency Tests

    func testStateConsistency() {
        // Test that the security manager maintains consistent state
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess
        let initialCanInstall = securityManager.canInstallRules()

        // The canInstallRules should be consistent with individual states
        let expectedCanInstall = initialKanataState && initialConfigState
        XCTAssertEqual(initialCanInstall, expectedCanInstall)

        // Multiple calls should return consistent results
        XCTAssertEqual(securityManager.canInstallRules(), initialCanInstall)
        XCTAssertEqual(securityManager.canInstallRules(), initialCanInstall)
    }

    // MARK: - Async Operation Tests

    func testAsyncConfirmation() {
        let expectation = self.expectation(description: "Async confirmation")

        let behavior = KanataBehavior.tapHold(key: "caps", tap: "esc", hold: "ctrl")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Async Test",
            description: "Testing async confirmation"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps (tap-hold 200 200 esc lctrl))",
            confidence: .high,
            explanation: "Async test rule"
        )

        // Test that confirmation is called on main queue
        securityManager.requestConfirmation(for: rule) { confirmed in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(confirmed)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0, handler: nil)
    }
}

// MARK: - SecurityConfirmationView Tests

final class SecurityConfirmationViewTests: XCTestCase {

    func testSecurityConfirmationViewCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test View",
            description: "Testing view creation"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Test rule for view"
        )

        var confirmationResult: Bool?

        let view = SecurityConfirmationView(rule: rule) { confirmed in
            confirmationResult = confirmed
        }

        XCTAssertNotNil(view)

        // Simulate user interaction
        view.onConfirm(true)
        XCTAssertEqual(confirmationResult, true)

        view.onConfirm(false)
        XCTAssertEqual(confirmationResult, false)
    }
}
