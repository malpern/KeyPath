@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

/// Routing when kanata's permissions are unverifiable (.unknown after retries).
/// Unknown permissions produce only warning-severity issues, which route()
/// ignores — routeForUnverifiedKanataPermissions must land the wizard on the
/// first unverified permission page instead of dead-ending on summary, while
/// never overriding higher-priority blocking pages (conflicts/helper).
@MainActor
final class WizardRouterUnverifiedPermissionsTests: XCTestCase {
    func testUnknownAccessibilityComesBeforeInputMonitoring() {
        let page = WizardRouter.routeForUnverifiedKanataPermissions(
            base: .summary,
            inputMonitoringUnknown: true,
            accessibilityUnknown: true
        )
        XCTAssertEqual(page, .accessibility, "Resolve AX before asking for separate input access")
    }

    func testUnknownAccessibilityOnlyOverridesToAccessibility() {
        let page = WizardRouter.routeForUnverifiedKanataPermissions(
            base: .service,
            inputMonitoringUnknown: false,
            accessibilityUnknown: true
        )
        XCTAssertEqual(page, .accessibility)
    }

    func testNoUnknownPermissionsLeavesBaseUntouched() {
        let page = WizardRouter.routeForUnverifiedKanataPermissions(
            base: .service,
            inputMonitoringUnknown: false,
            accessibilityUnknown: false
        )
        XCTAssertEqual(page, .service)
    }

    func testBlockingPagesAreNeverOverridden() {
        for base in [WizardPage.conflicts, .helper, .inputMonitoring, .accessibility] {
            let page = WizardRouter.routeForUnverifiedKanataPermissions(
                base: base,
                inputMonitoringUnknown: true,
                accessibilityUnknown: true
            )
            XCTAssertEqual(page, base, "\(base) must keep priority over unverified permissions")
        }
    }

    func testUnknownPermissionsDoNotAdvancePastPermissionPages() {
        // End-to-end shape of the dead-end fix: route() with only warning-severity
        // "not verified" issues would pick a post-permission page; the override
        // must pull it back to the permission page.
        let warningIssues = [WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .warning,
            category: .permissions,
            title: "Kanata Engine Input Monitoring Permission",
            description: "Not verified",
            autoFixAction: nil,
            userAction: nil
        )]
        let base = WizardRouter.route(
            state: .serviceNotRunning,
            issues: warningIssues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(base, .service, "warning-severity permission issues don't route on their own")

        let page = WizardRouter.routeForUnverifiedKanataPermissions(
            base: base,
            inputMonitoringUnknown: true,
            accessibilityUnknown: false
        )
        XCTAssertEqual(page, .inputMonitoring)
    }

    func testDeniedAccessibilityComesBeforeDeniedInputMonitoring() {
        let issues = [PermissionRequirement.kanataInputMonitoring, .kanataAccessibility].map {
            WizardIssue(identifier: .permission($0), severity: .error, category: .permissions,
                        title: "Permission", description: "Denied", autoFixAction: nil, userAction: nil)
        }
        XCTAssertEqual(WizardRouter.route(state: .serviceNotRunning, issues: issues,
                                          helperInstalled: true, helperNeedsApproval: false), .accessibility)
    }
}
