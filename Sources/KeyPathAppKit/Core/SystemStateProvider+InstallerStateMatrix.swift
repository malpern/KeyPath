import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore
import ServiceManagement

public extension SystemStateProvider {
    func currentInstallerStateMatrixSnapshot(
        components: ComponentStatus,
        helper: HelperStatus,
        healthChecker: ServiceHealthChecker? = nil,
        tcpPort: Int = KeyPathConstants.Networking.defaultTCPPort
    ) async -> InstallerStateMatrixSnapshot {
        let checker = if let healthChecker {
            healthChecker
        } else {
            await MainActor.run { ServiceHealthChecker.shared }
        }

        async let runtimeSnapshot = checker.checkKanataServiceRuntimeSnapshot(tcpPort: tcpPort)
        async let kanataStatus = cachedSMAppServiceStatus(for: "com.keypath.kanata.plist")
        async let helperStatus = cachedSMAppServiceStatus(for: "com.keypath.helper.plist")

        return await Self.installerStateMatrixSnapshot(
            components: components,
            helper: helper,
            runtime: runtimeSnapshot,
            kanataSMAppServiceStatus: kanataStatus,
            helperSMAppServiceStatus: helperStatus
        )
    }

    static func installerStateMatrixSnapshot(
        components: ComponentStatus,
        helper: HelperStatus,
        runtime: ServiceHealthChecker.KanataServiceRuntimeSnapshot,
        kanataSMAppServiceStatus: SMAppService.Status,
        helperSMAppServiceStatus: SMAppService.Status
    ) -> InstallerStateMatrixSnapshot {
        let driverKitApprovalPending = components.karabinerDriverInstalled
            && !runtime.inputCaptureReady
            && runtime.inputCaptureIssue == ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
        let smAppServiceRegistered = kanataSMAppServiceStatus == .enabled
            || kanataSMAppServiceStatus == .requiresApproval
        let launchdJobLoaded = !runtime.staleEnabledRegistration
            && (runtime.launchctlExitCode == 0 || runtime.isRunning)
        let loginItemsApprovalRequired = kanataSMAppServiceStatus == .requiresApproval
            || helperSMAppServiceStatus == .requiresApproval

        return InstallerStateMatrixSnapshot(
            kanataBinaryPresent: .known(components.kanataBinaryInstalled),
            requiredRuntimePayloadPresent: .known(components.requiredRuntimePayloadPresent),
            smAppServiceRegistered: .known(smAppServiceRegistered),
            launchdJobLoaded: .known(launchdJobLoaded),
            kanataProcessRunning: .known(runtime.isRunning),
            kanataTCPResponding: .known(runtime.isResponding),
            currentInputCaptureIssue: .known(runtime.isRunning && runtime.isResponding && !runtime.inputCaptureReady),
            staleInputCaptureIssue: .known(!runtime.isRunning && !runtime.inputCaptureReady && !driverKitApprovalPending),
            driverKitApprovalPending: .known(driverKitApprovalPending),
            virtualHIDDriverPresent: .known(components.karabinerDriverInstalled),
            virtualHIDPayloadPresent: .known(components.vhidDeviceInstalled),
            virtualHIDServicesHealthy: .known(components.vhidServicesHealthy),
            virtualHIDApprovalPending: .known(driverKitApprovalPending),
            helperInstalled: .known(helper.isInstalled),
            helperResponding: .known(helper.isWorking),
            helperFresh: .known(helper.version == HelperManager.expectedHelperVersion),
            manualApprovalRequired: .known(loginItemsApprovalRequired)
        )
    }
}
