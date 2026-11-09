import Foundation
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Historical DriverKit characterization tests that capture the behavior of the SystemStateResult projection (issue generation)
/// and WizardRouter (page routing). These tests must pass both before and after the wizard
/// simplification refactor — they prove behavioral equivalence.
///
/// Naming convention: test_<scenario>_<expectedBehavior>
@MainActor
final class WizardGoldenTests: XCTestCase {
    // MARK: - Test Fixtures

    private func makePermissions(
        keyPathAX: PermissionOracle.Status = .granted,
        runtimeKeyAccess: PermissionOracle.Status = .granted
    ) -> PermissionOracle.Snapshot {
        .fixture(accessibility: keyPathAX, runtimeKeyAccess: runtimeKeyAccess)
    }

    private var allComponentsHealthy: ComponentStatus {
        ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
    }

    private var healthyServices: HealthStatus {
        HealthStatus(backend: .driverKit,
                     kanataRunning: true,
                     karabinerDaemonRunning: true,
                     vhidHealthy: true)
    }

    private var defaultSystem: EngineSystemInfo {
        EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true)
    }

    private func makeContext(
        permissions: PermissionOracle.Snapshot? = nil,
        services: HealthStatus? = nil,
        conflicts: ConflictStatus = .empty,
        components: ComponentStatus? = nil,
        timedOut: Bool = false
    ) -> SystemContext {
        SystemContext(
            permissions: permissions ?? makePermissions(),
            services: services ?? healthyServices,
            conflicts: conflicts,
            components: components ?? allComponentsHealthy,
            system: defaultSystem,
            timestamp: Date(),
            timedOut: timedOut
        )
    }

    // MARK: - SystemStateResult projection: State Determination

    func test_allHealthy_stateIsActive() {
        let context = makeContext()
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .active)
    }

    func test_timedOut_stateIsServiceNotRunning() {
        let context = makeContext(timedOut: true)
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .serviceNotRunning)
    }

    func test_runtimeKeyAccessDenied_stateIsMissingPermissions() {
        let context = makeContext(
            permissions: makePermissions(runtimeKeyAccess: .denied)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .missingPermissions(missing: [.runtimeKeyAccess]))
    }

    func test_keyPathAXDenied_stateIsMissingPermissions() {
        let context = makeContext(
            permissions: makePermissions(keyPathAX: .denied)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .missingPermissions(missing: [.keyPathAccessibility]))
    }

    func test_kanataNotRunning_daemonRunning_stateIsServiceNotRunning() {
        let context = makeContext(
            services: HealthStatus(backend: .driverKit, kanataRunning: false, karabinerDaemonRunning: true, vhidHealthy: true)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .serviceNotRunning)
    }

    // MARK: - SystemStateResult projection: Issue Generation

    func test_allHealthy_noBlockingIssues() {
        let context = makeContext()
        let result = SystemStateResult.projecting(context)
        let blocking = result.issues.filter { $0.severity == .error || $0.severity == .critical }
        XCTAssertTrue(blocking.isEmpty, "Healthy system should have no blocking issues, got: \(blocking.map(\.title))")
    }

    func test_timedOut_generatesNoInventedIssues() {
        let context = makeContext(timedOut: true)
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.captureStatus, .timedOut)
        XCTAssertTrue(result.issues.isEmpty, "A timed-out capture must not invent consent or runtime faults")
    }

    func test_runtimeKeyAccessUnknown_doesNotGeneratePermissionIssue() {
        let context = makeContext(
            permissions: makePermissions(runtimeKeyAccess: .unknown)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertFalse(result.issues.contains { $0.identifier.isPermission },
                       "Unreported runtime access is not a denial (startup mode)")
    }

    // MARK: - WizardRouter: Page Routing

    func test_route_allHealthy_returnsSummary() {
        let page = WizardRouter.route(
            state: .active,
            issues: []
        )
        XCTAssertEqual(page, .summary)
    }

    func test_route_runtimeKeyAccessDenied_returnsAccessibility() {
        let issues = [WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .error,
            category: .permissions,
            title: "Runtime key access denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.runtimeKeyAccess]),
            issues: issues
        )
        XCTAssertEqual(page, .accessibility)
    }

    func test_route_keyPathAXDenied_returnsAccessibility() {
        let issues = [WizardIssue(
            identifier: .permission(.keyPathAccessibility),
            severity: .error,
            category: .permissions,
            title: "AX denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathAccessibility]),
            issues: issues
        )
        XCTAssertEqual(page, .accessibility)
    }

    func test_route_permissionWarning_doesNotRouteToPermissions() {
        let issues = [WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .warning,
            category: .permissions,
            title: "Not verified",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .active,
            issues: issues
        )
        XCTAssertEqual(page, .summary, "Warning-level permission issues should NOT route to permission pages")
    }

    func test_route_serviceNotRunning_returnsService() {
        let page = WizardRouter.route(
            state: .serviceNotRunning,
            issues: []
        )
        XCTAssertEqual(page, .service)
    }

    // MARK: - End-to-End: SystemContext → Issues → Page

    func test_e2e_allHealthy_routesToSummary() {
        let context = makeContext()
        let result = SystemStateResult.projecting(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues
        )
        XCTAssertEqual(page, .summary)
    }

    func test_e2e_runtimeKeyAccessDenied_routesToAccessibility() {
        let context = makeContext(permissions: makePermissions(runtimeKeyAccess: .denied))
        let result = SystemStateResult.projecting(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues
        )
        XCTAssertEqual(page, .accessibility)
    }

    func test_e2e_kanataNotRunning_routesToService() {
        let context = makeContext(
            services: HealthStatus(backend: .driverKit, kanataRunning: false, karabinerDaemonRunning: true, vhidHealthy: true)
        )
        let result = SystemStateResult.projecting(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues
        )
        XCTAssertEqual(page, .service)
    }

    // MARK: - WizardRouter: nextPage

    func test_nextPage_skipsGreenPages() {
        let issues = [WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .error,
            category: .permissions,
            title: "Runtime key access denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let next = WizardRouter.nextPage(
            after: .kanataMigration,
            state: .missingPermissions(missing: [.runtimeKeyAccess]),
            issues: issues
        )
        XCTAssertEqual(next, .accessibility, "Should skip green pages and land on accessibility")
    }

    func test_nextPage_allGreen_returnsSummary() {
        let next = WizardRouter.nextPage(after: .accessibility, state: .active, issues: [])
        XCTAssertEqual(next, .summary)
    }

    // MARK: - WizardRouter: pageHasRelevantIssues

    func test_pageHasRelevantIssues_servicePage() {
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.service, issues: [], state: .serviceNotRunning))
        XCTAssertFalse(WizardRouter.pageHasRelevantIssues(.service, issues: [], state: .active))
    }

    func test_pageHasRelevantIssues_summaryAlwaysTrue() {
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.summary, issues: [], state: .active))
    }
}
