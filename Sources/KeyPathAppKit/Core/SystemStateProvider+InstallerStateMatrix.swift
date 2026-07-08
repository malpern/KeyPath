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
            kanataBinaryPresent: components.kanataBinaryInstalled,
            requiredRuntimePayloadPresent: true,
            smAppServiceRegistered: smAppServiceRegistered,
            launchdJobLoaded: launchdJobLoaded,
            kanataProcessRunning: runtime.isRunning,
            kanataTCPResponding: runtime.isResponding,
            currentInputCaptureIssue: runtime.isRunning && runtime.isResponding && !runtime.inputCaptureReady,
            staleInputCaptureIssue: !runtime.isRunning && !runtime.inputCaptureReady && !driverKitApprovalPending,
            driverKitApprovalPending: driverKitApprovalPending,
            virtualHIDDriverPresent: components.karabinerDriverInstalled,
            virtualHIDPayloadPresent: components.vhidDeviceInstalled,
            virtualHIDServicesHealthy: components.vhidServicesHealthy,
            virtualHIDApprovalPending: driverKitApprovalPending,
            helperInstalled: helper.isInstalled,
            helperResponding: helper.isWorking,
            helperFresh: helper.version == nil || helper.version == HelperManager.expectedHelperVersion,
            manualApprovalRequired: loginItemsApprovalRequired
        )
    }
}
