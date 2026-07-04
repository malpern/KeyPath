@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class HelperMaintenanceTests: XCTestCase {
    private var originalExecutor: AdminCommandExecutor!

    override func setUp() async throws {
        try await super.setUp()
        originalExecutor = AdminCommandExecutorHolder.shared
    }

    override func tearDown() async throws {
        try await super.tearDown()
        HelperMaintenance.testDuplicateAppPathsOverride = nil
        HelperMaintenance.shared.applyTestHooks(nil)
        HelperManager.testHelperFunctionalityOverride = nil
        HelperManager.testInstallHelperOverride = nil
        AdminCommandExecutorHolder.shared = originalExecutor
    }

    func testDetectDuplicateAppCopiesFiltersBuildPathsAndSortsApplicationsFirst() {
        HelperMaintenance.testDuplicateAppPathsOverride = {
            [
                "/Users/test/Downloads/KeyPath.app",
                "/dist/KeyPath.app",
                "/Applications/KeyPath.app",
                "/Users/test/KeyPath.app"
            ]
        }

        let copies = HelperMaintenance.shared.detectDuplicateAppCopies()
        XCTAssertEqual(copies.first, "/Applications/KeyPath.app")
        let remaining = Set(copies.dropFirst())
        XCTAssertEqual(
            remaining,
            Set([
                "/Users/test/KeyPath.app",
                "/Users/test/Downloads/KeyPath.app"
            ])
        )
    }

    func testRunCleanupLogsWarningForDuplicateCopies() async {
        HelperMaintenance.testDuplicateAppPathsOverride = {
            [
                "/Applications/KeyPath.app",
                "/Users/other/KeyPath.app"
            ]
        }

        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: {},
            bootoutHelperJob: {},
            removeLegacyHelperArtifacts: { _ in .removed },
            registerHelper: { true }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
        XCTAssertTrue(success)
        XCTAssertTrue(
            HelperMaintenance.shared.logLines.contains {
                $0.contains("Multiple KeyPath.app copies detected:")
            }
        )
    }

    func testAdminCleanupFallbackFailureAbortsRun() async {
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

        let fakeExecutor = FakeAdminCommandExecutor(resultProvider: { _, _ in
            CommandExecutionResult(exitCode: 1, output: "Permission denied")
        })
        AdminCommandExecutorHolder.shared = fakeExecutor

        var attempts = 0
        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: {},
            bootoutHelperJob: {},
            registerHelper: {
                attempts += 1
                // Simulate primary failure; after cleanup still fail
                return attempts > 10 // never reached, keeps returning false
            }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
        XCTAssertFalse(success)
        XCTAssertTrue(
            HelperMaintenance.shared.logLines.contains { $0.localizedCaseInsensitiveContains("failed") },
            "Log should include admin cleanup failure"
        )
    }

    func testAdminCleanupFallbackSucceedsWithExecutor() async {
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

        let fakeExecutor = FakeAdminCommandExecutor()
        AdminCommandExecutorHolder.shared = fakeExecutor

        var attempts = 0
        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: {},
            bootoutHelperJob: {},
            registerHelper: {
                attempts += 1
                // Fail first time to trigger cleanup; succeed after cleanup
                return attempts > 1
            }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
        XCTAssertTrue(success)
        XCTAssertTrue(
            fakeExecutor.commands.contains { $0.description.contains("Remove legacy helper artifacts") }
        )
        XCTAssertTrue(
            HelperMaintenance.shared.logLines.contains {
                $0.localizedCaseInsensitiveContains("removed legacy helper artifacts")
            }
        )
    }

    func testRepairForcesReinstallWhenRegisteredButUnresponsive() async {
        // Regression: SMAppService.register() reports success even when the helper is
        // registered-but-wedged (stale launch constraint after a re-sign), so the bare
        // first-attempt success must NOT be trusted. The repair has to fall through to
        // unregister → bootout → re-register, then succeed once the helper responds.
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

        var unregisterCalled = false
        var bootoutCalled = false
        var registerAttempts = 0
        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: { unregisterCalled = true },
            bootoutHelperJob: { bootoutCalled = true },
            removeLegacyHelperArtifacts: { _ in .removed },
            registerHelper: {
                registerAttempts += 1
                return true // register always "succeeds" — even while wedged
            }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)

        // XPC health: unresponsive on the first-attempt gate, responsive after reinstall.
        var healthChecks = 0
        HelperManager.testHelperFunctionalityOverride = {
            healthChecks += 1
            return healthChecks > 1
        }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)

        XCTAssertTrue(success, "Repair should succeed after forcing a full reinstall")
        XCTAssertTrue(unregisterCalled, "Wedged-but-registered helper must be unregistered")
        XCTAssertTrue(bootoutCalled, "Wedged helper job must be booted out")
        XCTAssertGreaterThanOrEqual(registerAttempts, 2, "Helper must be re-registered after cleanup")
        XCTAssertTrue(
            HelperMaintenance.shared.logLines.contains { $0.localizedCaseInsensitiveContains("forcing full reinstall") },
            "Should log that it forced a reinstall despite register() succeeding"
        )
    }

    func testForceFullRepairReinstallsEvenWhenHelperResponds() async {
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

        var unregisterCalled = false
        var bootoutCalled = false
        var registerAttempts = 0
        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: { unregisterCalled = true },
            bootoutHelperJob: { bootoutCalled = true },
            removeLegacyHelperArtifacts: { _ in .removed },
            registerHelper: {
                registerAttempts += 1
                return true
            }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(
            useAppleScriptFallback: false,
            forceFullRepair: true
        )

        XCTAssertTrue(success)
        XCTAssertTrue(unregisterCalled, "Forced helper repair must unregister even if XPC responds")
        XCTAssertTrue(bootoutCalled, "Forced helper repair must boot out the existing helper job")
        XCTAssertGreaterThanOrEqual(registerAttempts, 2)
        XCTAssertTrue(
            HelperMaintenance.shared.logLines.contains {
                $0.localizedCaseInsensitiveContains("force full helper repair requested")
            }
        )
    }

    func testRunCleanupIsIdempotentWithoutDuplicates() async {
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }
        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: {},
            bootoutHelperJob: {},
            removeLegacyHelperArtifacts: { _ in .removed },
            registerHelper: { true }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let first = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
        XCTAssertTrue(first)
        let second = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
        XCTAssertTrue(second)
    }
}
