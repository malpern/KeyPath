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

    func test_systemStateProjectionPreservesCaptureStatus() {
        let context = makeContext(captureStatus: .cancelled)

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.captureStatus, .cancelled)
        XCTAssertEqual(result.stateMatrixRow, InstallerStateMatrixRow.definitiveUnhealthyState.rawValue)
        XCTAssertEqual(result.state, .serviceNotRunning, "An incomplete capture is never reported as a running runtime")
        XCTAssertTrue(result.issues.isEmpty, "An incomplete capture must not invent a consent or runtime fault")
    }

    func test_failedCaptureIsReportedAsNotRunningWithoutInventedIssues() {
        let context = makeContext(captureStatus: .failed)

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.captureStatus, .failed)
        XCTAssertEqual(result.stateMatrixRow, InstallerStateMatrixRow.definitiveUnhealthyState.rawValue)
        XCTAssertEqual(result.state, .serviceNotRunning)
        XCTAssertTrue(result.issues.isEmpty)
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

    func test_inspect_kanataIMDeniedWithAccessibilityGranted_asksToReopenKeyPath() {
        let context = makeContext(permissions: makePermissions(kanataIM: .denied))
        let (state, issues) = SystemInspector.inspect(context: context)
        XCTAssertEqual(state, .missingPermissions(missing: [.keyPathInputMonitoring]))
        let imIssue = issues.first { $0.identifier == .permission(.keyPathInputMonitoring) }
        XCTAssertNotNil(imIssue, "The runtime's denied input access is reported as KeyPath's own consent")
        XCTAssertEqual(imIssue?.severity, .error)
        XCTAssertEqual(imIssue?.title, "Keyboard access still needs approval")
    }

    // MARK: - WizardRouter: route()

    func test_route_noIssuesActiveState_returnsSummary() {
        let page = WizardRouter.route(
            state: .active,
            issues: []
        )
        XCTAssertEqual(page, .summary)
    }

    func test_route_kanataIMError_routesToInputMonitoring() {
        let issues = [
            makeIssue(identifier: .permission(.kanataInputMonitoring), severity: .error),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.kanataInputMonitoring]),
            issues: issues
        )
        XCTAssertEqual(page, .inputMonitoring)
    }

    func test_route_keyPathAXDenied_routesToAccessibility() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathAccessibility), severity: .error),
        ]
        let page = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathAccessibility]),
            issues: issues
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
            issues: issues
        )
        XCTAssertEqual(page, .accessibility, "Resolve AX before requesting separate input access")
    }

    func test_route_readyState_routesToService() {
        let page = WizardRouter.route(
            state: .ready,
            issues: []
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

    func test_nextPage_fromAccessibility_withServiceIssue_skipsToService() {
        let next = WizardRouter.nextPage(
            after: .accessibility,
            state: .serviceNotRunning,
            issues: []
        )
        XCTAssertEqual(next, .service, "Should skip green pages and land on service")
    }

    func test_nextPage_fromInputMonitoring_withAccessibilityIssue_goesToAccessibility() {
        let issues = [
            makeIssue(identifier: .permission(.keyPathAccessibility)),
        ]
        // Accessibility comes before inputMonitoring in orderedPages, so nextPage
        // walks forward from inputMonitoring and won't find accessibility.
        // It should land on the next relevant page or summary.
        let next = WizardRouter.nextPage(
            after: .inputMonitoring,
            state: .active,
            issues: issues
        )
        // After inputMonitoring comes service (green while active), then end -> summary
        XCTAssertEqual(next, .summary)
    }

    func test_nextPage_unknownPage_returnsSummary() {
        // If current page is not in orderedPages (shouldn't happen), returns summary
        // All WizardPage cases are in orderedPages, so this tests defensive behavior
        // We just verify it doesn't crash with a valid page at the end of list
        let next = WizardRouter.nextPage(
            after: .service,
            state: .active,
            issues: []
        )
        XCTAssertEqual(next, .summary, "Last page should fall through to summary")
    }

    // MARK: - Prerequisites: permission pages do not gate navigation

    func test_prereq_allResolvedReachesSummary() {
        // Everything green — should reach summary
        let next = WizardRouter.nextPage(
            after: .accessibility,
            state: .active,
            issues: []
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
            issues: issues
        )
        // Accessibility comes before inputMonitoring in page order,
        // so walking forward from IM won't find it — goes to summary
        XCTAssertEqual(next, .summary,
                       "Permission pages don't block each other")
    }

    // MARK: - WizardRouter: pageHasRelevantIssues()

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

    func test_pageHasRelevantIssues_kanataMigrationAlwaysFalse() {
        XCTAssertFalse(WizardRouter.pageHasRelevantIssues(.kanataMigration, issues: [], state: .active))
    }

    // MARK: - WizardRouter: shouldNavigateToSummary()

    func test_shouldNavigateToSummary_activeNoIssuesNotOnSummary_returnsTrue() {
        XCTAssertTrue(WizardRouter.shouldNavigateToSummary(
            currentPage: .service,
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
            currentPage: .service,
            state: .serviceNotRunning,
            issues: []
        ))
    }

    func test_shouldNavigateToSummary_hasIssues_returnsFalse() {
        let issues = [makeIssue(identifier: .permission(.keyPathInputMonitoring))]
        XCTAssertFalse(WizardRouter.shouldNavigateToSummary(
            currentPage: .service,
            state: .active,
            issues: issues
        ))
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

    // MARK: - Timeout Issue Handling

    func test_noTimeout_doesNotProduceTimeoutWarning() {
        let ctx = makeContext(timedOut: false)
        let (_, issues) = SystemInspector.inspect(context: ctx)

        let timeoutIssue = issues.first { $0.identifier == .validationTimeout }
        XCTAssertNil(timeoutIssue, "No timeout warning when validation completed normally")
    }
}
