@testable import KeyPathAppKit
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class DriverlessSettingsStatusTests: XCTestCase {
    func testDriverlessStatusDoesNotClaimUnperformedChecksPassed() {
        let rows = SettingsSystemStatusRowsBuilder.rows(wizardSystemState: .initializing, wizardIssues: [], systemContext: nil)
        XCTAssertEqual(rows.map(\.id), ["kanata-service"])
        XCTAssertEqual(rows.first?.title, "Keyboard remapping")
        XCTAssertEqual(rows.first?.status, .inProgress)
    }

    func testCombinedPermissionsNeverHideRuntimeFailureOrUncertainty() {
        XCTAssertEqual(SettingsPermissionSummary.combine(.granted, .denied), .denied)
        XCTAssertEqual(SettingsPermissionSummary.combine(.denied, .granted), .denied)
        XCTAssertEqual(SettingsPermissionSummary.combine(.granted, nil), .unknown)
        XCTAssertEqual(SettingsPermissionSummary.combine(.unknown, .granted), .unknown)
        XCTAssertEqual(SettingsPermissionSummary.combine(.granted, .error("probe failed")), .error("probe failed"))
        XCTAssertEqual(SettingsPermissionSummary.combine(.granted, .granted), .granted)
    }

    /// Turning remapping off with the Status switch is a choice, not a fault: the
    /// row must not go red or tell the user to start what they just stopped.
    func testIntentionallyOffShowsNeutralRowNotAFailure() {
        let rows = SettingsSystemStatusRowsBuilder.rows(
            wizardSystemState: .serviceNotRunning, wizardIssues: [], systemContext: nil,
            intentionallyOff: true
        )
        let service = rows.first { $0.id == "kanata-service" }
        XCTAssertEqual(service?.status, .notStarted)
        XCTAssertEqual(service?.message, "Turned off")
        XCTAssertNotEqual(service?.status, .failed)
    }
}
