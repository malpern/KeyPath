import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Pure, side-effect-free routing function for the wizard.
/// All inputs are immutable values — no async, no dependencies, no hidden state.
public enum WizardRouter {
    // MARK: - Primary Routing

    /// Determine the appropriate page given system state and detected issues.
    public static func route(
        state: WizardSystemState,
        issues: [WizardIssue]
    ) -> WizardPage {
        // 1. Permissions (blocking only — warnings like "not verified" don't route here)
        // Accessibility may already provide effective input access. Resolve it
        // first, then refresh the Oracle before asking for separate IM approval.
        if hasBlockingPermissionIssue(.permission(.keyPathAccessibility), in: issues)
            || hasBlockingPermissionIssue(.permission(.kanataAccessibility), in: issues)
        {
            return .accessibility
        }
        if hasBlockingPermissionIssue(.permission(.keyPathInputMonitoring), in: issues)
            || hasBlockingPermissionIssue(.permission(.kanataInputMonitoring), in: issues)
        {
            return .inputMonitoring
        }

        // 2. Service readiness
        switch state {
        case .serviceNotRunning, .ready:
            return .service
        default:
            break
        }

        // 3. Default to summary
        return .summary
    }

    /// Adjust a routing decision when kanata's permission state could not be
    /// verified through available runtime permission evidence.
    ///
    /// Unverified permissions produce only warning-severity issues, which
    /// `route()` deliberately ignores — but auto-advancing past the permission
    /// pages would start the service and trigger both system permission dialogs
    /// at once. Land on the first unverified permission page so the user sees the
    /// "not verified — add manually" guidance instead of parking on summary.
    public static func routeForUnverifiedKanataPermissions(
        base: WizardPage,
        inputMonitoringUnknown: Bool,
        accessibilityUnknown: Bool
    ) -> WizardPage {
        switch base {
        case .inputMonitoring, .accessibility:
            return base
        default:
            if accessibilityUnknown { return .accessibility }
            if inputMonitoringUnknown { return .inputMonitoring }
            return base
        }
    }

    // MARK: - Next Page (skipping resolved pages)

    /// Find the next page that needs attention after the current one.
    public static func nextPage(
        after current: WizardPage,
        state: WizardSystemState,
        issues: [WizardIssue]
    ) -> WizardPage {
        // Walk forward, skipping resolved pages
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
        case .service:
            switch state {
            case .serviceNotRunning, .ready:
                true
            default:
                false
            }
        case .welcome, .kanataMigration, .stopExternalKanata, .karabinerImport:
            false
        }
    }

    // MARK: - Summary Navigation

    /// Whether the wizard should navigate to summary (system is healthy, no issues).
    public static func shouldNavigateToSummary(
        currentPage: WizardPage,
        state: WizardSystemState,
        issues: [WizardIssue]
    ) -> Bool {
        state == .active && issues.isEmpty && currentPage != .summary
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
}
