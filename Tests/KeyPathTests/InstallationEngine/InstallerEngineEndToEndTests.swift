@testable import KeyPathAppKit
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
                ServiceRecipe(id: "install-bundled-kanata", type: .installComponent)
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
            coordinator.calls.contains("installBundledKanata"),
            "Component recipe should install bundled Kanata"
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
                ServiceRecipe(id: "install-bundled-kanata", type: .installComponent)
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
            defer { KanataDaemonManager.smServiceFactory = originalSMFactory }

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
}
