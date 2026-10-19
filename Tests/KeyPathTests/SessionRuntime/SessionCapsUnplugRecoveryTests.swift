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

    // MARK: Same-port re-bind (Micah's decision, 2026-10-19)

    private typealias Device = SessionCapsMappingPolicy.DeviceIdentity
    private func cl80(_ registry: UInt64, location: UInt32 = 0x0110_0000, serial: String? = nil) -> Device {
        Device(registryEntryID: registry, vendorID: 0x5449, productID: 0x911C, serialNumber: serial, locationID: location)
    }

    private func chosen(_ device: Device, boot: String) -> SessionCapsSelection {
        SessionCapsSelection(device: device, bootSessionUUID: boot, intermediateUsage: 110)
    }

    func testSamePortReplugReboundsAndKeepsTheReservedKey() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        let x2a = Device(registryEntryID: 900, vendorID: 0x1234, productID: 0x0001, serialNumber: nil, locationID: 0x0220_0000)
        let rebound = try XCTUnwrap(chosen(cl80(100), boot: boot).rebound(among: [x2a, cl80(200)], currentBoot: boot))
        XCTAssertEqual(rebound.device, cl80(200))
        XCTAssertEqual(rebound.intermediateUsage, 110)
        XCTAssertEqual(rebound.bootSessionUUID, boot)
        let data = try JSONEncoder().encode(chosen(cl80(100), boot: boot))
        XCTAssertEqual(SessionCapsRuntimeSupport.reboundSelection(selectionData: data, devices: [cl80(200)], boot: boot)?.device, cl80(200))
    }

    func testSerialMustMatchWhenTheChosenKeyboardHadOne() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        let withSerial = chosen(cl80(100, serial: "ABC123"), boot: boot)
        XCTAssertEqual(withSerial.rebound(among: [cl80(200, serial: "ABC123")], currentBoot: boot)?.device, cl80(200, serial: "ABC123"))
        XCTAssertNil(withSerial.rebound(among: [cl80(200, serial: "XYZ999")], currentBoot: boot))
        XCTAssertNil(withSerial.rebound(among: [cl80(200)], currentBoot: boot))
        XCTAssertNil(chosen(cl80(100), boot: boot).rebound(among: [cl80(200, serial: "ABC123")], currentBoot: boot))
    }

    func testDifferentPortReplugIsNotRebound() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        XCTAssertNil(chosen(cl80(100), boot: boot).rebound(among: [cl80(200, location: 0x0330_0000)], currentBoot: boot))
    }

    func testTwinsAtTheSameLocatorAreNeverGuessedBetween() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        XCTAssertNil(chosen(cl80(100), boot: boot).rebound(among: [cl80(200), cl80(300)], currentBoot: boot))
        // A twin at another port does not block the same-port one.
        XCTAssertEqual(chosen(cl80(100), boot: boot).rebound(among: [cl80(200), cl80(300, location: 0x0330_0000)], currentBoot: boot)?.device,
                       cl80(200))
    }

    /// MacBook case: the unplug moved Caps rules to the built-in keyboard,
    /// overwriting the saved choice. The disconnected choice still re-binds.
    func testDisplacedChoiceReboundsAfterAutomaticSetupMovedAway() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        let builtIn = Device(registryEntryID: 50, vendorID: 0, productID: 0, serialNumber: nil, locationID: 0x0001_0000, appleBuiltIn: true)
        let displaced = try JSONEncoder().encode(chosen(cl80(100), boot: boot))
        let current = try JSONEncoder().encode(chosen(builtIn, boot: boot))
        let devices = [builtIn, cl80(200)]
        XCTAssertNil(SessionCapsRuntimeSupport.reboundSelection(selectionData: current, devices: devices, boot: boot),
                     "The built-in choice is present; it is not a replug")
        XCTAssertEqual(SessionCapsRuntimeSupport.reboundSelection(selectionData: displaced, devices: devices, boot: boot)?.device, cl80(200))
    }

    func testANewBootIsNeverRebound() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        let old = chosen(cl80(100), boot: UUID().uuidString)
        XCTAssertNil(old.rebound(among: [cl80(200)], currentBoot: boot))
        let data = try JSONEncoder().encode(old)
        XCTAssertNil(SessionCapsRuntimeSupport.reboundSelection(selectionData: data, devices: [cl80(200)], boot: boot))
    }

    func testAnOriginalStillConnectedIsNotSubstituted() throws {
        let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
        XCTAssertNil(chosen(cl80(100), boot: boot).rebound(among: [cl80(100)], currentBoot: boot), "Same instance: nothing to re-bind")
        XCTAssertNil(chosen(cl80(100), boot: boot).rebound(among: [cl80(100), cl80(200)], currentBoot: boot))
    }

    // MARK: Parent supervision

    @MainActor
    func testDisconnectAndProfileChangeRestartTheSessionOtherFailuresDoNot() {
        XCTAssertEqual(ServiceLifecycleCoordinator.capsRestart(after: SessionCapsRuntimeSupport.keyboardDisconnectedReason),
                       .keyboardDisconnected)
        XCTAssertEqual(ServiceLifecycleCoordinator.capsRestart(after: SessionCapsRuntimeSupport.profileChangedReason), .profileChanged)
        XCTAssertNil(ServiceLifecycleCoordinator.capsRestart(after: SessionCapsRuntimeSupport.ownershipLostReason),
                     "Lost ownership stays terminal: something else changed the mapping")
        XCTAssertNil(ServiceLifecycleCoordinator.capsRestart(after: nil))
    }

    /// The keyboard can vanish between the parent's choice and the worker's
    /// own check; the worker then runs paused and the parent must notice.
    @MainActor
    func testParentNoticesWhenTheWorkerRanPaused() {
        XCTAssertTrue(ServiceLifecycleCoordinator.workerPausedCaps(intended: true, managedCapsGeneration: nil, nonce: "n"))
        XCTAssertTrue(ServiceLifecycleCoordinator.workerPausedCaps(intended: true, managedCapsGeneration: "old", nonce: "n"))
        XCTAssertFalse(ServiceLifecycleCoordinator.workerPausedCaps(intended: true, managedCapsGeneration: "n", nonce: "n"))
        XCTAssertFalse(ServiceLifecycleCoordinator.workerPausedCaps(intended: false, managedCapsGeneration: nil, nonce: "n"))
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
        let moved = SessionCapsSettingsSection.disconnectedStatus(name: "cl80", listed: ["X2A", "cl80"], showsPicker: true)
        XCTAssertTrue(moved.contains("different port"))
        XCTAssertTrue(moved.contains("Choose it again"))
    }

    @MainActor
    func testClearingTheSelectionForgetsItsName() throws {
        let defaults = UserDefaults.standard
        let keys = [SessionCapsRuntimeSupport.selectionKey, SessionCapsRuntimeSupport.selectionNameKey,
                    "keypath.session.caps.displaced.v1"]
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        SessionCapsSelectionStore.saveName("cl80")
        XCTAssertEqual(SessionCapsSelectionStore.savedName, "cl80")
        SessionCapsSelectionStore.saveName(nil)
        XCTAssertNil(SessionCapsSelectionStore.savedName, "An unknown name clears the old one, never names the wrong keyboard")
        SessionCapsSelectionStore.saveName("cl80")
        SessionCapsSelectionStore.setDisplaced(Data("x".utf8), name: "cl80")
        XCTAssertEqual(SessionCapsSelectionStore.displaced?.data, Data("x".utf8))
        XCTAssertEqual(SessionCapsSelectionStore.displaced?.name, "cl80")
        try SessionCapsSelectionStore.save(nil)
        XCTAssertNil(SessionCapsSelectionStore.savedName)
        XCTAssertNil(SessionCapsSelectionStore.displaced, "Turning setup off ends a disconnected keyboard's claim")
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
