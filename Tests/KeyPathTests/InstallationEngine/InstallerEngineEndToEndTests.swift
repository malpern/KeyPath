@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import ServiceManagement
@preconcurrency import XCTest

@MainActor
final class InstallerEngineEndToEndTests: KeyPathAsyncTestCase {
    func testExecutePlanInvokesBrokerAndSucceeds() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-daemons", type: .installService),
                ServiceRecipe(id: InstallerRecipeID.installLogRotation, type: .installComponent)
            ],
            status: .ready,
            intent: .install
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success, "Execution should succeed when broker operations succeed")
        XCTAssertTrue(
            coordinator.calls.contains("installRequiredRuntimeServices"),
            "Install service recipe should attempt to install required runtime services"
        )
        XCTAssertTrue(
            coordinator.calls.contains("installNewsyslogConfig"),
            "Component recipe should install log rotation"
        )
    }

    func testExecutePlanStopsOnBrokerFailure() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        coordinator.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-daemons", type: .installService),
                ServiceRecipe(id: InstallerRecipeID.installLogRotation, type: .installComponent)
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.success, "Failure from broker should mark report unsuccessful")
        XCTAssertEqual(report.executedRecipes.count, 1, "Execution should stop on first failure")
        XCTAssertTrue(
            report.failureReason?.contains("install-daemons") ?? false,
            "Failure should reference the failing recipe"
        )
    }

    func testExecutePlanRunsHelperMaintenanceForPrivilegedHelperRepair() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()
        let helperMaintenance = StubHelperMaintenance()
        WizardDependencies.helperMaintenance = helperMaintenance
        defer { WizardDependencies.helperMaintenance = nil }

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(
                    id: InstallerRecipeID.reinstallPrivilegedHelper,
                    type: .repairPrivilegedHelper,
                    serviceID: "com.keypath.helper"
                )
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success, "Helper maintenance success should mark the recipe successful")
        XCTAssertEqual(helperMaintenance.repairCallCount, 1)
        XCTAssertFalse(
            coordinator.calls.contains("installRequiredRuntimeServices"),
            "Privileged helper repair must not be routed to Kanata LaunchDaemon installation"
        )
    }

    func testExecutePlanUsesInstallOnlyPathForMissingPrivilegedHelper() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()
        let helperMaintenance = StubHelperMaintenance()
        WizardDependencies.helperMaintenance = helperMaintenance
        defer { WizardDependencies.helperMaintenance = nil }

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(
                    id: InstallerRecipeID.installPrivilegedHelper,
                    type: .repairPrivilegedHelper,
                    serviceID: "com.keypath.helper"
                )
            ],
            status: .ready,
            intent: .install
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success)
        XCTAssertEqual(helperMaintenance.installCallCount, 1)
        XCTAssertEqual(helperMaintenance.repairCallCount, 0)
        XCTAssertNil(helperMaintenance.lastForceFullRepair)
        XCTAssertNil(helperMaintenance.lastUseAppleScriptFallback)
    }

    func testRunSingleActionAllowsHelperInstallWhenDriverApprovalIsPending() async {
        let blockedContext = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: false,
            servicesHealthy: false,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
            componentsInstalled: true,
            driverCompatible: true
        ).build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: blockedContext))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let broker = PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        let helperMaintenance = StubHelperMaintenance()
        WizardDependencies.helperMaintenance = helperMaintenance
        defer { WizardDependencies.helperMaintenance = nil }

        let report = await engine.runSingleAction(.installPrivilegedHelper, using: broker)

        XCTAssertTrue(report.success)
        XCTAssertEqual(helperMaintenance.installCallCount, 1)
        XCTAssertFalse(
            report.failureReason?.contains("Driver Extensions") ?? false,
            "Helper-only install should not inherit the broad driver-approval blocker"
        )
    }

    func testInspectSystemForwardsCanonicalSnapshotFreshnessPolicy() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )

        let cachedContext = await engine.inspectSystem(freshness: .cached)
        let freshContext = await engine.inspectSystem()

        XCTAssertEqual(validator.freshnessRequests, [.cached, .fresh])
        XCTAssertEqual(validator.cacheInvalidationCount, 0)
        XCTAssertEqual(cachedContext.system, context.system)
        XCTAssertEqual(freshContext.system, context.system)
    }

    func testExecuteOwnsOneFreshFinalSnapshot() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertEqual(validator.freshnessRequests, [.fresh])
        XCTAssertEqual(validator.cacheInvalidationCount, 1)
        XCTAssertEqual(report.finalContext?.timestamp, context.timestamp)
        XCTAssertEqual(report.finalContext?.captureStatus, context.captureStatus)
    }

    func testInspectOnlyExecuteDoesNotCaptureRedundantFinalSnapshot() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .inspectOnly
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertTrue(validator.freshnessRequests.isEmpty)
        XCTAssertEqual(validator.cacheInvalidationCount, 0)
        XCTAssertNil(report.finalContext)
    }

    func testFailedExecuteStillOwnsOneFreshFinalSnapshot() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "unknown-test-recipe", type: .installComponent),
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertFalse(report.success)
        XCTAssertEqual(validator.freshnessRequests, [.fresh])
        XCTAssertEqual(validator.cacheInvalidationCount, 1)
        XCTAssertEqual(report.finalContext?.timestamp, context.timestamp)
        XCTAssertEqual(report.finalContext?.captureStatus, context.captureStatus)
    }

    func testExecutePlanUsesForceRefreshWithoutAppleScriptForHelperReinstall() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()
        let helperMaintenance = StubHelperMaintenance()
        WizardDependencies.helperMaintenance = helperMaintenance
        defer { WizardDependencies.helperMaintenance = nil }

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(
                    id: InstallerRecipeID.reinstallPrivilegedHelper,
                    type: .repairPrivilegedHelper,
                    serviceID: "com.keypath.helper"
                )
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success)
        XCTAssertEqual(helperMaintenance.installCallCount, 0)
        XCTAssertEqual(helperMaintenance.repairCallCount, 1)
        XCTAssertEqual(helperMaintenance.lastForceFullRepair, true)
        XCTAssertEqual(helperMaintenance.lastUseAppleScriptFallback, false)
    }

    func testExecutePlanTreatsPendingApprovalAsHealthyForKanataHealthCheck() async throws {
        #if DEBUG
            final class PendingApprovalSMAppService: SMAppServiceProtocol, @unchecked Sendable {
                var status: SMAppService.Status {
                    .requiresApproval
                }

                func register() throws {}
                func unregister() async throws {}
            }

            let originalSMFactory = KanataDaemonManager.smServiceFactory
            KanataDaemonManager.smServiceFactory = { _ in PendingApprovalSMAppService() }
            // Status now flows through the centralized provider (#853); point it at the
            // same pending-approval state so the Kanata health check observes it.
            let originalStatusProvider = SMAppServiceStatusProvider.shared
            SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
                cacheTTL: 0,
                serviceFactory: { _ in PendingApprovalSMAppService() }
            )
            defer {
                KanataDaemonManager.smServiceFactory = originalSMFactory
                SMAppServiceStatusProvider.shared = originalStatusProvider
            }

            let coordinator = StubPrivilegedOperationsCoordinator()
            let broker = PrivilegeBroker(coordinator: coordinator)
            let engine = InstallerEngine()

            let plan = InstallPlan(
                recipes: [
                    ServiceRecipe(
                        id: InstallerRecipeID.installRequiredRuntimeServices,
                        type: .installComponent,
                        healthCheck: HealthCheckCriteria(
                            serviceID: KanataDaemonManager.kanataServiceID,
                            shouldBeRunning: true
                        )
                    )
                ],
                status: .ready,
                intent: .install
            )

            let report = await engine.execute(plan: plan, using: broker)

            XCTAssertTrue(report.success)
            XCTAssertTrue(coordinator.calls.contains("installRequiredRuntimeServices"))
        #else
            throw XCTSkip("Uses DEBUG-only KanataDaemonManager.smServiceFactory override")
        #endif
    }

    private static func snapshot(from context: SystemContext) -> SystemSnapshot {
        SystemSnapshot(
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            helper: context.helper,
            compatibility: SystemCompatibilityStatus(
                macOSVersion: context.system.macOSVersion,
                driverCompatible: context.system.driverCompatible
            ),
            timestamp: context.timestamp
        )
    }
}

@MainActor
private final class StubHelperMaintenance: WizardHelperMaintaining {
    private(set) var installCallCount = 0
    private(set) var repairCallCount = 0
    private(set) var lastUseAppleScriptFallback: Bool?
    private(set) var lastForceFullRepair: Bool?
    var logLines: [String] = []
    var lastErrorLine: String?

    func detectDuplicateAppCopies() -> [String] {
        ["/Applications/KeyPath.app"]
    }

    func installOrRefresh() async -> Bool {
        installCallCount += 1
        logLines.append("helper install invoked")
        return true
    }

    func runCleanupAndRepair(useAppleScriptFallback _: Bool) async -> Bool {
        repairCallCount += 1
        lastUseAppleScriptFallback = false
        logLines.append("helper repair invoked")
        return true
    }

    func runCleanupAndRepair(useAppleScriptFallback: Bool, forceFullRepair: Bool) async -> Bool {
        repairCallCount += 1
        lastUseAppleScriptFallback = useAppleScriptFallback
        lastForceFullRepair = forceFullRepair
        logLines.append("helper repair invoked")
        return true
    }
}

@MainActor
private final class StubSystemValidator: WizardSystemValidating {
    private let snapshot: SystemSnapshot
    private(set) var freshnessRequests: [WizardSystemSnapshotFreshness] = []
    private(set) var cacheInvalidationCount = 0

    init(snapshot: SystemSnapshot) {
        self.snapshot = snapshot
    }

    func checkSystem() async -> SystemSnapshot {
        snapshot
    }

    func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        freshnessRequests.append(freshness)
        return snapshot
    }

    func invalidateCaches() {
        cacheInvalidationCount += 1
    }
}
