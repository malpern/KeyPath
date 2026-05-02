import Foundation
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Golden tests that capture the current behavior of SystemContextAdapter (issue generation)
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
            timestamp: now
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
        HealthStatus(
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true
        )
    }

    private var healthyHelper: HelperStatus {
        HelperStatus(isInstalled: true, version: "1.0", isWorking: true)
    }

    private var defaultSystem: EngineSystemInfo {
        EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true)
    }

    private func makeContext(
        permissions: PermissionOracle.Snapshot? = nil,
        services: HealthStatus? = nil,
        conflicts: ConflictStatus = .empty,
        components: ComponentStatus? = nil,
        helper: HelperStatus? = nil,
        timedOut: Bool = false
    ) -> SystemContext {
        SystemContext(
            permissions: permissions ?? makePermissions(),
            services: services ?? healthyServices,
            conflicts: conflicts,
            components: components ?? allComponentsHealthy,
            helper: helper ?? healthyHelper,
            system: defaultSystem,
            timestamp: Date(),
            timedOut: timedOut
        )
    }

    // MARK: - SystemContextAdapter: State Determination

    func test_allHealthy_stateIsActive() {
        let context = makeContext()
        let result = SystemContextAdapter.adapt(context)
        XCTAssertEqual(result.state, .active)
    }

    func test_timedOut_stateIsServiceNotRunning() {
        let context = makeContext(timedOut: true)
        let result = SystemContextAdapter.adapt(context)
        XCTAssertEqual(result.state, .serviceNotRunning)
    }

    func test_conflictsPresent_stateIsConflictsDetected() {
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [.kanataProcessRunning(pid: 123, command: "kanata")],
                canAutoResolve: true
            )
        )
        let result = SystemContextAdapter.adapt(context)
        if case .conflictsDetected = result.state {
            // pass
        } else {
            XCTFail("Expected .conflictsDetected, got \(result.state)")
        }
    }

    func test_missingKarabinerDriver_stateIsMissingComponents() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let result = SystemContextAdapter.adapt(context)
        if case let .missingComponents(missing) = result.state {
            XCTAssertTrue(missing.contains(.karabinerDriver))
        } else {
            XCTFail("Expected .missingComponents, got \(result.state)")
        }
    }

    func test_keyPathIMDenied_stateIsMissingPermissions() {
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .denied)
        )
        let result = SystemContextAdapter.adapt(context)
        if case let .missingPermissions(missing) = result.state {
            XCTAssertTrue(missing.contains(.keyPathInputMonitoring))
        } else {
            XCTFail("Expected .missingPermissions, got \(result.state)")
        }
    }

    func test_kanataAXDenied_stateIsMissingPermissions() {
        let context = makeContext(
            permissions: makePermissions(kanataAX: .denied)
        )
        let result = SystemContextAdapter.adapt(context)
        if case let .missingPermissions(missing) = result.state {
            XCTAssertTrue(missing.contains(.kanataAccessibility))
        } else {
            XCTFail("Expected .missingPermissions, got \(result.state)")
        }
    }

    func test_kanataIMUnknown_stateStaysActive() {
        let context = makeContext(
            permissions: makePermissions(kanataIM: .unknown)
        )
        let result = SystemContextAdapter.adapt(context)
        XCTAssertEqual(result.state, .active, "Unknown kanata IM should NOT block — it's 'not verified', not denied")
    }

    func test_kanataNotRunning_daemonRunning_stateIsServiceNotRunning() {
        let context = makeContext(
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: true, vhidHealthy: true)
        )
        let result = SystemContextAdapter.adapt(context)
        XCTAssertEqual(result.state, .serviceNotRunning)
    }

    func test_daemonNotRunning_stateIsDaemonNotRunning() {
        let context = makeContext(
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: true)
        )
        let result = SystemContextAdapter.adapt(context)
        XCTAssertEqual(result.state, .daemonNotRunning)
    }

    // MARK: - SystemContextAdapter: Issue Generation

    func test_allHealthy_noBlockingIssues() {
        let context = makeContext()
        let result = SystemContextAdapter.adapt(context)
        let blocking = result.issues.filter { $0.severity == .error || $0.severity == .critical }
        XCTAssertTrue(blocking.isEmpty, "Healthy system should have no blocking issues, got: \(blocking.map(\.title))")
    }

    func test_helperNotInstalled_generatesHelperIssue() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let result = SystemContextAdapter.adapt(context)
        XCTAssertTrue(
            result.issues.contains { $0.identifier == .component(.privilegedHelper) },
            "Should generate privilegedHelper issue"
        )
    }

    func test_helperInstalledButBroken_generatesUnhealthyIssue() {
        let context = makeContext(helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: false))
        let result = SystemContextAdapter.adapt(context)
        XCTAssertTrue(
            result.issues.contains { $0.identifier == .component(.privilegedHelperUnhealthy) },
            "Should generate privilegedHelperUnhealthy issue"
        )
    }

    func test_vhidVersionMismatch_generatesIssueWithAutoFix() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: true
        )
        let context = makeContext(components: components)
        let result = SystemContextAdapter.adapt(context)
        let issue = result.issues.first { $0.identifier == .component(.vhidDriverVersionMismatch) }
        XCTAssertNotNil(issue, "Should generate version mismatch issue")
        XCTAssertEqual(issue?.autoFixAction, .fixDriverVersionMismatch)
    }

    func test_timedOut_generatesSingleWarningIssue() {
        let context = makeContext(timedOut: true)
        let result = SystemContextAdapter.adapt(context)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.identifier, .validationTimeout)
        XCTAssertEqual(result.issues.first?.severity, .warning)
    }

    func test_conflictsPresent_generatesConflictIssues() {
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [
                    .kanataProcessRunning(pid: 123, command: "kanata"),
                    .karabinerGrabberRunning(pid: 456),
                ],
                canAutoResolve: true
            )
        )
        let result = SystemContextAdapter.adapt(context)
        let conflictIssues = result.issues.filter { $0.category == .conflicts }
        XCTAssertEqual(conflictIssues.count, 2)
        XCTAssertEqual(conflictIssues.first?.autoFixAction, .terminateConflictingProcesses)
    }

    func test_kanataIMUnknown_generatesWarningNotError() {
        let context = makeContext(
            permissions: makePermissions(kanataIM: .unknown)
        )
        let result = SystemContextAdapter.adapt(context)
        let imIssue = result.issues.first { $0.identifier == .permission(.kanataInputMonitoring) }
        XCTAssertNotNil(imIssue, "Should generate issue for unknown kanata IM")
        XCTAssertEqual(imIssue?.severity, .warning, "Unknown should be warning, not error")
    }

    func test_keyPathIMUnknown_doesNotGenerateIssue() {
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .unknown)
        )
        let result = SystemContextAdapter.adapt(context)
        let imIssue = result.issues.first { $0.identifier == .permission(.keyPathInputMonitoring) }
        XCTAssertNil(imIssue, "Unknown KeyPath IM should not generate an issue (startup mode)")
    }

    // MARK: - WizardRouter: Page Routing

    func test_route_allHealthy_returnsSummary() {
        let page = WizardRouter.route(
            state: .active,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .summary)
    }

    func test_route_helperNotInstalled_returnsHelper() {
        let page = WizardRouter.route(
            state: .active,
            issues: [],
            helperInstalled: false,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .helper)
    }

    func test_route_helperNeedsApproval_returnsHelper() {
        let page = WizardRouter.route(
            state: .active,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: true
        )
        XCTAssertEqual(page, .helper)
    }

    func test_route_conflictsPresent_returnsConflicts() {
        let issues = [WizardIssue(
            identifier: .conflict(.kanataProcessRunning(pid: 1, command: "kanata")),
            severity: .error,
            category: .conflicts,
            title: "Conflict",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .conflictsDetected(conflicts: []),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .conflicts)
    }

    func test_route_conflictsTrumpHelper() {
        let issues = [WizardIssue(
            identifier: .conflict(.kanataProcessRunning(pid: 1, command: "kanata")),
            severity: .error,
            category: .conflicts,
            title: "Conflict",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .conflictsDetected(conflicts: []),
            issues: issues,
            helperInstalled: false,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .conflicts, "Conflicts should take priority over helper")
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
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
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
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
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
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .summary, "Warning-level permission issues should NOT route to permission pages")
    }

    func test_route_karabinerDriverMissing_returnsKarabinerComponents() {
        let issues = [WizardIssue(
            identifier: .component(.karabinerDriver),
            severity: .error,
            category: .installation,
            title: "Driver missing",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let page = WizardRouter.route(
            state: .missingComponents(missing: [.karabinerDriver]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .karabinerComponents)
    }

    func test_route_serviceNotRunning_returnsService() {
        let page = WizardRouter.route(
            state: .serviceNotRunning,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .service)
    }

    func test_route_daemonNotRunning_returnsService() {
        let page = WizardRouter.route(
            state: .daemonNotRunning,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .service)
    }

    // MARK: - End-to-End: SystemContext → Issues → Page

    func test_e2e_allHealthy_routesToSummary() {
        let context = makeContext()
        let result = SystemContextAdapter.adapt(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .summary)
    }

    func test_e2e_helperMissing_routesToHelper() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let result = SystemContextAdapter.adapt(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues,
            helperInstalled: false,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .helper)
    }

    func test_e2e_keyPathIMDenied_routesToInputMonitoring() {
        let context = makeContext(permissions: makePermissions(keyPathIM: .denied))
        let result = SystemContextAdapter.adapt(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .inputMonitoring)
    }

    func test_e2e_driverMissing_routesToKarabinerComponents() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let result = SystemContextAdapter.adapt(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .karabinerComponents)
    }

    func test_e2e_kanataNotRunning_routesToService() {
        let context = makeContext(
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: true, vhidHealthy: true)
        )
        let result = SystemContextAdapter.adapt(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .service)
    }

    func test_e2e_multipleIssues_routesByPriority() {
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .denied),
            conflicts: ConflictStatus(
                conflicts: [.kanataProcessRunning(pid: 1, command: "kanata")],
                canAutoResolve: true
            )
        )
        let result = SystemContextAdapter.adapt(context)
        let page = WizardRouter.route(
            state: result.state,
            issues: result.issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .conflicts, "Conflicts should take priority over permissions")
    }
}
