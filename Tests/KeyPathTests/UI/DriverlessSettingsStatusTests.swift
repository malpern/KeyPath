@testable import KeyPathAppKit
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

final class DriverlessSettingsStatusTests: XCTestCase {
    func testDriverlessStatusDoesNotClaimUnperformedChecksPassed() {
        let rows = SettingsSystemStatusRowsBuilder.rows(wizardSystemState: .initializing, wizardIssues: [], systemContext: nil, tcpConfigured: true, driverless: true)
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

    func testLegacyStatusRetainsSeparateComponents() {
        let rows = SettingsSystemStatusRowsBuilder.rows(wizardSystemState: .initializing, wizardIssues: [], systemContext: nil, tcpConfigured: nil, driverless: false)
        XCTAssertEqual(rows.map(\.id), ["privileged-helper", "conflicts", "karabiner-components", "kanata-service", "tcp-communication"])
    }
}
