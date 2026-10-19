import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Regressions from the 2026-10-19 hardware unplug test on the mini (build
/// c656e34a0): unplugging the chosen cl80 stopped every rule, kept it stopped
/// after replug, Settings still said "On · cl80", and a keyboard pick made as
/// the app activated was dropped.
final class SessionCapsUnplugRecoveryTests: XCTestCase {
    private struct Refused: Error {}

    // MARK: Worker lease check

    func testVanishedLeasedKeyboardIsADisconnectNotLostOwnership() {
        let reason = SessionCapsRuntimeSupport.leaseCheckFailure(
            registryEntryID: 42, verify: { throw Refused() }, registryEntryExists: { _ in false }
        )
        XCTAssertEqual(reason, SessionCapsRuntimeSupport.keyboardDisconnectedReason)
    }

    func testPresentKeyboardThatFailsVerificationIsLostOwnership() {
        let reason = SessionCapsRuntimeSupport.leaseCheckFailure(
            registryEntryID: 42, verify: { throw Refused() }, registryEntryExists: { _ in true }
        )
        XCTAssertEqual(reason, SessionCapsRuntimeSupport.ownershipLostReason)
    }

    func testUnreadableRegistryIsNeverCalledADisconnect() {
        let reason = SessionCapsRuntimeSupport.leaseCheckFailure(
            registryEntryID: 42, verify: { throw Refused() }, registryEntryExists: { _ in throw Refused() }
        )
        XCTAssertEqual(reason, SessionCapsRuntimeSupport.ownershipLostReason)
    }

    func testVerifiedLeaseHasNoFailure() {
        var asked = false
        let reason = SessionCapsRuntimeSupport.leaseCheckFailure(
            registryEntryID: 42, verify: {}, registryEntryExists: { _ in asked = true; return false }
        )
        XCTAssertNil(reason)
        XCTAssertFalse(asked, "A healthy lease does not consult the registry")
    }

    // MARK: Paused admission

    /// The relaunch after a disconnect passes no selection. The worker must
    /// still run the profile (other rules), even one with a rule on F18: no
    /// key is reserved while Caps is paused.
    func testWorkerRunsACapsProfileWithoutASelectionAsPaused() throws {
        try SessionBridgeTestFixture.requireAvailable()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let none = [SessionCapsRuntimeSupport.selectionEnvironmentKey: SessionCapsRuntimeSupport.noSelection]
        for profile in ["(defsrc caps a)(deflayer base esc b)", "(defsrc caps f18)(deflayer base esc a)"] {
            try profile.write(to: file, atomically: true, encoding: .utf8)
            let admission = SessionCapsRuntimeSupport.admit(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                            environment: none, selectionData: nil, rechoose: false)
            guard case .valid = admission.result else { return XCTFail("Paused profile must run: \(profile)") }
            XCTAssertFalse(admission.managedCaps, profile)
            XCTAssertTrue(admission.capsPaused, profile)
        }
        try "(defsrc a)(deflayer base b)".write(to: file, atomically: true, encoding: .utf8)
        let ordinary = SessionCapsRuntimeSupport.admit(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                       environment: none, selectionData: nil, rechoose: false)
        XCTAssertFalse(ordinary.capsPaused, "A profile without Caps rules has nothing to pause")
        try "(defsrc caps)(deflayer base".write(to: file, atomically: true, encoding: .utf8)
        let broken = SessionCapsRuntimeSupport.admit(configPath: file.path, runtimeHost: SessionBridgeTestFixture.runtimeHost,
                                                     environment: none, selectionData: nil, rechoose: false)
        guard case .invalid = broken.result else { return XCTFail("Pausing never admits a profile that does not parse") }
        XCTAssertFalse(broken.capsPaused)
    }

    // MARK: Settings

    func testChoiceMadeWhileBusyIsQueuedAndAppliedOnce() {
        var queue = SessionCapsChoiceQueue<Int>()
        XCTAssertNil(queue.submit(1, busy: true), "A pick during a refresh waits instead of applying")
        XCTAssertEqual(queue.pending, 1, "The picker keeps showing the waiting pick")
        XCTAssertNil(queue.submit(2, busy: true))
        XCTAssertEqual(queue.takeAfterRefresh(), 2, "The latest pick wins")
        XCTAssertNil(queue.takeAfterRefresh(), "Applied once")
    }

    func testChoiceWhenIdleAppliesNowAndClearsAWaitingOne() {
        var queue = SessionCapsChoiceQueue<Int>()
        _ = queue.submit(1, busy: true)
        XCTAssertEqual(queue.submit(3, busy: false), 3)
        XCTAssertNil(queue.pending)
        XCTAssertNil(queue.takeAfterRefresh())
    }

    @MainActor
    func testDisconnectedStatusNamesTheKeyboardAndAsksToChooseAgainAfterReplug() {
        let gone = SessionCapsSettingsSection.disconnectedStatus(name: "cl80", listed: ["X2A"], showsPicker: true)
        XCTAssertTrue(gone.hasPrefix("cl80 is disconnected"))
        XCTAssertTrue(gone.contains("paused"))
        XCTAssertFalse(gone.hasPrefix("On"))
        let back = SessionCapsSettingsSection.disconnectedStatus(name: "cl80", listed: ["X2A", "cl80"], showsPicker: true)
        XCTAssertTrue(back.contains("reconnected"))
        XCTAssertTrue(back.contains("Choose it again"))
    }

    @MainActor
    func testClearingTheSelectionForgetsItsName() throws {
        let defaults = UserDefaults.standard
        let keys = [SessionCapsRuntimeSupport.selectionKey, SessionCapsRuntimeSupport.selectionNameKey]
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        SessionCapsSelectionStore.saveName("cl80")
        XCTAssertEqual(SessionCapsSelectionStore.savedName, "cl80")
        SessionCapsSelectionStore.saveName("")
        XCTAssertEqual(SessionCapsSelectionStore.savedName, "cl80", "An empty name never replaces a known one")
        try SessionCapsSelectionStore.save(nil)
        XCTAssertNil(SessionCapsSelectionStore.savedName)
    }

    // MARK: Stuck-key snapshot

    func testDriverlessSnapshotAttachesTheWorkerNotTheLegacyDaemonLog() {
        let report = SessionRuntimeReport(nonce: "n", pid: 4242, uid: 501, state: .failed, accessibility: true,
                                          effectiveInputAccess: true, tapActive: false, tcpPort: 37001,
                                          inputCount: 7, outputCount: 5, failure: "output-queue-overrun",
                                          heldOutputUsages: [4, 225])
        let lines = StuckKeyRecoveryService.runtimeEvidenceLines(.sessionWorker((report, false)),
                                                                 stderrPath: "/nonexistent", stdoutPath: "/nonexistent")
        XCTAssertTrue(lines.contains("=== Session Worker ==="))
        XCTAssertTrue(lines.contains("state: failed"))
        XCTAssertTrue(lines.contains("worker_pid: 4242"))
        XCTAssertTrue(lines.contains("report_current: false"))
        XCTAssertTrue(lines.contains("held_output_usages: 4,225"))
        XCTAssertTrue(lines.contains("failure: output-queue-overrun"))
        XCTAssertFalse(lines.contains { $0.contains("Kanata Stderr") || $0.contains("Kanata Stdout") })

        let none = StuckKeyRecoveryService.runtimeEvidenceLines(.sessionWorker(nil))
        XCTAssertTrue(none.contains { $0.contains("no worker report") })
        XCTAssertFalse(none.contains { $0.contains("Kanata Stderr") })
    }

    func testLegacySnapshotKeepsTheDaemonLogs() {
        let lines = StuckKeyRecoveryService.runtimeEvidenceLines(.daemonLogs, stderrPath: "/nonexistent", stdoutPath: "/nonexistent")
        XCTAssertTrue(lines.contains("=== Kanata Stderr (last 50 lines) ==="))
        XCTAssertFalse(lines.contains("=== Session Worker ==="))
    }
}
