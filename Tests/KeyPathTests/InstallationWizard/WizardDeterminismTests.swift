@testable import KeyPathAppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import ServiceManagement
@preconcurrency import XCTest

/// Characterization tests to lock current wizard routing behavior so refactors can proceed safely.
@MainActor
final class WizardDeterminismTests: XCTestCase {
    private var originalSMServiceFactory: ((String) -> SMAppServiceProtocol)!
    private var originalRunnerFactory: (() -> SubprocessRunning)!

    override func setUp() async throws {
        try await super.setUp()
        // Force helper to appear installed/enabled so routing decisions are deterministic.
        originalSMServiceFactory = HelperManager.smServiceFactory
        HelperManager.smServiceFactory = { _ in MockEnabledSMAppService() }

        originalRunnerFactory = HelperManager.subprocessRunnerFactory
        HelperManager.subprocessRunnerFactory = { SubprocessRunnerFake.shared }
        await SubprocessRunnerFake.shared.reset()
    }

    override func tearDown() async throws {
        HelperManager.smServiceFactory = originalSMServiceFactory
        originalSMServiceFactory = nil
        HelperManager.subprocessRunnerFactory = originalRunnerFactory
        originalRunnerFactory = nil
        try await super.tearDown()
    }

    func testSameSnapshotProducesSamePageEveryTime() async {
        // Given a snapshot with missing permissions but no conflicts or helper issues
        let context = SystemContextBuilder(
            permissionsStatus: .denied,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true
        ).build()

        let result = SystemContextAdapter.adapt(context)
        let engine = WizardNavigationEngine()

        // When determining the page twice for the same inputs
        let first = await engine.determineCurrentPage(for: result.state, issues: result.issues)
        let second = await engine.determineCurrentPage(for: result.state, issues: result.issues)

        // Then routing is deterministic
        XCTAssertEqual(first, second, "Routing should be deterministic for identical snapshots")
    }

    func testDifferentSnapshotsLeadToDifferentPages() async {
        // Given two distinct snapshots: one with conflicts, one clean and ready
        let conflictContext = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: true,
            componentsInstalled: true,
            conflicts: [.karabinerGrabberRunning(pid: 123)]
        ).build()

        let readyContext = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: true,
            componentsInstalled: true
        ).build()

        let conflictResult = SystemContextAdapter.adapt(conflictContext)
        let readyResult = SystemContextAdapter.adapt(readyContext)

        let engine = WizardNavigationEngine()

        // When routing each snapshot
        let conflictPage = await engine.determineCurrentPage(
            for: conflictResult.state, issues: conflictResult.issues
        )
        let readyPage = await engine.determineCurrentPage(
            for: readyResult.state, issues: readyResult.issues
        )

        // Then pages differ as expected
        XCTAssertEqual(conflictPage, .conflicts)
        XCTAssertNotEqual(conflictPage, readyPage)
    }
}

// MARK: - Local test doubles

private struct MockEnabledSMAppService: SMAppServiceProtocol {
    var status: SMAppService.Status { .enabled }
    func register() throws {}
    func unregister() async throws {}
}
