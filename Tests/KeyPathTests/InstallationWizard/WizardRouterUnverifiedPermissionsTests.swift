@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

/// Routing when permissions are unverifiable (.unknown after retries).
/// Unknown permissions produce only warning-severity issues, which route()
/// ignores — routeForUnverifiedPermissions must land the wizard on the
/// permission page instead of dead-ending on summary.
@MainActor
final class WizardRouterUnverifiedPermissionsTests: XCTestCase {
    func testUnverifiedPermissionsOverrideToAccessibility() {
        for base in [WizardPage.summary, .service] {
            let page = WizardRouter.routeForUnverifiedPermissions(base: base, permissionsUnverified: true)
            XCTAssertEqual(page, .accessibility)
        }
    }

    func testVerifiedPermissionsLeaveBaseUntouched() {
        let page = WizardRouter.routeForUnverifiedPermissions(base: .service, permissionsUnverified: false)
        XCTAssertEqual(page, .service)
    }

    func testPermissionPageIsNeverOverridden() {
        let page = WizardRouter.routeForUnverifiedPermissions(base: .accessibility, permissionsUnverified: true)
        XCTAssertEqual(page, .accessibility)
    }

    func testUnknownPermissionsDoNotAdvancePastPermissionPage() {
        // End-to-end shape of the dead-end fix: route() with only warning-severity
        // "not verified" issues would pick a post-permission page; the override
        // must pull it back to the permission page.
        let warningIssues = [WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .warning,
            category: .permissions,
            title: "Keyboard access not verified",
            description: "Not verified",
            autoFixAction: nil,
            userAction: nil
        )]
        let base = WizardRouter.route(
            state: .serviceNotRunning,
            issues: warningIssues
        )
        XCTAssertEqual(base, .service, "warning-severity permission issues don't route on their own")

        let page = WizardRouter.routeForUnverifiedPermissions(base: base, permissionsUnverified: true)
        XCTAssertEqual(page, .accessibility)
    }

    func testDeniedPermissionsRouteToAccessibility() {
        let issues = [PermissionRequirement.runtimeKeyAccess, .keyPathAccessibility].map {
            WizardIssue(identifier: .permission($0), severity: .error, category: .permissions,
                        title: "Permission", description: "Denied", autoFixAction: nil, userAction: nil)
        }
        XCTAssertEqual(WizardRouter.route(state: .serviceNotRunning, issues: issues), .accessibility)
    }
}
