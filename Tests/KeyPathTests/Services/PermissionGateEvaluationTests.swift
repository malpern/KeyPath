@testable import KeyPathAppKit
@testable import KeyPathPermissions
@preconcurrency import XCTest

@MainActor
final class PermissionGateEvaluationTests: XCTestCase {
    func testKanataUnknownClassifiesAsNotVerifiedNotBlocking() {
        let now = Date()
        let snap = PermissionOracle.Snapshot(
            keyPath: .init(
                accessibility: .granted,
                inputMonitoring: .granted,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            kanata: .init(
                accessibility: .unknown,
                inputMonitoring: .unknown,
                source: "test",
                confidence: .low,
                timestamp: now
            ),
            timestamp: now
        )

        let eval = PermissionGate.evaluate(snap, for: .keyboardRemapping)
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertTrue(eval.kanataBlocking.isEmpty)
        XCTAssertEqual(eval.kanataNotVerified, [.accessibility, .inputMonitoring])
    }

    func testKanataDeniedClassifiesAsBlocking() {
        let now = Date()
        let snap = PermissionOracle.Snapshot(
            keyPath: .init(
                accessibility: .granted,
                inputMonitoring: .granted,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            kanata: .init(
                accessibility: .denied,
                inputMonitoring: .denied,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            timestamp: now
        )

        let eval = PermissionGate.evaluate(snap, for: .keyboardRemapping)
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertEqual(eval.kanataBlocking, [.accessibility, .inputMonitoring])
        XCTAssertTrue(eval.kanataNotVerified.isEmpty)
    }

    private func snapshot(
        keyPathAX: PermissionOracle.Status = .granted,
        keyPathIM: PermissionOracle.Status = .denied,
        kanataAX: PermissionOracle.Status = .granted,
        kanataIM: PermissionOracle.Status = .granted
    ) -> PermissionOracle.Snapshot {
        let now = Date()
        return .init(
            keyPath: .init(accessibility: keyPathAX, inputMonitoring: keyPathIM,
                           source: "test", confidence: .high, timestamp: now),
            kanata: .init(accessibility: kanataAX, inputMonitoring: kanataIM,
                          source: "test", confidence: .high, timestamp: now),
            timestamp: now
        )
    }

    func testRemappingDoesNotRequireKeyPathInputMonitoring() {
        let eval = PermissionGate.evaluate(snapshot(), for: .keyboardRemapping)
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertTrue(eval.kanataBlocking.isEmpty)
        XCTAssertTrue(eval.kanataNotVerified.isEmpty)
    }

    func testRemappingStillRequiresEngineInputAccess() {
        let eval = PermissionGate.evaluate(snapshot(kanataIM: .denied), for: .keyboardRemapping)
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertEqual(eval.kanataBlocking, [.inputMonitoring])
    }

    func testReloadDoesNotRequestKeyboardPermissionsEvenWithStoppedUnverifiedEngine() {
        let eval = PermissionGate.evaluate(
            snapshot(keyPathAX: .denied, kanataAX: .unknown, kanataIM: .unknown),
            for: .configurationReload
        )
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertTrue(eval.kanataBlocking.isEmpty)
        XCTAssertTrue(eval.kanataNotVerified.isEmpty)
    }

    func testCaptureRequiresAppAccessibilityButNotEnginePermissions() {
        let eval = PermissionGate.evaluate(
            snapshot(keyPathAX: .denied, kanataAX: .unknown, kanataIM: .denied),
            for: .keyCapture
        )
        XCTAssertEqual(eval.missingKeyPath, [.accessibility])
        XCTAssertTrue(eval.kanataBlocking.isEmpty)
        XCTAssertTrue(eval.kanataNotVerified.isEmpty)
    }

    func testAppAndEngineFailuresRemainIndependentDuringRemapping() {
        let eval = PermissionGate.evaluate(
            snapshot(keyPathAX: .denied, kanataAX: .unknown, kanataIM: .denied),
            for: .keyboardRemapping
        )
        XCTAssertEqual(eval.missingKeyPath, [.accessibility])
        XCTAssertEqual(eval.kanataBlocking, [.inputMonitoring])
        XCTAssertEqual(eval.kanataNotVerified, [.accessibility])
    }

    func testGrantingAppAccessibilityCannotBypassEngineDenialOrUnknown() {
        for status in [PermissionOracle.Status.denied, .unknown] {
            let before = PermissionGate.evaluate(
                snapshot(keyPathAX: .denied, kanataIM: status), for: .keyboardRemapping
            )
            let after = PermissionGate.evaluate(
                snapshot(keyPathAX: .granted, kanataIM: status), for: .keyboardRemapping
            )
            XCTAssertFalse(before.canProceed)
            XCTAssertFalse(after.canProceed)
            XCTAssertTrue(after.missingKeyPath.isEmpty)
        }
    }

    func testUnverifiedAppAccessibilityDoesNotPermitLocalCapture() {
        let eval = PermissionGate.evaluate(snapshot(keyPathAX: .unknown), for: .keyCapture)
        XCTAssertFalse(eval.canProceed)
        XCTAssertEqual(eval.missingKeyPath, [.accessibility])
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
