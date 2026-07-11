import Foundation
@testable import KeyPathAppKit
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class UninstallCoordinatorTests: XCTestCase {
    func testHealthyHelperUninstallsWithoutAdminFallback() async {
        var postconditionsSatisfied = false
        var helperUninstallCalls = 0
        var adminFallbackCalls = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in
                adminFallbackCalls += 1
                return .failure("Admin fallback should not run")
            },
            postconditionsSatisfied: { _ in postconditionsSatisfied },
            helperInstalled: { true },
            helperFunctional: { true },
            repairHelper: { XCTFail("Healthy helper should not be repaired"); return false },
            uninstallViaHelper: { _ in
                helperUninstallCalls += 1
                postconditionsSatisfied = true
            }
        )

        let result = await coordinator.performUninstall()

        XCTAssertTrue(result.success)
        XCTAssertEqual(helperUninstallCalls, 1)
        XCTAssertEqual(adminFallbackCalls, 0)
        XCTAssertNil(result.recommendedRecovery)
        XCTAssertTrue(result.steps.contains { $0.id == "uninstall-via-helper" && $0.success })
        XCTAssertTrue(result.steps.contains { $0.id == "verify-uninstall" && $0.success })
    }

    func testMissingHelperIsRepairedBeforeUninstall() async {
        var postconditionsSatisfied = false
        var helperReady = false
        var repairCalls = 0
        var helperUninstallCalls = 0
        let coordinator = makeCoordinator(
            postconditionsSatisfied: { _ in postconditionsSatisfied },
            helperInstalled: { false },
            helperFunctional: { helperReady },
            repairHelper: {
                repairCalls += 1
                helperReady = true
                return true
            },
            uninstallViaHelper: { _ in
                helperUninstallCalls += 1
                postconditionsSatisfied = true
            }
        )

        let result = await coordinator.performUninstall()

        XCTAssertTrue(result.success)
        XCTAssertEqual(repairCalls, 1)
        XCTAssertEqual(helperUninstallCalls, 1)
        XCTAssertTrue(result.steps.contains { $0.id == "repair-uninstall-helper" && $0.success })
    }

    func testMissingHelperDoesNotAutomaticallyRunAdminFallback() async {
        var adminFallbackCalls = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in
                adminFallbackCalls += 1
                return .success
            },
            postconditionsSatisfied: { _ in false },
            helperInstalled: { false },
            helperFunctional: { false },
            repairHelper: { false }
        )

        let result = await coordinator.performUninstall()

        XCTAssertFalse(result.success)
        XCTAssertEqual(adminFallbackCalls, 0)
        XCTAssertEqual(result.recommendedRecovery, .emergencyCleanup)
        XCTAssertEqual(coordinator.recommendedRecovery, .emergencyCleanup)
        XCTAssertTrue(result.failureReason?.contains("could not be repaired") == true)
    }

    func testVirtualHIDRemovalRunsBeforeHelperSelfDestruct() async {
        var postconditionsSatisfied = false
        var events: [String] = []
        let coordinator = makeCoordinator(
            postconditionsSatisfied: { _ in postconditionsSatisfied },
            uninstallViaHelper: { _ in
                events.append("uninstall-keypath")
                postconditionsSatisfied = true
            },
            uninstallVirtualHID: {
                events.append("uninstall-driver")
            },
            virtualHIDRemoved: { true }
        )

        let result = await coordinator.performUninstall(removeVirtualHID: true)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, ["uninstall-driver", "uninstall-keypath"])
        XCTAssertTrue(result.steps.contains { $0.id == "uninstall-virtual-hid-driver" && $0.success })
    }

    func testVirtualHIDFailureStopsBeforeRemovingKeyPath() async {
        var helperUninstallCalls = 0
        let coordinator = makeCoordinator(
            postconditionsSatisfied: { _ in false },
            uninstallViaHelper: { _ in helperUninstallCalls += 1 },
            uninstallVirtualHID: {
                throw NSError(domain: "UninstallTests", code: 7)
            }
        )

        let result = await coordinator.performUninstall(removeVirtualHID: true)

        XCTAssertFalse(result.success)
        XCTAssertEqual(helperUninstallCalls, 0)
        XCTAssertTrue(result.failureReason?.contains("could not be removed") == true)
        XCTAssertTrue(result.failureReason?.contains("Uncheck driver removal") == true)
        XCTAssertNil(result.recommendedRecovery)
        XCTAssertTrue(result.steps.contains { $0.id == "uninstall-virtual-hid-driver" && !$0.success })
        XCTAssertFalse(result.steps.contains { $0.id == "uninstall-via-helper" })
    }

    func testExplicitEmergencyCleanupRunsAdminFallbackAndVerifies() async {
        var postconditionsSatisfied = false
        var adminFallbackCalls = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in
                adminFallbackCalls += 1
                postconditionsSatisfied = true
                return .success
            },
            postconditionsSatisfied: { _ in postconditionsSatisfied },
            helperInstalled: { false },
            helperFunctional: { false },
            repairHelper: { false }
        )

        let result = await coordinator.performUninstall(allowAdminFallback: true)

        XCTAssertTrue(result.success)
        XCTAssertEqual(adminFallbackCalls, 1)
        XCTAssertNil(result.recommendedRecovery)
        XCTAssertTrue(result.steps.contains { $0.id == "emergency-admin-cleanup" && $0.success })
    }

    func testEmergencyCleanupFailsWhenScriptIsMissing() async {
        let coordinator = makeCoordinator(
            resolveUninstallerURL: { nil },
            postconditionsSatisfied: { _ in false },
            helperInstalled: { false },
            helperFunctional: { false },
            repairHelper: { false }
        )

        let result = await coordinator.performUninstall(allowAdminFallback: true)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.failureReason, "Uninstaller script wasn't found in this build.")
        XCTAssertTrue(result.steps.contains { $0.id == "emergency-admin-cleanup" && !$0.success })
    }

    func testEmergencyCleanupDoesNotTrustCommandSuccessWithoutPostconditions() async {
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in .success },
            postconditionsSatisfied: { _ in false },
            helperInstalled: { false },
            helperFunctional: { false },
            repairHelper: { false }
        )

        let result = await coordinator.performUninstall(allowAdminFallback: true)

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.failureReason,
            "Emergency Cleanup finished, but some requested system components remain installed."
        )
    }

    func testSatisfiedPostconditionsSkipHelperAndFallback() async {
        var helperChecked = false
        var adminFallbackCalls = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in
                adminFallbackCalls += 1
                return .failure("Should not run")
            },
            postconditionsSatisfied: { _ in true },
            helperInstalled: {
                helperChecked = true
                return false
            }
        )

        let result = await coordinator.performUninstall()

        XCTAssertTrue(result.success)
        XCTAssertFalse(helperChecked)
        XCTAssertEqual(adminFallbackCalls, 0)
        XCTAssertTrue(coordinator.logLines.contains { $0.contains("cleanup already satisfied") })
    }

    func testLostHelperReplyWithSatisfiedPostconditionsSkipsEmergencyCleanup() async {
        var helperAttempted = false
        var adminFallbackCalls = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in
                adminFallbackCalls += 1
                return .failure("Emergency Cleanup should not run")
            },
            postconditionsSatisfied: { _ in helperAttempted },
            uninstallViaHelper: { _ in
                helperAttempted = true
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
        )

        let result = await coordinator.performUninstall(allowAdminFallback: true)

        XCTAssertTrue(result.success)
        XCTAssertEqual(adminFallbackCalls, 0)
        XCTAssertTrue(result.steps.contains { $0.id == "uninstall-via-helper" && !$0.success })
        XCTAssertTrue(result.steps.contains { $0.id == "verify-uninstall" && $0.success })
        XCTAssertTrue(coordinator.logLines.contains { $0.contains("skipping Emergency Cleanup") })
    }

    func testDeleteConfigIntentDoesNotAcceptSystemOnlyPostconditions() async {
        var helperAttempted = false
        var adminFallbackCalls = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, deleteConfig, _ in
                XCTAssertTrue(deleteConfig)
                adminFallbackCalls += 1
                return .success
            },
            postconditionsSatisfied: { deleteConfig in
                helperAttempted && !deleteConfig
            },
            uninstallViaHelper: { _ in
                helperAttempted = true
                throw HelperManagerError.ambiguousOutcome("reply lost")
            }
        )

        let result = await coordinator.performUninstall(
            deleteConfig: true,
            allowAdminFallback: true
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(adminFallbackCalls, 1)
    }

    func testCompletedHelperReplyDoesNotDuplicateStepsWhenEmergencyCleanupRuns() async {
        var postconditionChecks = 0
        let coordinator = makeCoordinator(
            runWithAdminPrivileges: { _, _, _ in .success },
            postconditionsSatisfied: { _ in
                postconditionChecks += 1
                return postconditionChecks > 9
            },
            uninstallViaHelper: { _ in },
            unregisterHelper: { false }
        )

        let result = await coordinator.performUninstall(allowAdminFallback: true)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.steps.filter { $0.id == "unregister-uninstall-helper" }.count, 1)
        XCTAssertEqual(result.steps.filter { $0.id == "verify-uninstall" }.count, 1)
        XCTAssertEqual(result.steps.filter { $0.id == "emergency-admin-cleanup" }.count, 1)
    }

    private func makeCoordinator(
        resolveUninstallerURL: @escaping () -> URL? = {
            URL(fileURLWithPath: "/tmp/keypath-test-uninstall.sh")
        },
        runWithAdminPrivileges: @escaping (URL, Bool, Bool) async -> AppleScriptResult = { _, _, _ in
            .failure("Admin fallback should not run")
        },
        postconditionsSatisfied: @escaping (Bool) -> Bool,
        helperInstalled: @escaping () async -> Bool = { true },
        helperFunctional: @escaping () async -> Bool = { true },
        repairHelper: @escaping () async -> Bool = { true },
        uninstallViaHelper: @escaping (Bool) async throws -> Void = { _ in },
        unregisterHelper: @escaping () async -> Bool = { true },
        uninstallVirtualHID: @escaping () async throws -> Void = {},
        virtualHIDRemoved: @escaping () async -> Bool = { true }
    ) -> UninstallCoordinator {
        UninstallCoordinator(
            resolveUninstallerURL: resolveUninstallerURL,
            runWithAdminPrivileges: runWithAdminPrivileges,
            uninstallPostconditionsSatisfied: postconditionsSatisfied,
            helperInstalled: helperInstalled,
            helperFunctional: helperFunctional,
            repairHelper: repairHelper,
            uninstallViaHelper: uninstallViaHelper,
            unregisterHelper: unregisterHelper,
            unregisterRuntimeServices: {},
            uninstallVirtualHID: uninstallVirtualHID,
            virtualHIDRemoved: virtualHIDRemoved
        )
    }
}

private extension AppleScriptResult {
    static let success = AppleScriptResult(success: true, output: "", error: "", exitStatus: 0)

    static func failure(_ message: String) -> AppleScriptResult {
        AppleScriptResult(success: false, output: "", error: message, exitStatus: 1)
    }
}
