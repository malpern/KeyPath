import XCTest

@testable import KeyPathAppKit
@testable import KeyPathWizardCore

/// Real-surface smoke tests for InstallerEngine. These are opt-in and only run on a developer machine
/// when KEYPATH_E2E_DEVICE=1 is set. No privileged actions are executed unless KEYPATH_ALLOW_PRIV=1.
@MainActor
final class InstallerDeviceTests: KeyPathAsyncTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await requireDeviceOptIn()
    }

    func testInspectSystemReturnsSnapshot() async throws {
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        XCTAssertFalse(context.system.macOSVersion.isEmpty, "Should report macOS version")
        XCTAssertNotNil(context.permissions.timestamp, "Permissions snapshot should carry a timestamp")
    }

    func testMakePlanForInstallIsReadyOrBlocked() async throws {
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)

        XCTAssertEqual(plan.intent, .install)
        switch plan.status {
        case .ready:
            XCTAssertGreaterThan(plan.recipes.count, 0, "Install plan should propose actions when ready")
        case let .blocked(requirement):
            XCTAssertFalse(requirement.name.isEmpty, "Blocked plan should name the requirement")
        }
    }

    func testExecuteInspectOnlyIsSafe() async throws {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let emptyInspectPlan = InstallPlan(recipes: [], status: .ready, intent: .inspectOnly)

        let report = await engine.execute(plan: emptyInspectPlan, using: broker)
        XCTAssertTrue(report.success, "inspectOnly execute should be a no-op success")
        XCTAssertEqual(report.executedRecipes.count, 0)
    }
}

// MARK: - Helpers

private func requireDeviceOptIn() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["KEYPATH_E2E_DEVICE"] == "1" else {
        throw XCTSkip("Skipping device installer tests (set KEYPATH_E2E_DEVICE=1 to run).")
    }
}
