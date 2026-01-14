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
        let hasBlockingPermissionIssue: (IssueIdentifier) -> Bool = { identifier in
            issues.contains { issue in
                guard issue.severity == .error || issue.severity == .critical else { return false }
                return issue.identifier == identifier
            }
        }
        let hasComponentIssue: (ComponentRequirement) -> Bool = { component in
            issues.contains { issue in
                if case let .component(comp) = issue.identifier {
                    return comp == component
                }
                return false
            }
        }

        // 1. Conflicts (highest priority)
        if issues.contains(where: { $0.category == .conflicts }) {
            return .conflicts
        }

        // 2. Privileged Helper gating
        if helperNeedsApproval { return .helper }
        if !helperInstalled { return .helper }

        // 3. Permissions (blocking only).
        //
        // We intentionally ignore warning/info permission issues here:
        // - Kanata `.unknown` is "not verified" (often no FDA), and should not force the user
        //   into permission pages.
        // - KeyPath `.unknown` during startup mode is "checking" and should not route.
        //
        // Users can still navigate to the permission pages manually from Summary/status rows.
        if hasBlockingPermissionIssue(.permission(.keyPathInputMonitoring))
            || hasBlockingPermissionIssue(.permission(.kanataInputMonitoring)) {
            return .inputMonitoring
        }
        if hasBlockingPermissionIssue(.permission(.keyPathAccessibility))
            || hasBlockingPermissionIssue(.permission(.kanataAccessibility)) {
            return .accessibility
        }

        // 4. Karabiner components (driver/VHID/background services)
        let hasKarabinerIssues = [
            .karabinerDriver,
            .karabinerDaemon,
            .vhidDeviceManager,
            .vhidDeviceActivation,
            .vhidDeviceRunning,
            .launchDaemonServices,
            .vhidDaemonMisconfigured,
            .vhidDriverVersionMismatch
        ].contains { hasComponentIssue($0) }
        if hasKarabinerIssues { return .karabinerComponents }

        // 5. Kanata setup (engine + service + communication)
        let hasKanataIssues = [
            .kanataBinaryMissing,
            .kanataService,
            .launchDaemonServices,
            .launchDaemonServicesUnhealthy,
            .orphanedKanataProcess,
            .communicationServerConfiguration,
            .communicationServerNotResponding,
            .tcpServerConfiguration,
            .tcpServerNotResponding
        ].contains { hasComponentIssue($0) }
        if hasKanataIssues { return .kanataComponents }

        // 6. Service readiness (finalize on Kanata setup page)
        switch state {
        case .serviceNotRunning, .ready, .daemonNotRunning:
            return .kanataComponents
        default:
            break
        }

        // 8. Default to summary
        return .summary
    }
}
