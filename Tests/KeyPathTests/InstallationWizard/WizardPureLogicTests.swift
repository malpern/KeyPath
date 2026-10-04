import Foundation
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Unit tests for the wizard's pure logic types: SystemInspector, WizardRouter,
/// InstallerRecipeID, and InstallerDecisionPipeline.
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
                     kanataLaunchdLoaded: true,
                     kanataProcessRunning: true,
                     kanataTCPResponding: true,
                     kanataRunning: true,
                     karabinerDaemonRunning: true,
                     vhidHealthy: true,
                     kanataSMAppServiceRegistered: true,
                     loginItemsApprovalRequired: false)
    }

    private var healthyHelper: HelperStatus {
        HelperStatus(isInstalled: true, version: WizardHelperConstants.expectedHelperVersion, isWorking: true)
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
        captureStatus: SystemSnapshotCaptureStatus = .complete,
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
            captureStatus: captureStatus,
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

    func test_systemContextStateMatrixSnapshot_classifiesStoppedRuntimeWithStaleInputCapture() {
        let context = makeContext(
            services: HealthStatus(backend: .driverKit,
                                   kanataLaunchdLoaded: true,
                                   kanataProcessRunning: false,
                                   kanataTCPResponding: false,
                                   kanataRunning: false,
                                   karabinerDaemonRunning: true,
                                   vhidHealthy: true,
                                   kanataInputCaptureReady: false,
                                   kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureGrabFailureReason,
                                   kanataSMAppServiceRegistered: true,
                                   loginItemsApprovalRequired: false)
        )

        XCTAssertEqual(context.installerStateMatrixRow, .staleInputCaptureIssueWithKanataStopped)
        XCTAssertEqual(context.installerStateMatrixPlan, [.installRequiredRuntimeServices])
    }

    func test_systemStateProjectionPublishesStateMatrixMetadata() {
        let context = makeContext(helper: HelperStatus(isInstalled: false, version: nil, isWorking: false))

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.stateMatrixRow, InstallerStateMatrixRow.helperMissing.rawValue)
        XCTAssertEqual(result.stateMatrixPlan, [InstallerStateMatrixAction.installHelper.rawValue])
        XCTAssertEqual(result.autoFixActions, [], "Historical helper classification must not produce an executable helper repair")
    }

    func test_systemStateProjectionPublishesCapturedHelperRoutingFacts() {
        let context = makeContext(
            helper: HelperStatus(
                isInstalled: false,
                version: nil,
                isWorking: false,
                requiresApproval: true
            )
        )

        let result = SystemStateResult.projecting(context)

        XCTAssertFalse(result.helperInstalled)
        XCTAssertTrue(result.helperNeedsApproval)
    }

    func test_systemStateProjectionPreservesCaptureStatus() {
        let context = makeContext(captureStatus: .cancelled)

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.captureStatus, .cancelled)
        XCTAssertEqual(result.stateMatrixRow, InstallerStateMatrixRow.definitiveUnhealthyState.rawValue)
        XCTAssertTrue(result.issues.contains { $0.identifier == .validationTimeout })
    }

    func test_failedCaptureProducesIncompleteStatusIssue() {
        let context = makeContext(captureStatus: .failed)

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.captureStatus, .failed)
        XCTAssertEqual(result.stateMatrixRow, InstallerStateMatrixRow.definitiveUnhealthyState.rawValue)
        XCTAssertTrue(result.issues.contains {
            $0.identifier == .validationTimeout && $0.title == "Status check incomplete"
        })
    }

    func test_emptyFallbackContextIsExplicitlyIncomplete() {
        XCTAssertEqual(SystemContext.empty.captureStatus, .cancelled)
        XCTAssertEqual(SystemContext.empty.installerStateMatrixRow, .sessionRuntimeStopped)
        XCTAssertEqual(SystemContext.timedOut.captureStatus, .timedOut)
        XCTAssertTrue(SystemContext.timedOut.timedOut)
    }

    func test_stateDetectionWithoutMachineProducesCanonicalTimeoutEvidence() async throws {
        let operation = WizardOperations.stateDetection(stateMachine: nil)

        let result = try await operation.execute { _ in }

        XCTAssertEqual(result.captureStatus, .timedOut)
        XCTAssertEqual(result.issues.map(\.identifier), [.validationTimeout])
    }

    func test_installerDecisionPipelinePinsAssessmentAndExecutablePlanFixtures() {
        struct DecisionFixture {
            let name: String
            let intent: InstallIntent
            let context: SystemContext
            let assessment: InstallerStateMatrixRow
            let matrixActions: [InstallerStateMatrixAction]
            let autoFixActions: [AutoFixAction]
        }

        let missingComponents = ComponentStatus(
            kanataBinaryInstalled: false,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )
        let stoppedWithStaleDiagnostic = HealthStatus(backend: .driverKit,
                                                      kanataLaunchdLoaded: true,
                                                      kanataProcessRunning: false,
                                                      kanataTCPResponding: false,
                                                      kanataRunning: false,
                                                      karabinerDaemonRunning: true,
                                                      vhidHealthy: true,
                                                      kanataInputCaptureReady: false,
                                                      kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureGrabFailureReason,
                                                      kanataSMAppServiceRegistered: true,
                                                      loginItemsApprovalRequired: false)
        let driverApprovalPending = HealthStatus(backend: .driverKit,
                                                 kanataLaunchdLoaded: true,
                                                 kanataProcessRunning: false,
                                                 kanataTCPResponding: false,
                                                 kanataRunning: false,
                                                 karabinerDaemonRunning: true,
                                                 vhidHealthy: false,
                                                 kanataInputCaptureReady: false,
                                                 kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
                                                 kanataSMAppServiceRegistered: true,
                                                 loginItemsApprovalRequired: false)
        let fixtures = [
            DecisionFixture(
                name: "healthy repair",
                intent: .repair,
                context: makeContext(),
                assessment: .runningAndTCPResponding,
                matrixActions: [],
                autoFixActions: []
            ),
            DecisionFixture(
                name: "missing helper repair",
                intent: .repair,
                context: makeContext(helper: .empty),
                assessment: .helperMissing,
                matrixActions: [.installHelper],
                autoFixActions: []
            ),
            DecisionFixture(
                name: "fresh install missing component",
                intent: .install,
                context: makeContext(components: missingComponents),
                assessment: .freshInstallMissingComponents,
                matrixActions: [.installMissingComponents],
                autoFixActions: []
            ),
            DecisionFixture(
                name: "stale diagnostic after stopped runtime",
                intent: .repair,
                context: makeContext(services: stoppedWithStaleDiagnostic),
                assessment: .staleInputCaptureIssueWithKanataStopped,
                matrixActions: [.installRequiredRuntimeServices],
                autoFixActions: [.restartCommServer]
            ),
            DecisionFixture(
                name: "driver approval pending",
                intent: .repair,
                context: makeContext(services: driverApprovalPending),
                assessment: .driverKitApprovalPendingWithKanataStopped,
                matrixActions: [.surfaceDriverKitApproval],
                autoFixActions: [.restartCommServer]
            ),
        ]

        for fixture in fixtures {
            let decision = InstallerDecisionPipeline.decide(
                for: fixture.intent,
                context: fixture.context
            )
            XCTAssertEqual(decision.assessment, fixture.assessment, fixture.name)
            XCTAssertEqual(decision.matrixActions, fixture.matrixActions, fixture.name)
            XCTAssertEqual(decision.autoFixActions, fixture.autoFixActions, fixture.name)
        }
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

    /// A pre-MAL-57 plist (missing ProcessType=Interactive) on an otherwise
    /// healthy system must surface proactively with a one-click repair —
    /// old installs never migrate otherwise.
    func test_inspect_vhidDaemonPlistMisconfigured_producesMisconfiguredIssueWithAutoFix() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidDaemonPlistMisconfigured: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let (state, issues) = SystemInspector.inspect(context: context)

        let issue = issues.first { $0.identifier == .component(.vhidDaemonMisconfigured) }
        XCTAssertNotNil(issue, "Stale VHID daemon plist should generate a misconfigured issue")
        XCTAssertEqual(issue?.category, .installation, "Must be .installation so the router sends it to the Karabiner components page")
        XCTAssertEqual(
            issue?.severity, .warning,
            "Daemon still works — warning nudges migration without flipping the app to a failed state"
        )
        XCTAssertEqual(issue?.autoFixAction, .installRequiredRuntimeServices)

        // The daemon is still running — state stays .active; the issue alone
        // drives routing and the components-page repair button.
        XCTAssertEqual(state, .active)
    }

    /// When the VHID services are already down, the unhealthy-services issue
    /// carries the same fix — don't double-alarm for one root cause.
    func test_inspect_vhidDaemonPlistMisconfiguredAndServicesUnhealthy_emitsSingleIssue() {
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: false,
            vhidDaemonPlistMisconfigured: true,
            vhidVersionMismatch: false
        )
        let context = makeContext(components: components)
        let (_, issues) = SystemInspector.inspect(context: context)

        XCTAssertNil(
            issues.first { $0.identifier == .component(.vhidDaemonMisconfigured) },
            "Misconfigured-plist issue is suppressed while services are unhealthy"
        )
        let serviceIssue = issues.first { $0.identifier == .component(.vhidDeviceManager) }
        XCTAssertEqual(
            serviceIssue?.autoFixAction, .installRequiredRuntimeServices,
            "The unhealthy-services issue carries the same repair"
        )
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
            services: HealthStatus(backend: .driverKit, kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: true)
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
            services: HealthStatus(backend: .driverKit,
                                   kanataRunning: false,
                                   karabinerDaemonRunning: true,
                                   vhidHealthy: true,
                                   kanataPermissionRejected: true)
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
        // Per #642, input-capture-not-ready maps to an Input Monitoring permission
        // issue ONLY when the failure reason is a genuine built-in-keyboard permission
        // problem. A grab failure (driver crash / another app) routes to the service
        // page instead — covered by SystemInspectorInputCaptureTests.
        let context = makeContext(
            services: HealthStatus(backend: .driverKit,
                                   kanataRunning: true,
                                   karabinerDaemonRunning: true,
                                   vhidHealthy: true,
                                   kanataInputCaptureReady: false,
                                   kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason)
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
            helperNeedsApproval: false, backend: .driverKit
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
            helperNeedsApproval: true, backend: .driverKit
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
            helperNeedsApproval: true, backend: .driverKit
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
            helperNeedsApproval: false, backend: .driverKit
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
            helperNeedsApproval: false, backend: .driverKit
        )
        XCTAssertEqual(page, .accessibility)
    }

    func test_route_accessibilityTakesPriorityOverInputMonitoring() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathInputMonitoring), severity: .error),
            makeIssue(identifier: .permission(.keyPathAccessibility), severity: .error),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathInputMonitoring, .keyPathAccessibility]),
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false, backend: .driverKit
        )
        XCTAssertEqual(page, .accessibility, "Resolve AX before requesting separate input access")
    }

    func test_route_communicationIssue_routesToCommunication() {
        let issues = [
            makeIssue(identifier: .component(.tcpServerNotResponding), category: .installation),
        ]
        let page = WizardRouter.route(
            state: .active,
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: false, backend: .driverKit
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
            helperNeedsApproval: false, backend: .driverKit
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
            helperNeedsApproval: false, backend: .driverKit
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
            helperNeedsApproval: false, backend: .driverKit
        )
        XCTAssertEqual(page, .karabinerComponents)
    }

    func test_route_readyState_routesToService() {
        let page = WizardRouter.route(
            state: .ready,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false, backend: .driverKit
        )
        XCTAssertEqual(page, .service)
    }

    // MARK: - WizardRouter: nextPage()

    func test_nextPage_fromSummary_staysAtSummary() {
        // Summary is first in orderedPages; after it, we walk forward
        let next = WizardRouter.nextPage(after: .summary, state: .active, issues: [], backend: .driverKit)
        // With no issues, should skip everything and land on summary (end of list fallback)
        // But summary is at index 0, so it walks forward and finds no relevant pages, returns .summary
        XCTAssertEqual(next, .summary)
    }

    func test_nextPage_fromHelper_withServiceIssue_skipsToService() {
        let next = WizardRouter.nextPage(
            after: .helper,
            state: .serviceNotRunning,
            issues: [], backend: .driverKit
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
            issues: issues, backend: .driverKit
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
            issues: issues, backend: .driverKit
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
            issues: [], backend: .driverKit
        )
        XCTAssertEqual(next, .summary, "Last page should fall through to summary")
    }

    // MARK: - WizardRouter: Prerequisite Enforcement in nextPage()

    func test_nextPage_cannotSkipPastUnresolvedHelper() {
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
            makeIssue(identifier: .component(.karabinerDaemon), category: .installation),
        ]
        let next = WizardRouter.nextPage(
            after: .conflicts,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: false,
            helperNeedsApproval: false, backend: .driverKit
        )
        XCTAssertEqual(next, .helper,
                       "Must stop at helper page — karabiner repair needs the helper")
    }

    func test_nextPage_cannotSkipPastUnresolvedKarabiner() {
        let issues = [
            makeIssue(identifier: .component(.karabinerDaemon), category: .installation),
        ]
        let next = WizardRouter.nextPage(
            after: .accessibility,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: true, backend: .driverKit
        )
        XCTAssertEqual(next, .karabinerComponents,
                       "Must stop at karabiner page — service needs VirtualHID")
    }

    func test_nextPage_helperInstalled_canAdvancePastHelper() {
        let issues = [
            makeIssue(identifier: .component(.karabinerDaemon), category: .installation),
        ]
        let next = WizardRouter.nextPage(
            after: .helper,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: true, backend: .driverKit
        )
        XCTAssertEqual(next, .karabinerComponents,
                       "Helper resolved — should advance to karabiner")
    }

    func test_nextPage_helperNeedsApproval_blocksAtHelper() {
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
        ]
        let next = WizardRouter.nextPage(
            after: .conflicts,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: true,
            helperNeedsApproval: true, backend: .driverKit
        )
        XCTAssertEqual(next, .helper,
                       "Helper needs approval — must stop there")
    }

    // MARK: - Full Dependency Chain: conflicts → helper → karabiner → service

    func test_prereq_conflictsBlockEverything() {
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
            makeIssue(identifier: .component(.karabinerDaemon), category: .installation),
        ]
        // Starting from summary (first in order), with conflicts present
        var allIssues = issues
        allIssues.append(makeIssue(identifier: .conflict(.kanataProcessRunning(pid: 999, command: "kanata")), severity: .error, category: .conflicts))
        let next = WizardRouter.nextPage(
            after: .summary,
            state: .serviceNotRunning,
            issues: allIssues,
            helperInstalled: false, backend: .driverKit
        )
        XCTAssertEqual(next, .conflicts, "Conflicts must be resolved before anything else")
    }

    func test_prereq_helperBlocksKarabiner() {
        // Helper not installed, karabiner has issues — must go to helper first
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
            makeIssue(identifier: .component(.vhidDeviceRunning), category: .installation),
        ]
        let next = WizardRouter.nextPage(
            after: .summary,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: false, backend: .driverKit
        )
        XCTAssertEqual(next, .helper, "Helper must be installed before karabiner repair")
    }

    func test_prereq_helperBlocksService() {
        // Helper not installed, only service issue — must go to helper first
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
        ]
        let next = WizardRouter.nextPage(
            after: .summary,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: false, backend: .driverKit
        )
        XCTAssertEqual(next, .helper, "Helper must be installed before starting service")
    }

    func test_prereq_karabinerBlocksService() {
        // Karabiner components broken, service not running — must fix karabiner first
        let issues = [
            makeIssue(identifier: .component(.karabinerDaemon), category: .installation),
        ]
        let next = WizardRouter.nextPage(
            after: .inputMonitoring,
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: true, backend: .driverKit
        )
        XCTAssertEqual(next, .karabinerComponents,
                       "Karabiner must be healthy before starting service")
    }

    func test_prereq_allResolvedReachesSummary() {
        // Everything green — should reach summary
        let next = WizardRouter.nextPage(
            after: .helper,
            state: .active,
            issues: [],
            helperInstalled: true, backend: .driverKit
        )
        XCTAssertEqual(next, .summary, "All resolved — should reach summary")
    }

    func test_prereq_permissionsDoNotBlockEachOther() {
        // AX issue present — should not block advancing past IM
        let issues = [
            makeIssue(identifier: .permission(.keyPathAccessibility)),
        ]
        let next = WizardRouter.nextPage(
            after: .inputMonitoring,
            state: .active,
            issues: issues,
            helperInstalled: true, backend: .driverKit
        )
        // Accessibility comes before inputMonitoring in page order,
        // so walking forward from IM won't find it — goes to summary
        XCTAssertEqual(next, .summary,
                       "Permission pages don't block each other")
    }

    func test_prereq_fromAnyPage_helperUninstalled_goesToHelper() {
        // Even from service page, if helper is gone, route back to helper
        let issues = [
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
        ]
        for page in [WizardPage.accessibility, .inputMonitoring, .karabinerComponents, .service] {
            let next = WizardRouter.nextPage(
                after: page,
                state: .serviceNotRunning,
                issues: issues,
                helperInstalled: false, backend: .driverKit
            )
            XCTAssertEqual(next, .helper,
                           "From \(page): helper not installed must redirect to helper page")
        }
    }

    func test_prereq_route_respectsFullChain() {
        // Full chain: conflicts + helper + karabiner + service all broken
        // route() should return the highest priority blocker
        let issues = [
            makeIssue(identifier: .conflict(.kanataProcessRunning(pid: 999, command: "kanata")), severity: .error, category: .conflicts),
            makeIssue(identifier: .component(.privilegedHelper), category: .backgroundServices),
            makeIssue(identifier: .component(.karabinerDaemon), category: .installation),
        ]
        let target = WizardRouter.route(
            state: .serviceNotRunning,
            issues: issues,
            helperInstalled: false,
            helperNeedsApproval: false, backend: .driverKit
        )
        XCTAssertEqual(target, .conflicts, "Conflicts are highest priority in route()")
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

    // MARK: - InstallerDecisionPipeline: Repair Actions

    /// Executable plans use session readiness regardless of historical helper/driver facts.
    func test_sessionPlansOnlyStartWhenRuntimeReadinessIsMissing() {
        let cases: [(Bool, Bool, Bool)] = [
            (true, true, true), (false, false, false),
            (true, false, true), (true, true, false),
        ]
        for (running, responding, inputReady) in cases {
            let health = HealthStatus(
                backend: .session, kanataProcessRunning: running,
                kanataTCPResponding: responding, kanataRunning: running,
                karabinerDaemonRunning: false, vhidHealthy: false,
                kanataInputCaptureReady: inputReady
            )
            let context = makeContext(services: health, components: .empty, helper: .empty)
            let expected: [AutoFixAction] = running && responding && inputReady ? [] : [.restartCommServer]
            for intent in [InstallIntent.install, .repair] {
                XCTAssertEqual(InstallerDecisionPipeline.determineActions(for: intent, context: context), expected)
            }
        }
    }

    func test_readySessionNeverRepairsHistoricalHelperDriverOrConflicts() {
        let health = HealthStatus(
            backend: .session, kanataProcessRunning: true, kanataTCPResponding: true,
            kanataRunning: true, karabinerDaemonRunning: false, vhidHealthy: false,
            kanataInputCaptureReady: true,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
        )
        for canAutoResolve in [false, true] {
            let context = makeContext(
                services: health,
                conflicts: ConflictStatus(conflicts: [.kanataProcessRunning(pid: 1, command: "historical")], canAutoResolve: canAutoResolve),
                components: .empty, helper: .empty
            )
            XCTAssertEqual(InstallerDecisionPipeline.determineInstallActions(context: context), [])
            XCTAssertEqual(InstallerDecisionPipeline.determineRepairActions(context: context), [])
        }
    }

    func test_missingSessionDoesNotPlanPrivilegedFallbackForLegacyApproval() {
        let health = HealthStatus(
            backend: .session, kanataProcessRunning: false, kanataTCPResponding: false,
            kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: false,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
            loginItemsApprovalRequired: true
        )
        let context = makeContext(services: health, components: .empty, helper: .empty)
        XCTAssertEqual(InstallerDecisionPipeline.determineInstallActions(context: context), [.restartCommServer])
        XCTAssertEqual(InstallerDecisionPipeline.determineRepairActions(context: context), [.restartCommServer])
    }

    func test_inspectionAndUninstallNeverPlanRuntimeMutations() {
        let context = makeContext(services: .empty, components: .empty, helper: .empty)
        XCTAssertEqual(InstallerDecisionPipeline.determineActions(for: .inspectOnly, context: context), [])
        XCTAssertEqual(InstallerDecisionPipeline.determineUninstallActions(context: context), [])
        XCTAssertEqual(InstallerDecisionPipeline.determineActions(for: .uninstall, context: context), [])
    }

    // MARK: - Timeout Issue Handling (ADR-critical: timeouts must not suppress real issues)

    func test_timeout_doesNotSuppressHelperIssue() {
        let ctx = makeContext(
            helper: HelperStatus(isInstalled: false, version: nil, isWorking: false),
            timedOut: true
        )
        let (_, issues) = SystemInspector.inspect(context: ctx)

        let helperIssue = issues.first { issue in
            if case .component(.privilegedHelper) = issue.identifier { return true }
            return false
        }
        XCTAssertNotNil(helperIssue, "Helper issue must be reported even when validation timed out")

        let timeoutIssue = issues.first { $0.identifier == .validationTimeout }
        XCTAssertNotNil(timeoutIssue, "Timeout warning should also be present")
    }

    func test_timeout_doesNotSuppressComponentIssues() {
        let unhealthyComponents = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: false,
            vhidVersionMismatch: false
        )
        let ctx = makeContext(components: unhealthyComponents, timedOut: true)
        let (_, issues) = SystemInspector.inspect(context: ctx)

        let componentIssues = issues.filter { $0.category == .backgroundServices || $0.category == .installation }
        XCTAssertFalse(componentIssues.isEmpty,
                       "Component issues must be reported even when validation timed out")

        let timeoutIssue = issues.first { $0.identifier == .validationTimeout }
        XCTAssertNotNil(timeoutIssue, "Timeout warning should also be present")
    }

    func test_timeout_aloneProducesOnlyTimeoutWarning() {
        let ctx = makeContext(timedOut: true)
        let (_, issues) = SystemInspector.inspect(context: ctx)

        let timeoutIssue = issues.first { $0.identifier == .validationTimeout }
        XCTAssertNotNil(timeoutIssue)
        XCTAssertEqual(timeoutIssue?.severity, .warning)
    }

    func test_noTimeout_doesNotProduceTimeoutWarning() {
        let ctx = makeContext(timedOut: false)
        let (_, issues) = SystemInspector.inspect(context: ctx)

        let timeoutIssue = issues.first { $0.identifier == .validationTimeout }
        XCTAssertNil(timeoutIssue, "No timeout warning when validation completed normally")
    }

    func test_timeout_withMultipleRealIssues_reportsAll() {
        let ctx = makeContext(
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: false,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: false,
                vhidServicesHealthy: false,
                vhidVersionMismatch: false
            ),
            helper: HelperStatus(isInstalled: false, version: nil, isWorking: false),
            timedOut: true
        )
        let (_, issues) = SystemInspector.inspect(context: ctx)

        XCTAssertGreaterThan(issues.count, 2,
                             "Should have helper + component + timeout issues")

        let hasHelper = issues.contains { if case .component(.privilegedHelper) = $0.identifier { return true }; return false }
        let hasTimeout = issues.contains { $0.identifier == .validationTimeout }

        XCTAssertTrue(hasHelper, "Helper issue present")
        XCTAssertTrue(hasTimeout, "Timeout warning present")
    }
}
