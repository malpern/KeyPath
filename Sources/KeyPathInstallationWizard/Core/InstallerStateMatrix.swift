import Foundation
import KeyPathWizardCore

/// Rows from `docs/process/installer-repair-state-matrix.md`.
public enum InstallerStateMatrixRow: String, CaseIterable, Sendable, Equatable {
    case freshInstallMissingComponents = "Fresh install, missing components"
    case kanataNotRegistered = "Kanata not registered"
    case registeredButNotLoaded = "Registered but not loaded"
    case loadedButNotRunning = "Loaded but not running"
    case runningButTCPNotResponding = "Running but TCP not responding"
    case runningAndTCPResponding = "Running and TCP responding"
    case runningButInputCaptureFailing = "Running but input capture failing"
    case staleInputCaptureIssueWithKanataStopped = "Stale/non-approval input-capture issue with Kanata stopped"
    case driverKitApprovalPendingWithKanataStopped = "DriverKit approval pending with Kanata stopped"
    case virtualHIDDriverPayloadMissing = "VirtualHID driver payload missing"
    case vhidServicesMissingUnhealthy = "VHID services missing/unhealthy"
    case virtualHIDApprovalPending = "VirtualHID approval pending"
    case helperMissing = "Helper missing"
    case helperRespondsButMayBeStale = "Helper responds but may be stale"
    case helperPathSucceeds = "Helper path succeeds"
    case sudoFallbackSucceeds = "Sudo fallback succeeds"
    case manualApprovalRequired = "Manual approval is required"
    case definitiveUnhealthyState = "Definitive unhealthy state"
}

/// Minimal immutable evidence used by the state-matrix classifier.
///
/// This is intentionally pure and OS-free. `SystemStateProvider` can build this
/// from live evidence in a later slice without changing the classifier contract.
public struct InstallerStateMatrixSnapshot: Sendable, Equatable {
    public var kanataBinaryPresent: Bool
    public var requiredRuntimePayloadPresent: Bool
    public var smAppServiceRegistered: Bool
    public var launchdJobLoaded: Bool
    public var kanataProcessRunning: Bool
    public var kanataTCPResponding: Bool
    public var currentInputCaptureIssue: Bool
    public var staleInputCaptureIssue: Bool
    public var driverKitApprovalPending: Bool
    public var virtualHIDDriverPresent: Bool
    public var virtualHIDPayloadPresent: Bool
    public var virtualHIDServicesHealthy: Bool
    public var virtualHIDApprovalPending: Bool
    public var helperInstalled: Bool
    public var helperResponding: Bool
    public var helperFresh: Bool
    public var helperPathReportedSuccess: Bool
    public var sudoFallbackReportedSuccess: Bool
    public var manualApprovalRequired: Bool
    public var definitiveUnhealthyState: Bool

    public init(
        kanataBinaryPresent: Bool = true,
        requiredRuntimePayloadPresent: Bool = true,
        smAppServiceRegistered: Bool = true,
        launchdJobLoaded: Bool = true,
        kanataProcessRunning: Bool = true,
        kanataTCPResponding: Bool = true,
        currentInputCaptureIssue: Bool = false,
        staleInputCaptureIssue: Bool = false,
        driverKitApprovalPending: Bool = false,
        virtualHIDDriverPresent: Bool = true,
        virtualHIDPayloadPresent: Bool = true,
        virtualHIDServicesHealthy: Bool = true,
        virtualHIDApprovalPending: Bool = false,
        helperInstalled: Bool = true,
        helperResponding: Bool = true,
        helperFresh: Bool = true,
        helperPathReportedSuccess: Bool = false,
        sudoFallbackReportedSuccess: Bool = false,
        manualApprovalRequired: Bool = false,
        definitiveUnhealthyState: Bool = false
    ) {
        self.kanataBinaryPresent = kanataBinaryPresent
        self.requiredRuntimePayloadPresent = requiredRuntimePayloadPresent
        self.smAppServiceRegistered = smAppServiceRegistered
        self.launchdJobLoaded = launchdJobLoaded
        self.kanataProcessRunning = kanataProcessRunning
        self.kanataTCPResponding = kanataTCPResponding
        self.currentInputCaptureIssue = currentInputCaptureIssue
        self.staleInputCaptureIssue = staleInputCaptureIssue
        self.driverKitApprovalPending = driverKitApprovalPending
        self.virtualHIDDriverPresent = virtualHIDDriverPresent
        self.virtualHIDPayloadPresent = virtualHIDPayloadPresent
        self.virtualHIDServicesHealthy = virtualHIDServicesHealthy
        self.virtualHIDApprovalPending = virtualHIDApprovalPending
        self.helperInstalled = helperInstalled
        self.helperResponding = helperResponding
        self.helperFresh = helperFresh
        self.helperPathReportedSuccess = helperPathReportedSuccess
        self.sudoFallbackReportedSuccess = sudoFallbackReportedSuccess
        self.manualApprovalRequired = manualApprovalRequired
        self.definitiveUnhealthyState = definitiveUnhealthyState
    }

    public var runtimeReady: Bool {
        kanataProcessRunning && kanataTCPResponding
    }
}

public enum InstallerStateMatrixAction: String, Sendable, Equatable {
    case installMissingComponents = "install-missing-components"
    case installOrRegisterRuntimeServices = "install-or-register-runtime-services"
    case recoverRuntimeRegistrationBypassingThrottle = "recover-runtime-registration-bypassing-throttle"
    case installRequiredRuntimeServices = "install-required-runtime-services"
    case restartOrRecoverKanataRuntime = "restart-or-recover-kanata-runtime"
    case repairVHIDActivationServices = "repair-vhid-activation-services"
    case installVirtualHIDPayload = "install-virtualhid-payload"
    case repairVHIDServices = "repair-vhid-services"
    case installHelper = "install-helper"
    case verifyOrRefreshHelper = "verify-or-refresh-helper"
    case verifyPostconditions = "verify-postconditions"
    case surfaceDriverKitApproval = "surface-driverkit-approval"
    case surfaceVirtualHIDApproval = "surface-virtualhid-approval"
    case surfaceManualApproval = "surface-manual-approval"
    case failWithDiagnostics = "fail-with-diagnostics"
}

public enum InstallerStateMatrixPlanner {
    public static func classify(_ snapshot: InstallerStateMatrixSnapshot) -> InstallerStateMatrixRow {
        let runtimeUsable = snapshot.runtimeReady && !snapshot.currentInputCaptureIssue

        if snapshot.manualApprovalRequired, !runtimeUsable {
            return .manualApprovalRequired
        }

        if snapshot.helperPathReportedSuccess {
            return .helperPathSucceeds
        }

        if snapshot.sudoFallbackReportedSuccess {
            return .sudoFallbackSucceeds
        }

        if snapshot.definitiveUnhealthyState {
            return .definitiveUnhealthyState
        }

        if !snapshot.kanataBinaryPresent ||
            !snapshot.requiredRuntimePayloadPresent ||
            !snapshot.virtualHIDDriverPresent
        {
            return .freshInstallMissingComponents
        }

        if !snapshot.smAppServiceRegistered {
            return .kanataNotRegistered
        }

        if snapshot.smAppServiceRegistered, !snapshot.launchdJobLoaded {
            return .registeredButNotLoaded
        }

        if snapshot.launchdJobLoaded, !snapshot.kanataProcessRunning {
            if snapshot.driverKitApprovalPending, snapshot.virtualHIDDriverPresent {
                return .driverKitApprovalPendingWithKanataStopped
            }

            if snapshot.staleInputCaptureIssue {
                return .staleInputCaptureIssueWithKanataStopped
            }

            return .loadedButNotRunning
        }

        if snapshot.kanataProcessRunning, !snapshot.kanataTCPResponding {
            return .runningButTCPNotResponding
        }

        if snapshot.virtualHIDApprovalPending {
            return .virtualHIDApprovalPending
        }

        if snapshot.runtimeReady, snapshot.currentInputCaptureIssue {
            return .runningButInputCaptureFailing
        }

        if !snapshot.virtualHIDPayloadPresent {
            return .virtualHIDDriverPayloadMissing
        }

        if !snapshot.virtualHIDServicesHealthy {
            return .vhidServicesMissingUnhealthy
        }

        if !snapshot.helperInstalled || !snapshot.helperResponding {
            return .helperMissing
        }

        if snapshot.helperResponding, !snapshot.helperFresh {
            return .helperRespondsButMayBeStale
        }

        return .runningAndTCPResponding
    }

    public static func plan(for row: InstallerStateMatrixRow) -> [InstallerStateMatrixAction] {
        switch row {
        case .freshInstallMissingComponents:
            [.installMissingComponents]
        case .kanataNotRegistered:
            [.installOrRegisterRuntimeServices]
        case .registeredButNotLoaded:
            [.recoverRuntimeRegistrationBypassingThrottle]
        case .loadedButNotRunning:
            [.installRequiredRuntimeServices]
        case .runningButTCPNotResponding:
            [.restartOrRecoverKanataRuntime]
        case .runningAndTCPResponding:
            []
        case .runningButInputCaptureFailing:
            [.repairVHIDActivationServices]
        case .staleInputCaptureIssueWithKanataStopped:
            [.installRequiredRuntimeServices]
        case .driverKitApprovalPendingWithKanataStopped:
            [.surfaceDriverKitApproval]
        case .virtualHIDDriverPayloadMissing:
            [.installVirtualHIDPayload]
        case .vhidServicesMissingUnhealthy:
            [.repairVHIDServices]
        case .virtualHIDApprovalPending:
            [.surfaceVirtualHIDApproval]
        case .helperMissing:
            [.installHelper]
        case .helperRespondsButMayBeStale:
            [.verifyOrRefreshHelper]
        case .helperPathSucceeds, .sudoFallbackSucceeds:
            [.verifyPostconditions]
        case .manualApprovalRequired:
            [.surfaceManualApproval]
        case .definitiveUnhealthyState:
            [.failWithDiagnostics]
        }
    }

    public static func plan(for snapshot: InstallerStateMatrixSnapshot) -> [InstallerStateMatrixAction] {
        plan(for: classify(snapshot))
    }
}

public extension SystemContext {
    var installerStateMatrixSnapshot: InstallerStateMatrixSnapshot {
        let driverKitApprovalPending = requiresManualVHIDDriverApproval
        let kanataProcessRunning = services.kanataProcessRunning ?? services.kanataRunning
        let kanataTCPResponding = services.kanataTCPResponding ?? services.kanataRunning
        let launchdJobLoaded = !services.staleEnabledRegistration && (services.kanataLaunchdLoaded
            ?? (kanataProcessRunning || components.kanataBinaryInstalled))
        let inputCaptureIssuePresent = !services.kanataInputCaptureReady
        let staleInputCaptureIssue = !kanataProcessRunning
            && inputCaptureIssuePresent
            && !driverKitApprovalPending

        return InstallerStateMatrixSnapshot(
            kanataBinaryPresent: components.kanataBinaryInstalled,
            requiredRuntimePayloadPresent: true,
            smAppServiceRegistered: components.kanataBinaryInstalled,
            launchdJobLoaded: launchdJobLoaded,
            kanataProcessRunning: kanataProcessRunning,
            kanataTCPResponding: kanataTCPResponding,
            currentInputCaptureIssue: kanataProcessRunning && kanataTCPResponding && inputCaptureIssuePresent,
            staleInputCaptureIssue: staleInputCaptureIssue,
            driverKitApprovalPending: driverKitApprovalPending,
            virtualHIDDriverPresent: components.karabinerDriverInstalled,
            virtualHIDPayloadPresent: components.vhidDeviceInstalled,
            virtualHIDServicesHealthy: !components.vhidRuntimeServicesNeedRepair,
            virtualHIDApprovalPending: driverKitApprovalPending,
            helperInstalled: helper.isInstalled,
            helperResponding: helper.isWorking,
            helperFresh: helper.version == WizardHelperConstants.expectedHelperVersion,
            definitiveUnhealthyState: timedOut
        )
    }

    var installerStateMatrixRow: InstallerStateMatrixRow {
        InstallerStateMatrixPlanner.classify(installerStateMatrixSnapshot)
    }

    var installerStateMatrixPlan: [InstallerStateMatrixAction] {
        InstallerStateMatrixPlanner.plan(for: installerStateMatrixSnapshot)
    }
}
