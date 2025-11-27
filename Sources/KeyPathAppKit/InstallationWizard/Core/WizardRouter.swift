import Foundation
import KeyPathWizardCore

/// Pure, side-effect-free routing function for the wizard.
/// Takes only immutable inputs so it can be used by any stack (legacy or new).
enum WizardRouter {
    /// Determine the appropriate page given system state and detected issues.
    /// This intentionally ignores optional pages like Full Disk Access; callers can
    /// apply additional heuristics (e.g., show-once pages) on top.
    static func route(
        state: WizardSystemState,
        issues: [WizardIssue],
        helperInstalled: Bool,
        helperNeedsApproval: Bool
    ) -> WizardPage {
        // 1. Conflicts (highest priority)
        if issues.contains(where: { $0.category == .conflicts }) {
            return .conflicts
        }

        // 2. Privileged Helper gating
        if helperNeedsApproval { return .helper }
        if !helperInstalled { return .helper }

        // 3. Permissions
        let hasInputMonitoringIssues = issues.contains {
            if case let .permission(permissionType) = $0.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        if hasInputMonitoringIssues { return .inputMonitoring }

        let keyPathAXMissing = issues.contains {
            if case let .permission(permissionType) = $0.identifier {
                return permissionType == .keyPathAccessibility
            }
            return false
        }
        if keyPathAXMissing { return .accessibility }

        let kanataPermMissing = issues.contains {
            if case let .permission(permissionType) = $0.identifier {
                return permissionType == .kanataAccessibility || permissionType == .kanataInputMonitoring
            }
            return false
        }
        if kanataPermMissing { return .accessibility }

        // 4. Communication configuration
        let hasCommunicationIssues = issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.communicationServerConfiguration),
                     .component(.communicationServerNotResponding),
                     .component(.tcpServerConfiguration),
                     .component(.tcpServerNotResponding):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasCommunicationIssues { return .communication }

        // 5. Karabiner components (driver/VHID/background services)
        let hasKarabinerIssues = issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.launchDaemonServices),
                     .component(.vhidDaemonMisconfigured),
                     .component(.vhidDriverVersionMismatch):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasKarabinerIssues { return .karabinerComponents }

        // 6. Kanata components (binary/service)
        let hasKanataIssues = issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.kanataBinaryMissing), .component(.kanataService):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasKanataIssues { return .kanataComponents }

        // 7. Service readiness
        switch state {
        case .serviceNotRunning, .ready, .daemonNotRunning:
            return .service
        default:
            break
        }

        // 8. Default to summary
        return .summary
    }
}
