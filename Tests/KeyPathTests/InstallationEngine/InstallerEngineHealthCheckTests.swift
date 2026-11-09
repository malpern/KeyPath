@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Tests for InstallerEngine health check façade methods
@MainActor
final class InstallerEngineHealthCheckTests: KeyPathAsyncTestCase {
    var engine: InstallerEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = InstallerEngine()
    }

    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }

    // MARK: - checkKanataServiceHealth() Tests

    func testCheckKanataServiceHealthReturnsHealthSnapshot() async {
        let health = await engine.checkKanataServiceHealth()

        // Verify structure
        XCTAssertNotNil(health, "checkKanataServiceHealth() should return runtime readiness evidence")

        // isRunning and isResponding should be booleans
        _ = health.isRunning
        _ = health.isResponding
    }

    func testCheckKanataServiceHealthReturnsConsistentResults() async {
        let health1 = await engine.checkKanataServiceHealth()
        let health2 = await engine.checkKanataServiceHealth()

        // Health status should be consistent between calls
        XCTAssertEqual(
            health1.isRunning, health2.isRunning,
            "isRunning should be consistent between calls"
        )
    }
}
