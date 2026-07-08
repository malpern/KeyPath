@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
@testable import KeyPathWizardCore
import ServiceManagement
@preconcurrency import XCTest

final class SystemStateProviderInstallerStateMatrixTests: XCTestCase {
    func testStateMatrixSnapshotPreservesRunningButTCPNotRespondingEvidence() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime(isRunning: true, isResponding: false),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .runningButTCPNotResponding)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.restartOrRecoverKanataRuntime])
    }

    func testStateMatrixSnapshotMapsStaleEnabledRegistrationToRegisteredButNotLoaded() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime(
                isRunning: false,
                isResponding: false,
                launchctlExitCode: 113,
                staleEnabledRegistration: true
            ),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .registeredButNotLoaded)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.recoverRuntimeRegistrationBypassingThrottle])
    }

    func testStateMatrixSnapshotMapsStoppedDriverKitApprovalToManualDriverKitRow() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime(
                isRunning: false,
                isResponding: false,
                inputCaptureReady: false,
                inputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
            ),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .driverKitApprovalPendingWithKanataStopped)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.surfaceDriverKitApproval])
    }

    func testStateMatrixSnapshotMapsStoppedRuntimeWithLoginItemsApprovalToManualApprovalRow() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime(isRunning: false, isResponding: false),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .requiresApproval
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .manualApprovalRequired)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.surfaceManualApproval])
    }

    func testStateMatrixSnapshotKeepsReadyRuntimeHealthyWhenLoginItemsApprovalIsStale() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime(),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .requiresApproval
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .runningAndTCPResponding)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [])
    }

    func testStateMatrixSnapshotMapsHelperVersionMismatchToStaleHelperRow() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: HelperStatus(isInstalled: true, version: "0.9.0", isWorking: true),
            runtime: runtime(),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .helperRespondsButMayBeStale)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.verifyOrRefreshHelper])
    }

    func testStateMatrixSnapshotTreatsUnknownHelperVersionAsNotFresh() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: HelperStatus(isInstalled: true, version: nil, isWorking: true),
            runtime: runtime(),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .helperRespondsButMayBeStale)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.verifyOrRefreshHelper])
    }

    func testStateMatrixSnapshotTreatsUnhealthyVHIDServicesAsServiceRepairNotMissingPayload() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: false,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: false,
                vhidVersionMismatch: false
            ),
            helper: healthyHelper,
            runtime: runtime(),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .vhidServicesMissingUnhealthy)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.repairVHIDServices])
    }

    func testWizardSystemContextSnapshotPreservesRunningButTCPNotRespondingEvidence() {
        assertWizardAndProviderClassifySameRuntimeEvidence(
            runtime: runtime(isRunning: true, isResponding: false),
            expectedRow: .runningButTCPNotResponding,
            expectedPlan: [.restartOrRecoverKanataRuntime]
        )
    }

    func testWizardSystemContextSnapshotPreservesRunningButInputCaptureFailingEvidence() {
        assertWizardAndProviderClassifySameRuntimeEvidence(
            runtime: runtime(
                isRunning: true,
                isResponding: true,
                inputCaptureReady: false,
                inputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason
            ),
            expectedRow: .runningButInputCaptureFailing,
            expectedPlan: [.repairVHIDActivationServices]
        )
    }

    func testWizardSystemContextSnapshotPreservesStaleEnabledRegistrationEvidence() {
        assertWizardAndProviderClassifySameRuntimeEvidence(
            runtime: runtime(
                isRunning: false,
                isResponding: false,
                launchctlExitCode: 113,
                staleEnabledRegistration: true
            ),
            expectedRow: .registeredButNotLoaded,
            expectedPlan: [.recoverRuntimeRegistrationBypassingThrottle]
        )
    }

    func testWizardSystemContextSnapshotTreatsUnknownHelperVersionAsNotFresh() {
        let snapshot = systemContext(
            from: runtime(),
            helper: HelperStatus(isInstalled: true, version: nil, isWorking: true)
        ).installerStateMatrixSnapshot

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .helperRespondsButMayBeStale)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.verifyOrRefreshHelper])
    }

    private var healthyComponents: ComponentStatus {
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

    private var healthyHelper: HelperStatus {
        HelperStatus(isInstalled: true, version: "1.0.0", isWorking: true)
    }

    private func assertWizardAndProviderClassifySameRuntimeEvidence(
        runtime: ServiceHealthChecker.KanataServiceRuntimeSnapshot,
        expectedRow: InstallerStateMatrixRow,
        expectedPlan: [InstallerStateMatrixAction],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let providerSnapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime,
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .enabled
        )
        let wizardSnapshot = systemContext(from: runtime).installerStateMatrixSnapshot

        XCTAssertEqual(wizardSnapshot, providerSnapshot, file: file, line: line)
        XCTAssertEqual(InstallerStateMatrixPlanner.classify(wizardSnapshot), expectedRow, file: file, line: line)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: wizardSnapshot), expectedPlan, file: file, line: line)
    }

    private func systemContext(
        from runtime: ServiceHealthChecker.KanataServiceRuntimeSnapshot,
        helper: HelperStatus? = nil
    ) -> SystemContext {
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
        let runtimeReady = runtime.isRunning && runtime.isResponding && runtime.inputCaptureReady
        let launchdJobLoaded = !runtime.staleEnabledRegistration &&
            (runtime.launchctlExitCode == 0 || runtime.isRunning)

        return SystemContext(
            permissions: permissions,
            services: HealthStatus(
                kanataLaunchdLoaded: launchdJobLoaded,
                kanataProcessRunning: runtime.isRunning,
                kanataTCPResponding: runtime.isResponding,
                kanataRunning: runtimeReady,
                karabinerDaemonRunning: true,
                vhidHealthy: true,
                kanataInputCaptureReady: runtime.inputCaptureReady,
                kanataInputCaptureIssue: runtime.inputCaptureIssue,
                staleEnabledRegistration: runtime.staleEnabledRegistration
            ),
            conflicts: .empty,
            components: healthyComponents,
            helper: helper ?? healthyHelper,
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: Date()
        )
    }

    private func runtime(
        isRunning: Bool = true,
        isResponding: Bool = true,
        inputCaptureReady: Bool = true,
        inputCaptureIssue: String? = nil,
        launchctlExitCode: Int32? = 0,
        staleEnabledRegistration: Bool = false
    ) -> ServiceHealthChecker.KanataServiceRuntimeSnapshot {
        ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: isRunning,
            isResponding: isResponding,
            inputCaptureReady: inputCaptureReady,
            inputCaptureIssue: inputCaptureIssue,
            launchctlExitCode: launchctlExitCode,
            staleEnabledRegistration: staleEnabledRegistration,
            recentlyRestarted: false
        )
    }
}
