@testable import KeyPathAppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

/// Characterization tests to ensure auto-fix actions map to the same recipes the planner uses.
///
/// These tests validate the façade parity between WizardAutoFixer actions and InstallerEngine recipes.
/// Related: WizardAutoFixerFacadeTests (comprehensive broker routing tests)
///
/// Issue: https://github.com/malpern/KeyPath/issues/47
@MainActor
final class WizardRecipeParityTests: XCTestCase {
    var engine: InstallerEngine!

    override func setUp() {
        super.setUp()
        VHIDDeviceManager.testPIDProvider = { [] }
        engine = InstallerEngine()
    }

    override func tearDown() {
        VHIDDeviceManager.testPIDProvider = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - Recipe ID Consistency

    func testRecipeIDsMatchForCommonActions() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let actions: [AutoFixAction] = [
            .installBundledKanata,
            .installLaunchDaemonServices,
            .restartUnhealthyServices,
            .terminateConflictingProcesses
        ]

        for action in actions {
            guard let recipe = engine.recipeForAction(action, context: context) else {
                XCTFail("Missing recipe for action \(action)")
                continue
            }
            XCTAssertEqual(
                recipe.id,
                engine.recipeIDForAction(action),
                "recipeForAction and recipeIDForAction should agree for \(action)"
            )
        }
    }

    /// Comprehensive test: Every AutoFixAction should have a recipe
    func testAllAutoFixActionsHaveRecipes() {
        let context = SystemContextBuilder.cleanInstall()

        let allActions: [AutoFixAction] = [
            .installPrivilegedHelper,
            .reinstallPrivilegedHelper,
            .terminateConflictingProcesses,
            .startKarabinerDaemon,
            .restartVirtualHIDDaemon,
            .installMissingComponents,
            .createConfigDirectories,
            .activateVHIDDeviceManager,
            .installLaunchDaemonServices,
            .installBundledKanata,
            .repairVHIDDaemonServices,
            .synchronizeConfigPaths,
            .restartUnhealthyServices,
            .adoptOrphanedProcess,
            .replaceOrphanedProcess,
            .installLogRotation,
            .replaceKanataWithBundled,
            .enableTCPServer,
            .setupTCPAuthentication,
            .regenerateCommServiceConfiguration,
            .restartCommServer,
            .fixDriverVersionMismatch,
            .installCorrectVHIDDriver
        ]

        for action in allActions {
            let recipeID = engine.recipeIDForAction(action)
            XCTAssertNotEqual(
                recipeID, "unknown-action",
                "Action \(action) should map to a valid recipe ID"
            )

            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(
                recipe,
                "Action \(action) should produce a ServiceRecipe"
            )

            // Verify consistency
            if let recipe = recipe {
                XCTAssertEqual(
                    recipe.id,
                    recipeID,
                    "Recipe ID should match recipeIDForAction for \(action)"
                )
            }
        }
    }

    // MARK: - Install Plan Tests

    func testInstallPlanIncludesBundledKanataWhenComponentsMissing() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let plan = await engine.makePlan(for: .install, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.installBundledKanata)),
            "Install plan should include bundled kanata when components are missing"
        )
    }

    func testInstallPlanAlwaysIncludesLaunchDaemonServices() async {
        let context = SystemContextBuilder.cleanInstall()

        let plan = await engine.makePlan(for: .install, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.installLaunchDaemonServices)),
            "Install plan should always include installLaunchDaemonServices"
        )
    }

    func testInstallPlanIncludesHelperWhenNotReady() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: false,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let plan = await engine.makePlan(for: .install, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.installPrivilegedHelper)),
            "Install plan should include installPrivilegedHelper when helper is not ready"
        )
    }

    // MARK: - Repair Plan Tests

    func testRepairPlanRestartsServicesWhenUnhealthy() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.restartUnhealthyServices)),
            "Repair plan should restart unhealthy services when health is false"
        )
    }

    func testRepairPlanIncludesConflictResolutionWhenConflictsExist() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true,
            conflicts: [.kanataProcessRunning(pid: 1234, command: "kanata")]
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.terminateConflictingProcesses)),
            "Repair plan should include terminate when conflicts exist"
        )
    }

    func testRepairPlanReinstallsHelperWhenUnhealthy() async {
        // Helper installed but not working
        let permissionSet = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        let permissions = PermissionOracle.Snapshot(
            keyPath: permissionSet,
            kanata: permissionSet,
            timestamp: Date()
        )
        let helper = HelperStatus(isInstalled: true, version: "1.0", isWorking: false)
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            launchDaemonServicesHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = SystemContext(
            permissions: permissions,
            services: HealthStatus(kanataRunning: true, karabinerDaemonRunning: true, vhidHealthy: true),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: components,
            helper: helper,
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: Date()
        )

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.reinstallPrivilegedHelper)),
            "Repair plan should include reinstallPrivilegedHelper when helper is installed but not working"
        )
    }

    // MARK: - InspectOnly Plan Tests

    func testInspectOnlyPlanHasNoRecipes() async {
        let context = SystemContextBuilder.cleanInstall()

        let plan = await engine.makePlan(for: .inspectOnly, context: context)

        XCTAssertEqual(plan.recipes.count, 0, "InspectOnly plan should have no recipes")
        if case .ready = plan.status {
            XCTAssertTrue(true, "InspectOnly plan should be ready")
        } else {
            XCTFail("InspectOnly plan should have .ready status")
        }
    }

    // MARK: - Recipe Type Mapping Tests

    func testServiceInstallRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let recipe = engine.recipeForAction(.installLaunchDaemonServices, context: context)
        XCTAssertNotNil(recipe)
        XCTAssertEqual(recipe?.type, .installService, "installLaunchDaemonServices should be installService type")
    }

    func testComponentInstallRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let componentActions: [AutoFixAction] = [
            .installBundledKanata,
            .installCorrectVHIDDriver,
            .installLogRotation
        ]

        for action in componentActions {
            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(recipe, "Recipe should exist for \(action)")
            XCTAssertEqual(recipe?.type, .installComponent, "\(action) should be installComponent type")
        }
    }

    func testRestartRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let restartActions: [AutoFixAction] = [
            .restartUnhealthyServices,
            .startKarabinerDaemon
        ]

        for action in restartActions {
            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(recipe, "Recipe should exist for \(action)")
            XCTAssertEqual(recipe?.type, .restartService, "\(action) should be restartService type")
        }
    }

    // MARK: - VHID Version Mismatch Tests

    func testRepairPlanIncludesVHIDFixWhenVersionMismatch() async {
        let permissionSet = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        let permissions = PermissionOracle.Snapshot(
            keyPath: permissionSet,
            kanata: permissionSet,
            timestamp: Date()
        )
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            launchDaemonServicesHealthy: true,
            vhidServicesHealthy: false,
            vhidVersionMismatch: true  // Key: version mismatch
        )
        let context = SystemContext(
            permissions: permissions,
            services: HealthStatus(kanataRunning: true, karabinerDaemonRunning: true, vhidHealthy: false),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: components,
            helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: true),
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: Date()
        )

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.fixDriverVersionMismatch)),
            "Repair plan should include fixDriverVersionMismatch when vhidVersionMismatch is true"
        )
    }
}
