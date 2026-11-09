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
        keyPathIM: PermissionOracle.Status = .granted,
        kanataAX: PermissionOracle.Status = .granted,
        kanataIM: PermissionOracle.Status = .granted
    ) -> PermissionOracle.Snapshot {
        let now = Date()
        return PermissionOracle.Snapshot(
            keyPath: PermissionOracle.PermissionSet(
                accessibility: keyPathAX,
                inputMonitoring: keyPathIM,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            kanata: PermissionOracle.PermissionSet(
                accessibility: kanataAX,
                inputMonitoring: kanataIM,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            timestamp: now, backend: .driverKit
        )
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

    func test_kanataIMDenied_stateIsMissingPermissions() {
        let context = makeContext(
            permissions: makePermissions(kanataIM: .denied)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .missingPermissions(missing: [.keyPathInputMonitoring]))
    }

    func test_keyPathIMDenied_doesNotBlockReadyRuntime() {
        // The app's own Input Monitoring is not a session-runtime requirement;
        // the runtime's effective input access is.
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .denied)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .active)
    }

    func test_kanataAXDenied_stateIsMissingPermissions() {
        let context = makeContext(
            permissions: makePermissions(kanataAX: .denied)
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .missingPermissions(missing: [.keyPathAccessibility]),
                       "Either side's denied Accessibility asks the user to allow KeyPath")
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

    func test_keyPathIMUnknown_doesNotGenerateIssue() {
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .unknown)
        )
        let result = SystemStateResult.projecting(context)
        let imIssue = result.issues.first { $0.identifier == .permission(.keyPathInputMonitoring) }
        XCTAssertNil(imIssue, "Unknown KeyPath IM should not generate an issue (startup mode)")
    }

    // MARK: - WizardRouter: Page Routing

    func test_route_allHealthy_returnsSummary() {
        let page = WizardRouter.route(
            state: .active,
            issues: []
        )
        XCTAssertEqual(page, .summary)
    }

    func test_route_keyPathIMDenied_returnsInputMonitoring() {
        let issues = [WizardIssue(
            identifier: .permission(.keyPathInputMonitoring),
            severity: .error,
            category: .permissions,
            title: "IM denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathInputMonitoring]),
            issues: issues
        )
        XCTAssertEqual(page, .inputMonitoring)
    }

    func test_route_kanataAXDenied_returnsAccessibility() {
        let issues = [WizardIssue(
            identifier: .permission(.kanataAccessibility),
            severity: .error,
            category: .permissions,
            title: "AX denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.kanataAccessibility]),
            issues: issues
        )
        XCTAssertEqual(page, .accessibility)
    }

    func test_route_kanataIMWarning_doesNotRouteToPermissions() {
        let issues = [WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
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

    func test_e2e_kanataIMDenied_routesToInputMonitoring() {
        let context = makeContext(permissions: makePermissions(kanataIM: .denied))
        let result = SystemStateResult.projecting(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues
        )
        XCTAssertEqual(page, .inputMonitoring)
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
            identifier: .permission(.keyPathInputMonitoring),
            severity: .error,
            category: .permissions,
            title: "IM denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let next = WizardRouter.nextPage(
            after: .kanataMigration,
            state: .missingPermissions(missing: [.keyPathInputMonitoring]),
            issues: issues
        )
        XCTAssertEqual(next, .inputMonitoring, "Should skip green pages and land on inputMonitoring")
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
