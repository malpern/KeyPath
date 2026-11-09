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
        // Accessibility is the only permission. A runtime that still lacks key
        // access after it is granted needs a relaunch, explained on the same page.
        if hasBlockingPermissionIssue(.permission(.keyPathAccessibility), in: issues)
            || hasBlockingPermissionIssue(.permission(.runtimeKeyAccess), in: issues)
        {
            return .accessibility
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

    /// Adjust a routing decision when permissions could not be verified: KeyPath's
    /// Accessibility is unknown or no runtime has reported key access. Unverified
    /// permissions produce no blocking issue, but auto-advancing past the
    /// permission page would start the service before the user saw the grant step.
    public static func routeForUnverifiedPermissions(
        base: WizardPage,
        permissionsUnverified: Bool
    ) -> WizardPage {
        if base == .accessibility { return base }
        return permissionsUnverified ? .accessibility : base
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
        case .accessibility:
            issues.contains { $0.identifier.isPermission }
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
