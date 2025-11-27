@testable import KeyPathAppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

/// Façade parity and regression tests for WizardAutoFixer → InstallerEngine routing.
///
/// These tests ensure that each AutoFixAction dispatched by the wizard correctly routes through
/// InstallerEngine recipes without bypassing the façade (no direct subprocess side effects).
///
/// Issue: https://github.com/malpern/KeyPath/issues/47
@MainActor
final class WizardAutoFixerFacadeTests: XCTestCase {
    var stubCoordinator: StubPrivilegedOperationsCoordinator!
    var broker: PrivilegeBroker!
    var engine: InstallerEngine!

    override func setUp() {
        super.setUp()
        // Prevent real pgrep calls during tests
        VHIDDeviceManager.testPIDProvider = { [] }
        stubCoordinator = StubPrivilegedOperationsCoordinator()
        broker = PrivilegeBroker(coordinator: stubCoordinator)
        engine = InstallerEngine()
    }

    override func tearDown() {
        VHIDDeviceManager.testPIDProvider = nil
        stubCoordinator = nil
        broker = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - All AutoFixActions Have Recipes (Coverage Guard)

    /// Ensures every AutoFixAction has a corresponding recipe in InstallerEngine.
    /// This test will fail if a new action is added without a recipe mapping.
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
                "Action \(action) should have a valid recipe ID"
            )

            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(
                recipe,
                "Action \(action) should produce a ServiceRecipe"
            )
        }
    }

    // MARK: - Recipe ID and Recipe Generation Consistency

    /// Ensures recipeIDForAction and recipeForAction produce consistent results.
    func testRecipeIDMatchesGeneratedRecipe() {
        let context = SystemContextBuilder.cleanInstall()

        let actions: [AutoFixAction] = [
            .installBundledKanata,
            .installLaunchDaemonServices,
            .restartUnhealthyServices,
            .terminateConflictingProcesses,
            .fixDriverVersionMismatch,
            .installCorrectVHIDDriver,
            .adoptOrphanedProcess,
            .replaceOrphanedProcess
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

    // MARK: - Restart Unhealthy Services (Fast/Slow Paths)

    /// Tests restartUnhealthyServices recipe routes through broker to restartUnhealthyServices.
    func testRestartUnhealthyServicesRoutesToBroker() async {
        let report = await engine.runSingleAction(.restartUnhealthyServices, using: broker)

        // Verify the broker was called (recipe executed)
        XCTAssertTrue(
            stubCoordinator.calls.contains("restartUnhealthyServices"),
            "restartUnhealthyServices should call restartUnhealthyServices on broker"
        )
        XCTAssertNotNil(report, "Report should be returned")
    }

    /// Tests that repair plan includes restartUnhealthyServices when services are unhealthy.
    func testRepairPlanIncludesRestartWhenUnhealthy() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)
        let recipeIDs = plan.recipes.map(\.id)

        XCTAssertTrue(
            recipeIDs.contains(engine.recipeIDForAction(.restartUnhealthyServices)),
            "Repair plan should include restartUnhealthyServices when services are unhealthy"
        )
    }

    /// Tests that restartVirtualHIDDaemon maps to the same recipe as restartUnhealthyServices.
    func testRestartVirtualHIDDaemonMapsToRestartUnhealthy() {
        // Per InstallerEngine+Recipes.swift, restartVirtualHIDDaemon uses same recipe
        let id1 = engine.recipeIDForAction(.restartVirtualHIDDaemon)
        let id2 = engine.recipeIDForAction(.restartUnhealthyServices)

        XCTAssertEqual(
            id1, id2,
            "restartVirtualHIDDaemon should map to same recipe as restartUnhealthyServices"
        )
    }

    // MARK: - TCP Actions

    /// Tests enableTCPServer routes through broker to regenerateServiceConfiguration.
    func testEnableTCPServerRoutesToBroker() async {
        let report = await engine.runSingleAction(.enableTCPServer, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("regenerateServiceConfiguration"),
            "enableTCPServer should call regenerateServiceConfiguration on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests setupTCPAuthentication routes through broker to regenerateServiceConfiguration.
    func testSetupTCPAuthenticationRoutesToBroker() async {
        let report = await engine.runSingleAction(.setupTCPAuthentication, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("regenerateServiceConfiguration"),
            "setupTCPAuthentication should call regenerateServiceConfiguration on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests regenerateCommServiceConfiguration routes through broker.
    func testRegenerateCommServiceConfigurationRoutesToBroker() async {
        let report = await engine.runSingleAction(.regenerateCommServiceConfiguration, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("regenerateServiceConfiguration"),
            "regenerateCommServiceConfiguration should call regenerateServiceConfiguration on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests restartCommServer routes through broker to restartUnhealthyServices.
    func testRestartCommServerRoutesToBroker() async {
        let report = await engine.runSingleAction(.restartCommServer, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("restartUnhealthyServices"),
            "restartCommServer should call restartUnhealthyServices on broker"
        )
        XCTAssertNotNil(report)
    }

    // MARK: - VHID Fixes

    /// Tests fixDriverVersionMismatch routes through broker to downloadAndInstallCorrectVHIDDriver.
    func testFixDriverVersionMismatchRoutesToBroker() async {
        let report = await engine.runSingleAction(.fixDriverVersionMismatch, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("downloadAndInstallCorrectVHIDDriver"),
            "fixDriverVersionMismatch should call downloadAndInstallCorrectVHIDDriver on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests installCorrectVHIDDriver routes through broker.
    func testInstallCorrectVHIDDriverRoutesToBroker() async {
        let report = await engine.runSingleAction(.installCorrectVHIDDriver, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("downloadAndInstallCorrectVHIDDriver"),
            "installCorrectVHIDDriver should call downloadAndInstallCorrectVHIDDriver on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests activateVHIDDeviceManager routes through broker.
    func testActivateVHIDDeviceManagerRoutesToBroker() async {
        let report = await engine.runSingleAction(.activateVHIDDeviceManager, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("activateVirtualHIDManager"),
            "activateVHIDDeviceManager should call activateVirtualHIDManager on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests repairVHIDDaemonServices routes through broker.
    func testRepairVHIDDaemonServicesRoutesToBroker() async {
        let report = await engine.runSingleAction(.repairVHIDDaemonServices, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("repairVHIDDaemonServices"),
            "repairVHIDDaemonServices should call repairVHIDDaemonServices on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests that repair plan includes VHID actions when driver version mismatch exists.
    func testRepairPlanIncludesVHIDFixWhenMismatch() async {
        // Create context with VHID version mismatch
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
        let recipeIDs = plan.recipes.map(\.id)

        XCTAssertTrue(
            recipeIDs.contains(engine.recipeIDForAction(.fixDriverVersionMismatch)),
            "Repair plan should include fixDriverVersionMismatch when vhidVersionMismatch is true"
        )
    }

    // MARK: - Bundled Install

    /// Tests installBundledKanata routes through broker.
    func testInstallBundledKanataRoutesToBroker() async {
        let report = await engine.runSingleAction(.installBundledKanata, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("installBundledKanata"),
            "installBundledKanata should call installBundledKanata on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests replaceKanataWithBundled routes through broker.
    func testReplaceKanataWithBundledRoutesToBroker() async {
        let report = await engine.runSingleAction(.replaceKanataWithBundled, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("installBundledKanata"),
            "replaceKanataWithBundled should call installBundledKanata on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests that install plan includes bundled Kanata when components are missing.
    func testInstallPlanIncludesBundledKanataWhenMissing() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let plan = await engine.makePlan(for: .install, context: context)
        let recipeIDs = plan.recipes.map(\.id)

        XCTAssertTrue(
            recipeIDs.contains(engine.recipeIDForAction(.installBundledKanata)),
            "Install plan should include installBundledKanata when components are missing"
        )
    }

    // MARK: - Orphaned Process Flows

    /// Tests adoptOrphanedProcess routes through broker to installLaunchDaemonServicesWithoutLoading.
    func testAdoptOrphanedProcessRoutesToBroker() async {
        let report = await engine.runSingleAction(.adoptOrphanedProcess, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("installLaunchDaemonServicesWithoutLoading"),
            "adoptOrphanedProcess should call installLaunchDaemonServicesWithoutLoading on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests replaceOrphanedProcess routes through broker with kill + install.
    func testReplaceOrphanedProcessRoutesToBroker() async {
        let report = await engine.runSingleAction(.replaceOrphanedProcess, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("killAllKanataProcesses"),
            "replaceOrphanedProcess should call killAllKanataProcesses on broker"
        )
        XCTAssertTrue(
            stubCoordinator.calls.contains("installLaunchDaemonServicesWithoutLoading"),
            "replaceOrphanedProcess should call installLaunchDaemonServicesWithoutLoading on broker"
        )
        XCTAssertNotNil(report)
    }

    // MARK: - Terminate Conflicting Processes

    /// Tests terminateConflictingProcesses routes through broker.
    func testTerminateConflictingProcessesRoutesToBroker() async {
        let report = await engine.runSingleAction(.terminateConflictingProcesses, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("killAllKanataProcesses"),
            "terminateConflictingProcesses should call killAllKanataProcesses on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests that repair plan includes terminate when conflicts exist.
    func testRepairPlanIncludesTerminateWhenConflicts() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true,
            conflicts: [.kanataProcessRunning(pid: 1234, command: "kanata")]
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)
        let recipeIDs = plan.recipes.map(\.id)

        XCTAssertTrue(
            recipeIDs.contains(engine.recipeIDForAction(.terminateConflictingProcesses)),
            "Repair plan should include terminateConflictingProcesses when conflicts exist"
        )
    }

    // MARK: - Install LaunchDaemon Services

    /// Tests installLaunchDaemonServices routes through broker.
    func testInstallLaunchDaemonServicesRoutesToBroker() async {
        let report = await engine.runSingleAction(.installLaunchDaemonServices, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("installAllLaunchDaemonServices"),
            "installLaunchDaemonServices should call installAllLaunchDaemonServices on broker"
        )
        XCTAssertNotNil(report)
    }

    /// Tests that install plan always includes LaunchDaemon services.
    func testInstallPlanAlwaysIncludesLaunchDaemonServices() async {
        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .install, context: context)
        let recipeIDs = plan.recipes.map(\.id)

        XCTAssertTrue(
            recipeIDs.contains(engine.recipeIDForAction(.installLaunchDaemonServices)),
            "Install plan should always include installLaunchDaemonServices"
        )
    }

    // MARK: - Log Rotation

    /// Tests installLogRotation routes through broker.
    func testInstallLogRotationRoutesToBroker() async {
        let report = await engine.runSingleAction(.installLogRotation, using: broker)

        XCTAssertTrue(
            stubCoordinator.calls.contains("installLogRotation"),
            "installLogRotation should call installLogRotation on broker"
        )
        XCTAssertNotNil(report)
    }

    // MARK: - Start Karabiner Daemon

    /// Tests startKarabinerDaemon routes through broker.
    func testStartKarabinerDaemonRoutesToBroker() async {
        let report = await engine.runSingleAction(.startKarabinerDaemon, using: broker)

        // startKarabinerDaemon first checks VHID activation, then restarts
        // It may call activateVirtualHIDManager first, then restartKarabinerDaemonVerified
        XCTAssertTrue(
            stubCoordinator.calls.contains("restartKarabinerDaemonVerified") ||
            stubCoordinator.calls.contains("restartUnhealthyServices"),
            "startKarabinerDaemon should call restart methods on broker"
        )
        XCTAssertNotNil(report)
    }

    // MARK: - Error Handling

    /// Tests that broker failures are captured in the report.
    func testBrokerFailuresCapturedInReport() async {
        stubCoordinator.failOnCall = "installBundledKanata"

        let report = await engine.runSingleAction(.installBundledKanata, using: broker)

        XCTAssertFalse(report.success, "Report should indicate failure when broker fails")
        XCTAssertNotNil(report.failureReason, "Report should include failure reason")
    }

    /// Tests that partial execution is captured in executed recipes.
    func testPartialExecutionCaptured() async {
        // Create a plan with multiple recipes
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let plan = await engine.makePlan(for: .install, context: context)

        // Fail on the second call (whatever it is)
        if plan.recipes.count > 1 {
            // We'll fail on a common call that happens after the first
            stubCoordinator.failOnCall = "activateVirtualHIDManager"
        }

        let report = await engine.execute(plan: plan, using: broker)

        // Some recipes should have been attempted
        XCTAssertNotNil(report.executedRecipes, "Executed recipes should be tracked")
    }

    // MARK: - Recipe Type Mapping

    /// Tests that service installation recipes have correct type.
    func testInstallRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let installAction = AutoFixAction.installLaunchDaemonServices
        let recipe = engine.recipeForAction(installAction, context: context)

        XCTAssertNotNil(recipe)
        XCTAssertEqual(recipe?.type, .installService, "installLaunchDaemonServices should be installService type")
    }

    /// Tests that component installation recipes have correct type.
    func testComponentRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let componentActions: [AutoFixAction] = [
            .installBundledKanata,
            .installCorrectVHIDDriver,
            .installLogRotation,
            .activateVHIDDeviceManager,
            .adoptOrphanedProcess,
            .replaceOrphanedProcess
        ]

        for action in componentActions {
            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(recipe, "Recipe should exist for \(action)")
            XCTAssertEqual(
                recipe?.type, .installComponent,
                "\(action) should be installComponent type"
            )
        }
    }

    /// Tests that restart recipes have correct type.
    func testRestartRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let restartActions: [AutoFixAction] = [
            .restartUnhealthyServices,
            .startKarabinerDaemon,
            .restartVirtualHIDDaemon
        ]

        for action in restartActions {
            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(recipe, "Recipe should exist for \(action)")
            XCTAssertEqual(
                recipe?.type, .restartService,
                "\(action) should be restartService type"
            )
        }
    }

    /// Tests that requirement check recipes have correct type.
    func testRequirementCheckRecipesHaveCorrectType() {
        let context = SystemContextBuilder.cleanInstall()

        let checkActions: [AutoFixAction] = [
            .terminateConflictingProcesses,
            .synchronizeConfigPaths
        ]

        for action in checkActions {
            let recipe = engine.recipeForAction(action, context: context)
            XCTAssertNotNil(recipe, "Recipe should exist for \(action)")
            XCTAssertEqual(
                recipe?.type, .checkRequirement,
                "\(action) should be checkRequirement type"
            )
        }
    }

    // MARK: - runSingleAction Regression Tests

    /// Regression: Ensure all actions can be executed via runSingleAction without "No recipe available" errors.
    func testAllActionsCanBeExecutedViaSingleAction() async {
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
            // Reset stub for each test
            stubCoordinator.calls.removeAll()
            stubCoordinator.failOnCall = nil

            let report = await engine.runSingleAction(action, using: broker)

            XCTAssertNotNil(report, "Report should be returned for \(action)")

            // Should not fail with "No recipe available" error
            if !report.success {
                XCTAssertFalse(
                    report.failureReason?.contains("No recipe available") ?? false,
                    "Action \(action) should not fail with 'No recipe available'"
                )
            }

            // At least one broker call should have been made (unless it's a no-op like createConfigDirectories)
            // createConfigDirectories is a no-op in the broker, so it won't have calls
            if action != .createConfigDirectories && action != .synchronizeConfigPaths {
                XCTAssertGreaterThan(
                    stubCoordinator.calls.count, 0,
                    "Action \(action) should make at least one broker call"
                )
            }
        }
    }
}

// MARK: - Extended SystemContextBuilder for Tests

extension SystemContextBuilder {
    /// Create context with specified conflicts
    init(
        permissionsStatus: PermissionOracle.Status,
        helperReady: Bool,
        servicesHealthy: Bool,
        componentsInstalled: Bool,
        conflicts: [SystemConflict]
    ) {
        self.permissionsStatus = permissionsStatus
        self.helperReady = helperReady
        self.servicesHealthy = servicesHealthy
        self.componentsInstalled = componentsInstalled
        self.conflicts = conflicts
    }
}
