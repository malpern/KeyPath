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
    // Post-action verification rows. These are produced by explicit repair
    // action reports, not by a passive live/wizard system snapshot.
    case helperPathSucceeds = "Helper path succeeds"
    case sudoFallbackSucceeds = "Sudo fallback succeeds"
    case manualApprovalRequired = "Manual approval is required"
    case definitiveUnhealthyState = "Definitive unhealthy state"
}

/// A value captured from system evidence, preserving the difference between
/// "known false" and "not captured".
public enum Evidence<Value: Sendable & Equatable>: Sendable, Equatable {
    case known(Value)
    case unknown
}

public extension Evidence {
    var value: Value? {
        guard case let .known(value) = self else { return nil }
        return value
    }
}

public extension Evidence where Value == Bool {
    static var present: Evidence<Bool> {
        .known(true)
    }

    static var absent: Evidence<Bool> {
        .known(false)
    }

    var isKnownTrue: Bool {
        value == true
    }

    var isKnownFalse: Bool {
        value == false
    }
}

extension Evidence: ExpressibleByBooleanLiteral where Value == Bool {
    public init(booleanLiteral value: Bool) {
        self = .known(value)
    }
}

/// Minimal immutable evidence used by the state-matrix classifier.
///
/// This is intentionally pure and OS-free. `SystemStateProvider` can build this
/// from live evidence in a later slice without changing the classifier contract.
public struct InstallerStateMatrixSnapshot: Sendable, Equatable {
    public var kanataBinaryPresent: Evidence<Bool>
    public var requiredRuntimePayloadPresent: Evidence<Bool>
    public var smAppServiceRegistered: Evidence<Bool>
    public var launchdJobLoaded: Evidence<Bool>
    public var kanataProcessRunning: Evidence<Bool>
    public var kanataTCPResponding: Evidence<Bool>
    public var currentInputCaptureIssue: Evidence<Bool>
    public var staleInputCaptureIssue: Evidence<Bool>
    public var driverKitApprovalPending: Evidence<Bool>
    public var virtualHIDDriverPresent: Evidence<Bool>
    public var virtualHIDPayloadPresent: Evidence<Bool>
    public var virtualHIDServicesHealthy: Evidence<Bool>
    public var virtualHIDApprovalPending: Evidence<Bool>
    public var helperInstalled: Evidence<Bool>
    public var helperResponding: Evidence<Bool>
    public var helperFresh: Evidence<Bool>
    public var helperPathReportedSuccess: Evidence<Bool>
    public var sudoFallbackReportedSuccess: Evidence<Bool>
    public var manualApprovalRequired: Evidence<Bool>
    public var definitiveUnhealthyState: Evidence<Bool>

    public init(
        kanataBinaryPresent: Evidence<Bool>,
        requiredRuntimePayloadPresent: Evidence<Bool>,
        smAppServiceRegistered: Evidence<Bool>,
        launchdJobLoaded: Evidence<Bool>,
        kanataProcessRunning: Evidence<Bool>,
        kanataTCPResponding: Evidence<Bool>,
        currentInputCaptureIssue: Evidence<Bool>,
        staleInputCaptureIssue: Evidence<Bool>,
        driverKitApprovalPending: Evidence<Bool>,
        virtualHIDDriverPresent: Evidence<Bool>,
        virtualHIDPayloadPresent: Evidence<Bool>,
        virtualHIDServicesHealthy: Evidence<Bool>,
        virtualHIDApprovalPending: Evidence<Bool>,
        helperInstalled: Evidence<Bool>,
        helperResponding: Evidence<Bool>,
        helperFresh: Evidence<Bool>,
        helperPathReportedSuccess: Evidence<Bool>,
        sudoFallbackReportedSuccess: Evidence<Bool>,
        manualApprovalRequired: Evidence<Bool>,
        definitiveUnhealthyState: Evidence<Bool>
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
        kanataProcessRunning.isKnownTrue && kanataTCPResponding.isKnownTrue
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
        let runtimeUsable = snapshot.runtimeReady && !snapshot.currentInputCaptureIssue.isKnownTrue

        if snapshot.manualApprovalRequired.isKnownTrue, !runtimeUsable {
            return .manualApprovalRequired
        }

        if snapshot.helperPathReportedSuccess.isKnownTrue {
            return .helperPathSucceeds
        }

        if snapshot.sudoFallbackReportedSuccess.isKnownTrue {
            return .sudoFallbackSucceeds
        }

        if snapshot.definitiveUnhealthyState.isKnownTrue {
            return .definitiveUnhealthyState
        }

        if !snapshot.kanataBinaryPresent.isKnownTrue ||
            !snapshot.requiredRuntimePayloadPresent.isKnownTrue ||
            !snapshot.virtualHIDDriverPresent.isKnownTrue
        {
            return .freshInstallMissingComponents
        }

        if !snapshot.smAppServiceRegistered.isKnownTrue {
            return .kanataNotRegistered
        }

        if snapshot.smAppServiceRegistered.isKnownTrue, !snapshot.launchdJobLoaded.isKnownTrue {
            return .registeredButNotLoaded
        }

        if snapshot.launchdJobLoaded.isKnownTrue, !snapshot.kanataProcessRunning.isKnownTrue {
            if snapshot.driverKitApprovalPending.isKnownTrue, snapshot.virtualHIDDriverPresent.isKnownTrue {
                return .driverKitApprovalPendingWithKanataStopped
            }

            if snapshot.staleInputCaptureIssue.isKnownTrue {
                return .staleInputCaptureIssueWithKanataStopped
            }

            return .loadedButNotRunning
        }

        if snapshot.kanataProcessRunning.isKnownTrue, !snapshot.kanataTCPResponding.isKnownTrue {
            return .runningButTCPNotResponding
        }

        if snapshot.virtualHIDApprovalPending.isKnownTrue {
            return .virtualHIDApprovalPending
        }

        if snapshot.runtimeReady, snapshot.currentInputCaptureIssue.isKnownTrue {
            return .runningButInputCaptureFailing
        }

        if !snapshot.virtualHIDPayloadPresent.isKnownTrue {
            return .virtualHIDDriverPayloadMissing
        }

        if !snapshot.virtualHIDServicesHealthy.isKnownTrue {
            return .vhidServicesMissingUnhealthy
        }

        if !snapshot.helperInstalled.isKnownTrue || !snapshot.helperResponding.isKnownTrue {
            return .helperMissing
        }

        if snapshot.helperResponding.isKnownTrue, !snapshot.helperFresh.isKnownTrue {
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
        let kanataProcessRunning = services.kanataProcessRunning.map(Evidence<Bool>.known) ?? .unknown
        let kanataTCPResponding = services.kanataTCPResponding.map(Evidence<Bool>.known) ?? .unknown
        let launchdJobLoaded: Evidence<Bool> = if services.staleEnabledRegistration {
            .absent
        } else if let kanataLaunchdLoaded = services.kanataLaunchdLoaded {
            .known(kanataLaunchdLoaded)
        } else {
            .unknown
        }
        let inputCaptureIssuePresent = !services.kanataInputCaptureReady
        let staleInputCaptureIssue: Evidence<Bool> = if let kanataProcessRunning = services.kanataProcessRunning {
            .known(!kanataProcessRunning
                && inputCaptureIssuePresent
                && !driverKitApprovalPending)
        } else {
            .unknown
        }
        let currentInputCaptureIssue: Evidence<Bool> = if let kanataProcessRunning = services.kanataProcessRunning,
                                                          let kanataTCPResponding = services.kanataTCPResponding
        {
            .known(kanataProcessRunning && kanataTCPResponding && inputCaptureIssuePresent)
        } else {
            .unknown
        }

        return InstallerStateMatrixSnapshot(
            kanataBinaryPresent: .known(components.kanataBinaryInstalled),
            requiredRuntimePayloadPresent: .known(components.requiredRuntimePayloadPresent),
            smAppServiceRegistered: services.kanataSMAppServiceRegistered.map(Evidence<Bool>.known) ?? .unknown,
            launchdJobLoaded: launchdJobLoaded,
            kanataProcessRunning: kanataProcessRunning,
            kanataTCPResponding: kanataTCPResponding,
            currentInputCaptureIssue: currentInputCaptureIssue,
            staleInputCaptureIssue: staleInputCaptureIssue,
            driverKitApprovalPending: .known(driverKitApprovalPending),
            virtualHIDDriverPresent: .known(components.karabinerDriverInstalled),
            virtualHIDPayloadPresent: .known(components.vhidDeviceInstalled),
            virtualHIDServicesHealthy: .known(!components.vhidRuntimeServicesNeedRepair),
            virtualHIDApprovalPending: .known(driverKitApprovalPending),
            helperInstalled: .known(helper.isInstalled),
            helperResponding: .known(helper.isWorking),
            helperFresh: .known(helper.version == WizardHelperConstants.expectedHelperVersion),
            helperPathReportedSuccess: .absent,
            sudoFallbackReportedSuccess: .absent,
            manualApprovalRequired: services.loginItemsApprovalRequired.map(Evidence<Bool>.known) ?? .unknown,
            definitiveUnhealthyState: .known(!captureStatus.isComplete)
        )
    }

    var installerStateMatrixRow: InstallerStateMatrixRow {
        InstallerStateMatrixPlanner.classify(installerStateMatrixSnapshot)
    }

    var installerStateMatrixPlan: [InstallerStateMatrixAction] {
        InstallerStateMatrixPlanner.plan(for: installerStateMatrixSnapshot)
    }
}
