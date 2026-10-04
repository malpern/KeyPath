import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// Executable session plans and individual actions must share the same restricted recipes.
@MainActor
final class WizardRecipeParityTests: KeyPathTestCase {
    private func context(running: Bool) -> SystemContext {
        let now = Date()
        let permissions = PermissionOracle.PermissionSet(
            accessibility: .granted, inputMonitoring: .granted,
            source: "session-test", confidence: .high, timestamp: now
        )
        return SystemContext(
            permissions: .init(keyPath: permissions, kanata: permissions, timestamp: now, backend: .session),
            services: HealthStatus(
                backend: .session, kanataProcessRunning: running, kanataTCPResponding: running,
                kanataRunning: running, karabinerDaemonRunning: false, vhidHealthy: false,
                kanataInputCaptureReady: running
            ),
            conflicts: .empty,
            components: ComponentStatus(
                kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true,
                karabinerDriverInstalled: false, karabinerDaemonRunning: false,
                vhidDeviceInstalled: false, vhidDeviceHealthy: false,
                vhidServicesHealthy: false, vhidVersionMismatch: false
            ),
            helper: .empty, system: EngineSystemInfo(macOSVersion: "27.0", driverCompatible: false),
            timestamp: now
        )
    }

    func testSupportedActionIDsMatchRestrictedRecipes() throws {
        let engine = InstallerEngine()
        for action in [AutoFixAction.restartCommServer, .synchronizeConfigPaths] {
            let recipe = try XCTUnwrap(engine.recipeForAction(action, context: context(running: false)))
            XCTAssertEqual(recipe.id, engine.recipeIDForAction(action))
            XCTAssertTrue(recipe.launchctlActions.isEmpty)
            XCTAssertNil(recipe.serviceID)
            XCTAssertNil(recipe.plistContent)
        }
    }

    func testLegacyActionsHaveNoExecutableRecipes() {
        let engine = InstallerEngine()
        let unsupported: [AutoFixAction] = [
            .installPrivilegedHelper, .reinstallPrivilegedHelper, .terminateConflictingProcesses,
            .startKarabinerDaemon, .restartVirtualHIDDaemon, .installMissingComponents,
            .createConfigDirectories, .activateVHIDDeviceManager, .installRequiredRuntimeServices,
            .repairVHIDDaemonServices, .installLogRotation, .enableTCPServer,
            .setupTCPAuthentication, .regenerateCommServiceConfiguration,
            .regenerateServiceConfiguration, .fixDriverVersionMismatch, .installCorrectVHIDDriver,
        ]
        for action in unsupported {
            XCTAssertNil(engine.recipeForAction(action, context: context(running: false)), "\(action) must be unavailable")
        }
        XCTAssertTrue(engine.generateRecipes(from: unsupported, context: context(running: false)).isEmpty)
    }

    func testInstallAndRepairPlansOnlyStartMissingSession() async {
        let engine = InstallerEngine()
        for intent in [InstallIntent.install, .repair] {
            let captured = context(running: false)
            let plan = await engine.makePlan(for: intent, context: captured)
            XCTAssertEqual(plan.recipes.map(\.id), [engine.recipeIDForAction(.restartCommServer)])
            XCTAssertEqual(plan.recipes.first?.expectedPostconditions, [.runtimeReadyOrApprovalPending])
            XCTAssertEqual(plan.sourceSnapshotID, captured.snapshotID)
        }
    }

    func testReadySessionHasNoHelperOrDriverRepairPlan() async {
        let engine = InstallerEngine()
        for intent in [InstallIntent.install, .repair] {
            let captured = context(running: true)
            let plan = await engine.makePlan(for: intent, context: captured)
            XCTAssertTrue(plan.recipes.isEmpty)
            XCTAssertEqual(plan.sourceSnapshotID, captured.snapshotID)
        }
    }
}
