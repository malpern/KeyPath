@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
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

    func testStateMatrixSnapshotMapsLoginItemsApprovalToManualApprovalRow() {
        let snapshot = SystemStateProvider.installerStateMatrixSnapshot(
            components: healthyComponents,
            helper: healthyHelper,
            runtime: runtime(),
            kanataSMAppServiceStatus: .enabled,
            helperSMAppServiceStatus: .requiresApproval
        )

        XCTAssertEqual(InstallerStateMatrixPlanner.classify(snapshot), .manualApprovalRequired)
        XCTAssertEqual(InstallerStateMatrixPlanner.plan(for: snapshot), [.surfaceManualApproval])
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
