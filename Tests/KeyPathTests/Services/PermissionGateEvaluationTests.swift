@testable import KeyPathAppKit
@testable import KeyPathPermissions
@preconcurrency import XCTest

@MainActor
final class PermissionGateEvaluationTests: XCTestCase {
    private func snapshot(
        accessibility: PermissionOracle.Status = .granted,
        runtimeKeyAccess: PermissionOracle.Status = .granted
    ) -> PermissionOracle.Snapshot {
        .fixture(accessibility: accessibility, runtimeKeyAccess: runtimeKeyAccess)
    }

    func testUnreportedRuntimeIsNotVerifiedNotBlocking() {
        let eval = PermissionGate.evaluate(snapshot(runtimeKeyAccess: .unknown), for: .keyboardRemapping)
        XCTAssertFalse(eval.accessibilityMissing)
        XCTAssertFalse(eval.runtimeBlocked)
        XCTAssertTrue(eval.runtimeNotVerified)
        XCTAssertFalse(eval.canProceed)
    }

    func testDeniedRuntimeIsBlocking() {
        let eval = PermissionGate.evaluate(snapshot(runtimeKeyAccess: .denied), for: .keyboardRemapping)
        XCTAssertFalse(eval.accessibilityMissing)
        XCTAssertTrue(eval.runtimeBlocked)
        XCTAssertFalse(eval.runtimeNotVerified)
    }

    func testRemappingProceedsWithAccessibilityAndRuntimeAccess() {
        XCTAssertTrue(PermissionGate.evaluate(snapshot(), for: .keyboardRemapping).canProceed)
    }

    func testReloadDoesNotRequireKeyboardPermissions() {
        let eval = PermissionGate.evaluate(
            snapshot(accessibility: .denied, runtimeKeyAccess: .unknown), for: .configurationReload
        )
        XCTAssertTrue(eval.canProceed)
    }

    func testCaptureRequiresAccessibilityButNotRuntimeAccess() {
        let eval = PermissionGate.evaluate(
            snapshot(accessibility: .denied, runtimeKeyAccess: .denied), for: .keyCapture
        )
        XCTAssertTrue(eval.accessibilityMissing)
        XCTAssertFalse(eval.runtimeBlocked)
        XCTAssertFalse(eval.runtimeNotVerified)
    }

    func testAccessibilityAndRuntimeFailuresRemainIndependentDuringRemapping() {
        let eval = PermissionGate.evaluate(
            snapshot(accessibility: .denied, runtimeKeyAccess: .denied), for: .keyboardRemapping
        )
        XCTAssertTrue(eval.accessibilityMissing)
        XCTAssertTrue(eval.runtimeBlocked)
    }

    func testGrantingAccessibilityCannotBypassRuntimeDenialOrUnknown() {
        for status in [PermissionOracle.Status.denied, .unknown] {
            let before = PermissionGate.evaluate(
                snapshot(accessibility: .denied, runtimeKeyAccess: status), for: .keyboardRemapping
            )
            let after = PermissionGate.evaluate(
                snapshot(accessibility: .granted, runtimeKeyAccess: status), for: .keyboardRemapping
            )
            XCTAssertFalse(before.canProceed)
            XCTAssertFalse(after.canProceed)
            XCTAssertFalse(after.accessibilityMissing)
        }
    }

    func testUnverifiedAccessibilityDoesNotPermitLocalCapture() {
        let eval = PermissionGate.evaluate(snapshot(accessibility: .unknown), for: .keyCapture)
        XCTAssertFalse(eval.canProceed)
        XCTAssertTrue(eval.accessibilityMissing)
    }

    func testReloadActionProceedsWithoutPermissionInspection() async {
        var granted = false
        var denied = false
        await PermissionGate.shared.checkAndRequestPermissions(
            for: .configurationReload,
            onGranted: { granted = true },
            onDenied: { denied = true }
        )
        XCTAssertTrue(granted)
        XCTAssertFalse(denied)
    }
}
