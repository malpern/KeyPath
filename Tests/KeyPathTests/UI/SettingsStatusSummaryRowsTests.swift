@testable import KeyPathAppKit
import KeyPathWizardCore
import ServiceManagement
import XCTest

final class SettingsStatusSummaryRowsTests: XCTestCase {
    private func row(_ id: String, in rows: [SettingsSystemStatusRowModel]) -> SettingsSystemStatusRowModel? {
        rows.first { $0.id == id }
    }

    func testCapsLockIsOnOnlyWhenTheRunningWorkerManagesIt() {
        let on = SettingsStatusSummaryRows.rows(runtimeRunning: true, capsManaged: true, launchAtLogin: .enabled, appCopies: 1)
        XCTAssertEqual(row("caps-lock", in: on)?.status, .completed)

        let unused = SettingsStatusSummaryRows.rows(runtimeRunning: true, capsManaged: false, launchAtLogin: .enabled, appCopies: 1)
        XCTAssertEqual(row("caps-lock", in: unused)?.status, .notStarted)

        // A stopped runtime is reported by the remapping row; Caps Lock must not
        // claim to be on from stale evidence.
        let stopped = SettingsStatusSummaryRows.rows(runtimeRunning: false, capsManaged: true, launchAtLogin: .enabled, appCopies: 1)
        XCTAssertEqual(row("caps-lock", in: stopped)?.status, .notStarted)
    }

    func testLaunchAtLoginReflectsServiceStatus() {
        func status(_ value: SMAppService.Status?) -> SettingsSystemStatusRowModel? {
            row("launch-at-login", in: SettingsStatusSummaryRows.rows(
                runtimeRunning: true, capsManaged: false, launchAtLogin: value, appCopies: 1
            ))
        }
        XCTAssertEqual(status(.enabled)?.status, .completed)
        XCTAssertEqual(status(.requiresApproval)?.status, .warning)
        XCTAssertNotNil(status(.requiresApproval)?.message)
        XCTAssertEqual(status(.notRegistered)?.status, .notStarted)
        XCTAssertEqual(status(nil)?.status, .notStarted)
    }

    func testExtraAppCopiesAppearOnlyWhenPresentAndLinkToRepair() {
        let single = SettingsStatusSummaryRows.rows(runtimeRunning: true, capsManaged: true, launchAtLogin: .enabled, appCopies: 1)
        XCTAssertNil(row("app-copies", in: single))

        let multiple = SettingsStatusSummaryRows.rows(runtimeRunning: true, capsManaged: true, launchAtLogin: .enabled, appCopies: 3)
        XCTAssertEqual(row("app-copies", in: multiple)?.status, .warning)
        XCTAssertEqual(row("app-copies", in: multiple)?.settingsDestination, .openSettingsAdvanced)
        XCTAssertEqual(row("caps-lock", in: multiple)?.settingsDestination, .openSettingsGeneral)
    }
}
