import Foundation
import KeyPathWizardCore

/// Pure, side-effect-free routing function for the wizard.
/// All inputs are immutable values — no async, no dependencies, no hidden state.
public enum WizardRouter {
    // MARK: - Primary Routing

    /// Determine the appropriate page given system state and detected issues.
    public static func route(
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

        // 3. Permissions (blocking only — warnings like "not verified" don't route here)
        if hasBlockingPermissionIssue(.permission(.keyPathInputMonitoring), in: issues)
            || hasBlockingPermissionIssue(.permission(.kanataInputMonitoring), in: issues)
        {
            return .inputMonitoring
        }
        if hasBlockingPermissionIssue(.permission(.keyPathAccessibility), in: issues)
            || hasBlockingPermissionIssue(.permission(.kanataAccessibility), in: issues)
        {
            return .accessibility
        }

        // 4. Communication configuration
        if hasCommunicationIssues(in: issues) { return .communication }

        // 5. Karabiner components (driver/VHID/background services)
        if hasKarabinerIssues(in: issues) { return .karabinerComponents }

        // 6. Service readiness
        switch state {
        case .serviceNotRunning, .ready, .daemonNotRunning:
            return .service
        default:
            break
        }

        // 7. Default to summary
        return .summary
    }

    // MARK: - Next Page (skipping resolved pages)

    /// Find the next page that needs attention after the current one.
    /// Walks forward through the page order, skipping pages with no relevant issues.
    public static func nextPage(
        after current: WizardPage,
        state: WizardSystemState,
        issues: [WizardIssue]
    ) -> WizardPage {
        let pageOrder = WizardPage.orderedPages
        guard let currentIndex = pageOrder.firstIndex(of: current) else {
            return .summary
        }

        var candidateIndex = currentIndex + 1
        while candidateIndex < pageOrder.count {
            let candidate = pageOrder[candidateIndex]
            if candidate == .summary || pageHasRelevantIssues(candidate, issues: issues, state: state) {
                return candidate
            }
            candidateIndex += 1
        }

        return .summary
    }

    // MARK: - Page Relevance

    /// Whether a page has issues that need user attention.
    /// Pages with no relevant issues are "green" and can be skipped during navigation.
    public static func pageHasRelevantIssues(
        _ page: WizardPage,
        issues: [WizardIssue],
        state: WizardSystemState
    ) -> Bool {
        switch page {
        case .summary:
            true
        case .conflicts:
            issues.contains { $0.category == .conflicts }
        case .helper:
            issues.contains { issue in
                if case let .component(req) = issue.identifier {
                    return req == .privilegedHelper || req == .privilegedHelperUnhealthy
                }
                return false
            }
        case .inputMonitoring:
            issues.contains { issue in
                if case let .permission(perm) = issue.identifier {
                    return perm == .keyPathInputMonitoring || perm == .kanataInputMonitoring
                }
                return false
            }
        case .accessibility:
            issues.contains { issue in
                if case let .permission(perm) = issue.identifier {
                    return perm == .keyPathAccessibility || perm == .kanataAccessibility
                }
                return false
            }
        case .communication:
            hasCommunicationIssues(in: issues)
        case .karabinerComponents:
            hasKarabinerIssues(in: issues)
        case .service:
            switch state {
            case .serviceNotRunning, .ready, .daemonNotRunning:
                true
            default:
                false
            }
        case .fullDiskAccess, .kanataMigration, .stopExternalKanata, .karabinerImport:
            false
        }
    }

    // MARK: - Blocking Pages

    /// Whether a page represents a blocking issue that must be resolved before proceeding.
    public static func isBlockingPage(
        _ page: WizardPage,
        helperInstalled: Bool,
        helperNeedsApproval: Bool
    ) -> Bool {
        switch page {
        case .conflicts, .karabinerComponents:
            true
        case .helper:
            !helperInstalled || helperNeedsApproval
        default:
            false
        }
    }

    // MARK: - Private Helpers

    private static func hasBlockingPermissionIssue(
        _ identifier: IssueIdentifier,
        in issues: [WizardIssue]
    ) -> Bool {
        issues.contains { issue in
            guard issue.severity == .error || issue.severity == .critical else { return false }
            return issue.identifier == identifier
        }
    }

    private static func hasCommunicationIssues(in issues: [WizardIssue]) -> Bool {
        issues.contains {
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
    }

    private static func hasKarabinerIssues(in issues: [WizardIssue]) -> Bool {
        issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.vhidDaemonMisconfigured),
                     .component(.vhidDriverVersionMismatch):
                    return true
                default:
                    return false
                }
            }
            return false
        }
    }
}
