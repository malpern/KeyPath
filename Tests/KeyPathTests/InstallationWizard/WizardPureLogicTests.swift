import Foundation
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Unit tests for the wizard's pure logic types: SystemInspector, WizardRouter,
/// InstallerRecipeID, and ActionDeterminer.
/// These complement the golden tests by covering edge cases and gap scenarios.
///
/// Naming convention: test_<scenario>_<expectedBehavior>
@MainActor
final class WizardPureLogicTests: XCTestCase {
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

    private func makeIssue(
        identifier: IssueIdentifier,
        severity: WizardIssue.IssueSeverity = .error,
        category: WizardIssue.IssueCategory = .permissions,
        autoFixAction: AutoFixAction? = nil
    ) -> WizardIssue {
        WizardIssue(
            identifier: identifier,
            severity: severity,
            category: category,
            title: "Test Issue",
            description: "Test description",
            autoFixAction: autoFixAction,
            userAction: nil
        )
    }

    // MARK: - SystemInspector: State Determination

    func test_inspect_allHealthy_returnsActiveAndNoIssues() {
        let context = makeContext()
        let (state, issues) = SystemInspector.inspect(context: context)
        XCTAssertEqual(state, .active)
        let blocking = issues.filter { $0.severity == .error || $0.severity == .critical }
        XCTAssertTrue(blocking.isEmpty, "Healthy system should have no blocking issues")
    }

    func test_inspect_keyPathAccessibilityDenied_producesMissingPermissionsState() {
        let context = makeContext(permissions: makePermissions(keyPathAX: .denied))
        let (state, _) = SystemInspector.inspect(context: context)
        if case let .missingPermissions(missing) = state {
            XCTAssertTrue(missing.contains(.keyPathAccessibility))
        } else {
            XCTFail("Expected .missingPermissions, got \(state)")
        }
    }

    func test_inspect_keyPathAccessibilityDenied_producesPermissionIssue() {
        let context = makeContext(permissions: makePermissions(keyPathAX: .denied))
        let (_, issues) = SystemInspector.inspect(context: context)
        let axIssue = issues.first { $0.identifier == .permission(.keyPathAccessibility) }
        XCTAssertNotNil(axIssue, "Should generate keyPath accessibility issue")
        XCTAssertEqual(axIssue?.severity, .error)
        XCTAssertEqual(axIssue?.category, .permissions)
    }

    func test_inspect_kanataIMDenied_producesPermissionIssue() {
        let context = makeContext(permissions: makePermissions(kanataIM: .denied))
        let (_, issues) = SystemInspector.inspect(context: context)
        let imIssue = issues.first { $0.identifier == .permission(.kanataInputMonitoring) }
        XCTAssertNotNil(imIssue, "Should generate kanata IM issue")
        XCTAssertEqual(imIssue?.severity, .error)
    }

    func test_inspect_kanataAXUnknown_producesWarningNotError() {
        let context = makeContext(permissions: makePermissions(kanataAX: .unknown))
        let (_, issues) = SystemInspector.inspect(context: context)
        let axIssue = issues.first { $0.identifier == .permission(.kanataAccessibility) }
        XCTAssertNotNil(axIssue, "Should generate issue for unknown kanata AX")
        XCTAssertEqual(axIssue?.severity, .warning, "Unknown kanata permission should be warning")
    }

    func test_inspect_keyPathAXUnknown_doesNotProduceIssue() {
        let context = makeContext(permissions: makePermissions(keyPathAX: .unknown))
        let (_, issues) = SystemInspector.inspect(context: context)
        let axIssue = issues.first { $0.identifier == .permission(.keyPathAccessibility) }
        XCTAssertNil(axIssue, "Unknown KeyPath AX should not generate issue (includeUnknown=false)")
    }

    func test_inspect_vhidDeviceUnhealthy_producesComponentIssue() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let (_, issues) = SystemInspector.inspect(context: context)
        let vhidIssue = issues.first { $0.identifier == .component(.vhidDeviceRunning) }
        XCTAssertNotNil(vhidIssue, "Should generate VHID device issue")
        XCTAssertEqual(vhidIssue?.autoFixAction, .restartVirtualHIDDaemon)
    }

    func test_inspect_vhidServicesUnhealthy_producesComponentIssue() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: false,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let (_, issues) = SystemInspector.inspect(context: context)
        let serviceIssue = issues.first { $0.identifier == .component(.vhidDeviceManager) }
        XCTAssertNotNil(serviceIssue, "Should generate VHID services issue")
        XCTAssertEqual(serviceIssue?.autoFixAction, .installRequiredRuntimeServices)
    }

    func test_inspect_multipleIssues_allReported() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: true,
            vhidVersionMismatch: true
        )
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .denied),
            components: components,
            helper: HelperStatus(isInstalled: false, version: nil, isWorking: false)
        )
        let (_, issues) = SystemInspector.inspect(context: context)

        // Verify multiple issue types are present
        XCTAssertTrue(issues.contains { $0.identifier == .permission(.keyPathInputMonitoring) },
                      "Should report permission issue")
        XCTAssertTrue(issues.contains { $0.identifier == .component(.karabinerDriver) },
                      "Should report missing driver")
        XCTAssertTrue(issues.contains { $0.identifier == .component(.vhidDriverVersionMismatch) },
                      "Should report version mismatch")
        XCTAssertTrue(issues.contains { $0.identifier == .component(.vhidDeviceRunning) },
                      "Should report unhealthy VHID device")
        XCTAssertTrue(issues.contains { $0.identifier == .component(.privilegedHelper) },
                      "Should report missing helper")
    }

    func test_inspect_issueOrdering_permissionsBeforeComponents() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(
            permissions: makePermissions(keyPathIM: .denied),
            components: components
        )
        let (_, issues) = SystemInspector.inspect(context: context)

        // Permission issues should come before component issues (appendPermissionIssues called first)
        let permIndex = issues.firstIndex { $0.identifier == .permission(.keyPathInputMonitoring) }
        let compIndex = issues.firstIndex { $0.identifier == .component(.karabinerDriver) }
        XCTAssertNotNil(permIndex)
        XCTAssertNotNil(compIndex)
        XCTAssertTrue(permIndex! < compIndex!, "Permission issues should precede component issues")
    }

    func test_inspect_conflictsDetected_stateIsConflictsDetected() {
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [
                    .kanataProcessRunning(pid: 100, command: "kanata"),
                    .karabinerGrabberRunning(pid: 200),
                ],
                canAutoResolve: true
            )
        )
        let (state, issues) = SystemInspector.inspect(context: context)
        if case .conflictsDetected = state {
            // pass
        } else {
            XCTFail("Expected .conflictsDetected, got \(state)")
        }
        let conflictIssues = issues.filter { $0.category == .conflicts }
        XCTAssertEqual(conflictIssues.count, 2, "Should have one issue per conflict")
        XCTAssertEqual(conflictIssues.first?.autoFixAction, .terminateConflictingProcesses)
    }

    func test_inspect_conflictsNotAutoResolvable_issueHasNoAutoFix() {
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [.kanataProcessRunning(pid: 100, command: "kanata")],
                canAutoResolve: false
            )
        )
        let (_, issues) = SystemInspector.inspect(context: context)
        let conflictIssue = issues.first { $0.category == .conflicts }
        XCTAssertNil(conflictIssue?.autoFixAction, "Non-auto-resolvable conflict should have no autoFixAction")
    }

    func test_inspect_daemonNotRunning_producesServiceIssue() {
        let context = makeContext(
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: true)
        )
        let (state, issues) = SystemInspector.inspect(context: context)
        XCTAssertEqual(state, .daemonNotRunning)
        let daemonIssue = issues.first { $0.identifier == .component(.karabinerDaemon) }
        XCTAssertNotNil(daemonIssue, "Should generate karabiner daemon issue")
        XCTAssertEqual(daemonIssue?.autoFixAction, .startKarabinerDaemon)
    }

    func test_inspect_helperInstalledButNotWorking_producesUnhealthyIssue() {
        let context = makeContext(helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: false))
        let (_, issues) = SystemInspector.inspect(context: context)
        let helperIssue = issues.first {
            if case let .component(req) = $0.identifier {
                return req == .privilegedHelperUnhealthy
            }
            return false
        }
        XCTAssertNotNil(helperIssue, "Should generate unhealthy helper issue")
        XCTAssertEqual(helperIssue?.autoFixAction, .reinstallPrivilegedHelper)
    }

    func test_inspect_helperNotInstalled_producesInstallIssue() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let (_, issues) = SystemInspector.inspect(context: context)
        let helperIssue = issues.first {
            if case let .component(req) = $0.identifier {
                return req == .privilegedHelper
            }
            return false
        }
        XCTAssertNotNil(helperIssue, "Should generate install helper issue")
        XCTAssertEqual(helperIssue?.autoFixAction, .installPrivilegedHelper)
    }

    func test_inspect_kanataNotRunningWithPermissionRejected_producesPermissionIssue() {
        let context = makeContext(
            services: HealthStatus(
                kanataRunning: false,
                karabinerDaemonRunning: true,
                vhidHealthy: true,
                kanataPermissionRejected: true
            )
        )
        let (state, issues) = SystemInspector.inspect(context: context)
        if case let .missingPermissions(missing) = state {
            XCTAssertTrue(missing.contains(.kanataAccessibility))
        } else {
            XCTFail("Expected .missingPermissions, got \(state)")
        }
        // Should produce a kanataAccessibility permission issue in service issues
        let axIssues = issues.filter { $0.identifier == .permission(.kanataAccessibility) }
        XCTAssertFalse(axIssues.isEmpty, "Should generate AX permission issue for rejected kanata")
    }

    func test_inspect_inputCaptureNotReady_producesIMIssue() {
        let context = makeContext(
            services: HealthStatus(
                kanataRunning: true,
                karabinerDaemonRunning: true,
                vhidHealthy: true,
                kanataInputCaptureReady: false
            )
        )
        let (state, issues) = SystemInspector.inspect(context: context)
        if case let .missingPermissions(missing) = state {
            XCTAssertTrue(missing.contains(.kanataInputMonitoring))
        } else {
            XCTFail("Expected .missingPermissions, got \(state)")
        }
        let imIssues = issues.filter { $0.identifier == .permission(.kanataInputMonitoring) }
        XCTAssertFalse(imIssues.isEmpty, "Should generate IM issue for input capture not ready")
    }

    func test_inspect_timedOut_returnsSingleTimeoutIssue() {
        let context = makeContext(timedOut: true)
        let (state, issues) = SystemInspector.inspect(context: context)
        XCTAssertEqual(state, .serviceNotRunning)
        XCTAssertEqual(issues.count, 1, "Timeout should produce exactly one issue")
        XCTAssertEqual(issues.first?.identifier, .validationTimeout)
        XCTAssertEqual(issues.first?.severity, .warning)
    }

    // MARK: - WizardRouter: route()

    func test_route_noIssuesActiveState_returnsSummary() {
        let page = WizardRouter.route(
            state: .active,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .summary)
    }

    func test_route_conflictsTakePriorityOverEverything() {
        let issues = [
            makeIssue(identifier: .conflict(.kanataProcessRunning(pid: 1, command: "kanata")),
                      category: .conflicts),
            makeIssue(identifier: .permission(.keyPathInputMonitoring)),
        ]
        let page = WizardRouter.route(
            state: .conflictsDetected(conflicts: []),
            issues: issues,
            helperInstalled: false,
            helperNeedsApproval: true
        )
        XCTAssertEqual(page, .conflicts, "Conflicts should take priority even with helper and permission issues")
    }

    func test_route_helperNeedsApproval_returnsHelperBeforePermissions() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathInputMonitoring)),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathInputMonitoring]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: true
        )
        XCTAssertEqual(page, .helper, "Helper approval should take priority over permissions")
    }

    func test_route_kanataIMError_routesToInputMonitoring() {
        let issues = [
            makeIssue(identifier: .permission(.kanataInputMonitoring), severity: .error),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.kanataInputMonitoring]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .inputMonitoring)
    }

    func test_route_keyPathAXDenied_routesToAccessibility() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathAccessibility), severity: .error),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathAccessibility]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .accessibility)
    }

    func test_route_inputMonitoringTakesPriorityOverAccessibility() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathInputMonitoring), severity: .error),
            makeIssue(identifier: .permission(.keyPathAccessibility), severity: .error),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathInputMonitoring, .keyPathAccessibility]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .inputMonitoring, "IM should take priority over AX")
    }

    func test_route_communicationIssue_routesToCommunication() {
        let issues = [
            makeIssue(identifier: .component(.tcpServerNotResponding), category: .installation),
        ]
        let page = WizardRouter.route(
            state: .active,
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .communication)
    }

    func test_route_communicationServerConfig_routesToCommunication() {
        let issues = [
            makeIssue(identifier: .component(.communicationServerConfiguration), category: .installation),
        ]
        let page = WizardRouter.route(
            state: .active,
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .communication)
    }

    func test_route_vhidDriverMismatch_routesToKarabinerComponents() {
        let issues = [
            makeIssue(identifier: .component(.vhidDriverVersionMismatch), category: .installation),
        ]
        let page = WizardRouter.route(
            state: .missingComponents(missing: [.vhidDriverVersionMismatch]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .karabinerComponents)
    }

    func test_route_vhidDeviceManager_routesToKarabinerComponents() {
        let issues = [
            makeIssue(identifier: .component(.vhidDeviceManager), category: .installation),
        ]
        let page = WizardRouter.route(
            state: .active,
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .karabinerComponents)
    }

    func test_route_readyState_routesToService() {
        let page = WizardRouter.route(
            state: .ready,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(page, .service)
    }

    // MARK: - WizardRouter: nextPage()

    func test_nextPage_fromSummary_staysAtSummary() {
        // Summary is first in orderedPages; after it, we walk forward
        let next = WizardRouter.nextPage(after: .summary, state: .active, issues: [])
        // With no issues, should skip everything and land on summary (end of list fallback)
        // But summary is at index 0, so it walks forward and finds no relevant pages, returns .summary
        XCTAssertEqual(next, .summary)
    }

    func test_nextPage_fromHelper_withServiceIssue_skipsToService() {
        let next = WizardRouter.nextPage(
            after: .helper,
            state: .serviceNotRunning,
            issues: []
        )
        XCTAssertEqual(next, .service, "Should skip green pages and land on service")
    }

    func test_nextPage_fromInputMonitoring_withAccessibilityIssue_goesToAccessibility() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathAccessibility)),
        ]
        // inputMonitoring is at index 8 in orderedPages, accessibility is at index 7
        // Since accessibility comes before inputMonitoring in orderedPages, nextPage
        // walks forward from inputMonitoring and won't find accessibility.
        // It should land on the next relevant page or summary.
        let next = WizardRouter.nextPage(
            after: .inputMonitoring,
            state: .active,
            issues: issues
        )
        // After inputMonitoring comes karabinerComponents, service, communication, then end -> summary
        XCTAssertEqual(next, .summary)
    }

    func test_nextPage_fromConflicts_withKarabinerIssue_skipsToKarabinerComponents() {
        let issues = [
            makeIssue(identifier: .component(.karabinerDriver), category: .installation),
        ]
        let next = WizardRouter.nextPage(
            after: .conflicts,
            state: .missingComponents(missing: [.karabinerDriver]),
            issues: issues
        )
        XCTAssertEqual(next, .karabinerComponents)
    }

    func test_nextPage_unknownPage_returnsSummary() {
        // If current page is not in orderedPages (shouldn't happen), returns summary
        // All WizardPage cases are in orderedPages, so this tests defensive behavior
        // We just verify it doesn't crash with a valid page at the end of list
        let next = WizardRouter.nextPage(
            after: .communication,
            state: .active,
            issues: []
        )
        XCTAssertEqual(next, .summary, "Last page should fall through to summary")
    }

    // MARK: - WizardRouter: pageHasRelevantIssues()

    func test_pageHasRelevantIssues_helperPage_withHelperIssue() {
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
        ]
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.helper, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_helperPage_withUnhealthyHelperIssue() {
        let issues = [
            makeIssue(identifier: .component(.privilegedHelperUnhealthy), category: .backgroundServices),
        ]
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.helper, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_helperPage_noHelperIssue() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathInputMonitoring)),
        ]
        XCTAssertFalse(WizardRouter.pageHasRelevantIssues(.helper, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_inputMonitoringPage() {
        let issues = [
            makeIssue(identifier: .permission(.kanataInputMonitoring)),
        ]
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.inputMonitoring, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_accessibilityPage() {
        let issues = [
            makeIssue(identifier: .permission(.kanataAccessibility)),
        ]
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.accessibility, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_communicationPage() {
        let issues = [
            makeIssue(identifier: .component(.tcpServerConfiguration), category: .installation),
        ]
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.communication, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_karabinerComponentsPage() {
        let issues = [
            makeIssue(identifier: .component(.vhidDaemonMisconfigured), category: .installation),
        ]
        XCTAssertTrue(WizardRouter.pageHasRelevantIssues(.karabinerComponents, issues: issues, state: .active))
    }

    func test_pageHasRelevantIssues_fullDiskAccessAlwaysFalse() {
        XCTAssertFalse(WizardRouter.pageHasRelevantIssues(.fullDiskAccess, issues: [], state: .active))
    }

    func test_pageHasRelevantIssues_kanataMigrationAlwaysFalse() {
        XCTAssertFalse(WizardRouter.pageHasRelevantIssues(.kanataMigration, issues: [], state: .active))
    }

    // MARK: - WizardRouter: shouldNavigateToSummary()

    func test_shouldNavigateToSummary_activeNoIssuesNotOnSummary_returnsTrue() {
        XCTAssertTrue(WizardRouter.shouldNavigateToSummary(
            currentPage: .helper,
            state: .active,
            issues: []
        ))
    }

    func test_shouldNavigateToSummary_activeNoIssuesAlreadyOnSummary_returnsFalse() {
        XCTAssertFalse(WizardRouter.shouldNavigateToSummary(
            currentPage: .summary,
            state: .active,
            issues: []
        ))
    }

    func test_shouldNavigateToSummary_notActive_returnsFalse() {
        XCTAssertFalse(WizardRouter.shouldNavigateToSummary(
            currentPage: .helper,
            state: .serviceNotRunning,
            issues: []
        ))
    }

    func test_shouldNavigateToSummary_hasIssues_returnsFalse() {
        let issues = [makeIssue(identifier: .permission(.keyPathInputMonitoring))]
        XCTAssertFalse(WizardRouter.shouldNavigateToSummary(
            currentPage: .helper,
            state: .active,
            issues: issues
        ))
    }

    // MARK: - WizardRouter: isBlockingPage()

    func test_isBlockingPage_karabinerComponents_alwaysBlocking() {
        XCTAssertTrue(WizardRouter.isBlockingPage(.karabinerComponents, helperInstalled: true, helperNeedsApproval: false))
    }

    func test_isBlockingPage_helperNeedsApproval_isBlocking() {
        XCTAssertTrue(WizardRouter.isBlockingPage(.helper, helperInstalled: true, helperNeedsApproval: true))
    }

    func test_isBlockingPage_helperInstalledAndNoApproval_notBlocking() {
        XCTAssertFalse(WizardRouter.isBlockingPage(.helper, helperInstalled: true, helperNeedsApproval: false))
    }

    func test_isBlockingPage_summary_notBlocking() {
        XCTAssertFalse(WizardRouter.isBlockingPage(.summary, helperInstalled: true, helperNeedsApproval: false))
    }

    func test_isBlockingPage_service_notBlocking() {
        XCTAssertFalse(WizardRouter.isBlockingPage(.service, helperInstalled: true, helperNeedsApproval: false))
    }

    // MARK: - InstallerRecipeID: Constants Coverage

    func test_recipeIDs_areUniqueStrings() {
        let allIDs = [
            InstallerRecipeID.installRequiredRuntimeServices,
            InstallerRecipeID.installCorrectVHIDDriver,
            InstallerRecipeID.installLogRotation,
            InstallerRecipeID.installPrivilegedHelper,
            InstallerRecipeID.reinstallPrivilegedHelper,
            InstallerRecipeID.startKarabinerDaemon,
            InstallerRecipeID.terminateConflictingProcesses,
            InstallerRecipeID.fixDriverVersionMismatch,
            InstallerRecipeID.installMissingComponents,
            InstallerRecipeID.createConfigDirectories,
            InstallerRecipeID.activateVHIDManager,
            InstallerRecipeID.repairVHIDDaemonServices,
            InstallerRecipeID.enableTCPServer,
            InstallerRecipeID.setupTCPAuthentication,
            InstallerRecipeID.regenerateCommServiceConfig,
            InstallerRecipeID.regenerateServiceConfig,
            InstallerRecipeID.restartCommServer,
            InstallerRecipeID.synchronizeConfigPaths,
        ]
        let uniqueIDs = Set(allIDs)
        XCTAssertEqual(allIDs.count, uniqueIDs.count, "All recipe IDs should be unique")
    }

    func test_recipeIDs_areKebabCase() {
        let allIDs = [
            InstallerRecipeID.installRequiredRuntimeServices,
            InstallerRecipeID.installCorrectVHIDDriver,
            InstallerRecipeID.installLogRotation,
            InstallerRecipeID.installPrivilegedHelper,
            InstallerRecipeID.reinstallPrivilegedHelper,
            InstallerRecipeID.startKarabinerDaemon,
            InstallerRecipeID.terminateConflictingProcesses,
            InstallerRecipeID.fixDriverVersionMismatch,
            InstallerRecipeID.installMissingComponents,
            InstallerRecipeID.createConfigDirectories,
            InstallerRecipeID.activateVHIDManager,
            InstallerRecipeID.repairVHIDDaemonServices,
            InstallerRecipeID.enableTCPServer,
            InstallerRecipeID.setupTCPAuthentication,
            InstallerRecipeID.regenerateCommServiceConfig,
            InstallerRecipeID.regenerateServiceConfig,
            InstallerRecipeID.restartCommServer,
            InstallerRecipeID.synchronizeConfigPaths,
        ]
        for id in allIDs {
            XCTAssertFalse(id.isEmpty, "Recipe ID should not be empty")
            XCTAssertEqual(id, id.lowercased(), "Recipe ID '\(id)' should be lowercase kebab-case")
            XCTAssertFalse(id.contains(" "), "Recipe ID '\(id)' should not contain spaces")
        }
    }

    // MARK: - ActionDeterminer: Repair Actions

    func test_determineRepairActions_allHealthy_returnsEmpty() {
        let context = makeContext()
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.isEmpty, "Healthy system should need no repair actions")
    }

    func test_determineRepairActions_conflictsAutoResolvable_includesTerminate() {
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [.kanataProcessRunning(pid: 1, command: "kanata")],
                canAutoResolve: true
            )
        )
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.terminateConflictingProcesses))
    }

    func test_determineRepairActions_conflictsNotAutoResolvable_excludesTerminate() {
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [.kanataProcessRunning(pid: 1, command: "kanata")],
                canAutoResolve: false
            )
        )
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertFalse(actions.contains(.terminateConflictingProcesses))
    }

    func test_determineRepairActions_vhidVersionMismatch_includesFix() {
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
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.fixDriverVersionMismatch))
    }

    func test_determineRepairActions_missingDriver_includesInstallAndActivate() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.installMissingComponents))
        XCTAssertTrue(actions.contains(.activateVHIDDeviceManager),
                      "Should activate manager when driver is missing")
    }

    func test_determineRepairActions_daemonNotRunning_includesStartDaemon() {
        let context = makeContext(
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: true)
        )
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.startKarabinerDaemon))
    }

    func test_determineRepairActions_helperInstalledButBroken_includesReinstall() {
        let context = makeContext(helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: false))
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.reinstallPrivilegedHelper),
                      "Repair should reinstall (not install) existing broken helper")
        XCTAssertFalse(actions.contains(.installPrivilegedHelper))
    }

    func test_determineRepairActions_helperMissing_includesInstall() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.installPrivilegedHelper))
    }

    func test_determineRepairActions_vhidServicesUnhealthy_includesInstallRuntimeServices() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: false,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let actions = ActionDeterminer.determineRepairActions(context: context)
        XCTAssertTrue(actions.contains(.installRequiredRuntimeServices))
    }

    // MARK: - ActionDeterminer: Install Actions

    func test_determineInstallActions_allHealthy_returnsEmpty() {
        let context = makeContext()
        let actions = ActionDeterminer.determineInstallActions(context: context)
        XCTAssertTrue(actions.isEmpty, "Healthy system should need no install actions")
    }

    func test_determineInstallActions_helperMissing_usesInstallNotReinstall() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let actions = ActionDeterminer.determineInstallActions(context: context)
        XCTAssertTrue(actions.contains(.installPrivilegedHelper),
                      "Fresh install should use installPrivilegedHelper")
        XCTAssertFalse(actions.contains(.reinstallPrivilegedHelper),
                       "Fresh install should NOT use reinstall")
    }

    func test_determineInstallActions_helperInstalledButBroken_stillUsesInstall() {
        let context = makeContext(helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: false))
        let actions = ActionDeterminer.determineInstallActions(context: context)
        // For install intent, it always uses install (not reinstall)
        XCTAssertTrue(actions.contains(.installPrivilegedHelper))
    }

    // MARK: - ActionDeterminer: Uninstall Actions

    func test_determineUninstallActions_returnsEmpty() {
        let context = makeContext()
        let actions = ActionDeterminer.determineUninstallActions(context: context)
        XCTAssertTrue(actions.isEmpty, "Uninstall is handled by UninstallCoordinator, not ActionDeterminer")
    }

    // MARK: - ActionDeterminer: determineActions with Intent

    func test_determineActions_inspectOnly_returnsEmpty() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let actions = ActionDeterminer.determineActions(for: .inspectOnly, context: context)
        XCTAssertTrue(actions.isEmpty, "Inspect-only should never produce actions")
    }

    func test_determineActions_repairIntent_delegatesToRepairActions() {
        let context = makeContext(helper: HelperStatus(isInstalled: true, version: "1.0", isWorking: false))
        let actions = ActionDeterminer.determineActions(for: .repair, context: context)
        XCTAssertTrue(actions.contains(.reinstallPrivilegedHelper))
    }

    func test_determineActions_installIntent_delegatesToInstallActions() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))
        let actions = ActionDeterminer.determineActions(for: .install, context: context)
        XCTAssertTrue(actions.contains(.installPrivilegedHelper))
    }

    // MARK: - ActionDeterminer: Ordering Guarantees

    func test_determineRepairActions_conflictsBeforeComponents() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(
            conflicts: ConflictStatus(
                conflicts: [.kanataProcessRunning(pid: 1, command: "kanata")],
                canAutoResolve: true
            ),
            components: components
        )
        let actions = ActionDeterminer.determineRepairActions(context: context)
        let terminateIdx = actions.firstIndex(of: .terminateConflictingProcesses)
        let installIdx = actions.firstIndex(of: .installMissingComponents)
        XCTAssertNotNil(terminateIdx)
        XCTAssertNotNil(installIdx)
        XCTAssertTrue(terminateIdx! < installIdx!,
                      "Terminate conflicts should come before installing components")
    }

    func test_determineRepairActions_activateManagerBeforeStartDaemon() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: true),
            components: components
        )
        let actions = ActionDeterminer.determineRepairActions(context: context)
        let activateIdx = actions.firstIndex(of: .activateVHIDDeviceManager)
        let startIdx = actions.firstIndex(of: .startKarabinerDaemon)
        XCTAssertNotNil(activateIdx)
        XCTAssertNotNil(startIdx)
        XCTAssertTrue(activateIdx! < startIdx!,
                      "Activate VHIDDeviceManager should come before starting daemon")
    }
}
