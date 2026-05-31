@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

/// Tests for the KeyPath consumer of kanata's authoritative `InputGrab` TCP
/// status (#630): parsing the message, the shared status store, and the health
/// checker preferring it over the stderr log-pattern detector (#632).
///
/// Extends `KeyPathTestCase` for defensive isolation: its `TestSingletonReset`
/// resets `KanataGrabStatusStore.shared` in setUp/tearDown, so the global store
/// these tests mutate can't bleed into (or out of) other suites.
@MainActor
final class KanataInputGrabConsumerTests: KeyPathTestCase {
    // MARK: - parseInputGrab

    func testParseInputGrab_active_withDevices() {
        let body: [String: Any] = [
            "active": true,
            "devices": ["Apple Internal Keyboard / Trackpad", "HHKB-Hybrid"]
        ]
        let status = KanataEventListener.parseInputGrab(from: body, observedAt: Date())
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.active, true)
        XCTAssertEqual(status?.devices, ["Apple Internal Keyboard / Trackpad", "HHKB-Hybrid"])
        XCTAssertNil(status?.reason)
    }

    func testParseInputGrab_inactive_withReason() {
        let body: [String: Any] = [
            "active": false,
            "devices": [String](),
            "reason": "another process has exclusive grab"
        ]
        let status = KanataEventListener.parseInputGrab(from: body, observedAt: Date())
        XCTAssertEqual(status?.active, false)
        XCTAssertEqual(status?.devices, [])
        XCTAssertEqual(status?.reason, "another process has exclusive grab")
    }

    func testParseInputGrab_inactive_noReason_defaultsEmptyDevices() {
        let body: [String: Any] = ["active": false]
        let status = KanataEventListener.parseInputGrab(from: body, observedAt: Date())
        XCTAssertEqual(status?.active, false)
        XCTAssertEqual(status?.devices, [])
        XCTAssertNil(status?.reason)
    }

    func testParseInputGrab_missingActive_returnsNil() {
        let body: [String: Any] = ["devices": ["a"]]
        XCTAssertNil(KanataEventListener.parseInputGrab(from: body, observedAt: Date()))
    }

    // MARK: - KanataGrabStatusStore

    func testStore_recordAndReset() {
        XCTAssertNil(KanataGrabStatusStore.shared.latest)
        let status = KanataInputGrabStatus(active: true, devices: ["kbd"], reason: nil, observedAt: Date())
        KanataGrabStatusStore.shared.record(status)
        XCTAssertEqual(KanataGrabStatusStore.shared.latest, status)
        KanataGrabStatusStore.shared.reset()
        XCTAssertNil(KanataGrabStatusStore.shared.latest)
    }

    // MARK: - resolveInputCaptureStatus (primary signal vs. fallback)

    func testResolve_noStore_usesStderrFallback() {
        // Store empty → fall back to the #632 stderr detector verbatim.
        let failedFallback = ServiceHealthChecker.KanataInputCaptureStatus(isReady: false, issue: ServiceHealthChecker.inputCaptureGrabFailureReason)
        XCTAssertEqual(
            ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: failedFallback),
            failedFallback
        )
        XCTAssertEqual(
            ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready),
            .ready
        )
    }

    func testResolve_storeActive_doesNotMaskStderrFailure() {
        // active:true is strictly additive — it must NOT suppress a failure the
        // stderr detector found (the grab bit is coarser than stderr; a cached
        // active:true could be stale). The fallback passes through unchanged.
        KanataGrabStatusStore.shared.record(
            KanataInputGrabStatus(active: true, devices: ["kbd"], reason: nil, observedAt: Date())
        )
        let stderrFailure = ServiceHealthChecker.KanataInputCaptureStatus(
            isReady: false, issue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason
        )
        XCTAssertEqual(
            ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: stderrFailure),
            stderrFailure
        )
        // When stderr is clean, active:true resolves ready.
        XCTAssertEqual(
            ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready),
            .ready
        )
    }

    func testResolve_recoveryClearsPriorFailure() {
        // An authoritative failure marks unhealthy...
        KanataGrabStatusStore.shared.record(
            KanataInputGrabStatus(active: false, devices: [], reason: "exclusive grab", observedAt: Date())
        )
        XCTAssertFalse(ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready).isReady)
        // ...then a recovery transition (active:true) overwrites it in the store,
        // so a now-clean stderr resolves ready — no stuck-unhealthy.
        KanataGrabStatusStore.shared.record(
            KanataInputGrabStatus(active: true, devices: ["kbd"], reason: nil, observedAt: Date())
        )
        XCTAssertEqual(
            ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready),
            .ready
        )
    }

    func testResolve_storeInactive_overridesReadyFallback() {
        // Authoritative grab failure beats a stderr that looks clean (e.g. the
        // failure never produced a recognizable log line, or VNC masked it).
        KanataGrabStatusStore.shared.record(
            KanataInputGrabStatus(active: false, devices: [], reason: "not running as root", observedAt: Date())
        )
        let resolved = ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready)
        XCTAssertFalse(resolved.isReady)
        XCTAssertEqual(resolved.issue, "not running as root")
    }

    func testResolve_storeInactive_noReason_usesDefaultIssue() {
        KanataGrabStatusStore.shared.record(
            KanataInputGrabStatus(active: false, devices: [], reason: nil, observedAt: Date())
        )
        let resolved = ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready)
        XCTAssertFalse(resolved.isReady)
        XCTAssertEqual(resolved.issue, ServiceHealthChecker.inputCaptureGrabFailureReason)
    }

    // MARK: - end-to-end decision

    func testDecideHealth_inactiveGrab_marksUnhealthy() {
        KanataGrabStatusStore.shared.record(
            KanataInputGrabStatus(active: false, devices: [], reason: "exclusive grab", observedAt: Date())
        )
        let inputCapture = ServiceHealthChecker.resolveInputCaptureStatus(stderrFallback: .ready)
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: inputCapture.isReady,
            inputCaptureIssue: inputCapture.issue,
            launchctlExitCode: 0,
            staleEnabledRegistration: false,
            recentlyRestarted: false
        )
        let decision = ServiceHealthChecker.decideKanataHealth(for: snapshot)
        XCTAssertFalse(decision.isHealthy)
        XCTAssertEqual(decision, .unhealthy(reason: "exclusive grab"))
    }
}
