import Testing
import SwiftUI
import Observation
@testable import KeyPath

@Suite("SecurityManager Tests")
final class SecurityManagerTests {
    var securityManager: SecurityManager!

    init() {
        securityManager = SecurityManager()
    }

    deinit {
        securityManager = nil
    }

    // MARK: - Initialization Tests

    @Test("Initialization")
    func initialization() {
        #expect(securityManager != nil)

        // Properties should be accessible as Booleans
        _ = securityManager.isKanataInstalled
        _ = securityManager.hasConfigAccess
        _ = securityManager.needsSudoPermission
    }

    // MARK: - Environment Check Tests

    @Test("Check environment")
    func checkEnvironment() {
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess

        securityManager.checkEnvironment()

        #expect(securityManager.isKanataInstalled == initialKanataState)
        #expect(securityManager.hasConfigAccess == initialConfigState)
    }

    @Test("Force refresh")
    func forceRefresh() {
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess

        securityManager.forceRefresh()

        #expect(securityManager.isKanataInstalled == initialKanataState)
        #expect(securityManager.hasConfigAccess == initialConfigState)
    }

    // MARK: - Published Properties Tests

    @Test("Observable properties")
    func observableProperties() {
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess
        let initialSudoState = securityManager.needsSudoPermission

        // Properties should be accessible as Booleans
        _ = initialKanataState
        _ = initialConfigState
        _ = initialSudoState

        securityManager.forceRefresh()

        // Properties should still be accessible after refresh
        _ = securityManager.isKanataInstalled
        _ = securityManager.hasConfigAccess
        _ = securityManager.needsSudoPermission
    }

    // MARK: - Rule Installation Permission Tests

    @Test("Can install rules with both permissions")
    func canInstallRulesWithBothPermissions() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = true

        #expect(securityManager.canInstallRules())
    }

    @Test("Can install rules without Kanata")
    func canInstallRulesWithoutKanata() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = true

        #expect(!securityManager.canInstallRules())
    }

    @Test("Can install rules without config access")
    func canInstallRulesWithoutConfigAccess() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = false

        #expect(!securityManager.canInstallRules())
    }

    @Test("Can install rules without both permissions")
    func canInstallRulesWithoutBothPermissions() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = false

        #expect(!securityManager.canInstallRules())
    }

    // MARK: - Confirmation Tests

    @Test("Request confirmation")
    func requestConfirmation() async throws {
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

        let confirmed = await withCheckedContinuation { continuation in
            securityManager.requestConfirmation(for: rule) { confirmed in
                continuation.resume(returning: confirmed)
            }
        }

        #expect(confirmed)
    }

    // MARK: - Setup Instructions Tests

    @Test("Get setup instructions with no Kanata")
    func getSetupInstructionsWithNoKanata() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = true
        securityManager.needsSudoPermission = false

        let instructions = securityManager.getSetupInstructions()

        #expect(instructions.contains("Kanata Not Found"))
        #expect(instructions.contains("github.com/jtroo/kanata"))
        #expect(instructions.contains("/usr/local/bin/"))
        #expect(!instructions.contains("Configuration Setup"))
        #expect(!instructions.contains("Sudo Access Required"))
    }

    @Test("Get setup instructions with no config access")
    func getSetupInstructionsWithNoConfigAccess() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = false
        securityManager.needsSudoPermission = false

        let instructions = securityManager.getSetupInstructions()

        #expect(!instructions.contains("Kanata Not Found"))
        #expect(instructions.contains("Configuration Setup"))
        #expect(instructions.contains("~/.config/kanata/kanata.kbd"))
        #expect(!instructions.contains("Sudo Access Required"))
    }

    @Test("Get setup instructions with sudo required")
    func getSetupInstructionsWithSudoRequired() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = true
        securityManager.needsSudoPermission = true

        let instructions = securityManager.getSetupInstructions()

        #expect(!instructions.contains("Kanata Not Found"))
        #expect(!instructions.contains("Configuration Setup"))
        #expect(instructions.contains("Sudo Access Required"))
        #expect(instructions.contains("password"))
    }

    @Test("Get setup instructions with all issues")
    func getSetupInstructionsWithAllIssues() {
        securityManager.isKanataInstalled = false
        securityManager.hasConfigAccess = false
        securityManager.needsSudoPermission = true

        let instructions = securityManager.getSetupInstructions()

        #expect(instructions.contains("Kanata Not Found"))
        #expect(instructions.contains("Configuration Setup"))
        #expect(instructions.contains("Sudo Access Required"))
    }

    @Test("Get setup instructions with everything working")
    func getSetupInstructionsWithEverythingWorking() {
        securityManager.isKanataInstalled = true
        securityManager.hasConfigAccess = true
        securityManager.needsSudoPermission = false

        let instructions = securityManager.getSetupInstructions()

        #expect(instructions.isEmpty)
    }

    // MARK: - Integration Tests

    @Test("Complete security flow")
    func completeSecurityFlow() async throws {
        let initialCanInstall = securityManager.canInstallRules()

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
            let confirmed = await withCheckedContinuation { continuation in
                securityManager.requestConfirmation(for: rule) { confirmed in
                    continuation.resume(returning: confirmed)
                }
            }
            #expect(confirmed)
        } else {
            let instructions = securityManager.getSetupInstructions()
            #expect(!instructions.isEmpty)

            #expect(
                instructions.contains("Kanata") ||
                instructions.contains("Configuration") ||
                instructions.contains("Sudo")
            )
        }
    }

    // MARK: - State Consistency Tests

    @Test("State consistency")
    func stateConsistency() {
        let initialKanataState = securityManager.isKanataInstalled
        let initialConfigState = securityManager.hasConfigAccess
        let initialCanInstall = securityManager.canInstallRules()

        let expectedCanInstall = initialKanataState && initialConfigState
        #expect(initialCanInstall == expectedCanInstall)

        #expect(securityManager.canInstallRules() == initialCanInstall)
        #expect(securityManager.canInstallRules() == initialCanInstall)
    }

    // MARK: - Async Operation Tests

    @Test("Async confirmation")
    func asyncConfirmation() async throws {
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

        let (confirmed, isMainThread) = await withCheckedContinuation { continuation in
            securityManager.requestConfirmation(for: rule) { confirmed in
                continuation.resume(returning: (confirmed, Thread.isMainThread))
            }
        }

        #expect(isMainThread)
        #expect(confirmed)
    }
}

// MARK: - SecurityConfirmationView Tests

@Suite("SecurityConfirmationView Tests")
final class SecurityConfirmationViewTests {

    @Test("Security confirmation view creation")
    func securityConfirmationViewCreation() {
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

        #expect(view != nil)

        view.onConfirm(true)
        #expect(confirmationResult == true)

        view.onConfirm(false)
        #expect(confirmationResult == false)
    }
}
