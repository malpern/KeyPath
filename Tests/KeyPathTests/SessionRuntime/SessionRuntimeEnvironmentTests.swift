@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class SessionRuntimeEnvironmentTests: XCTestCase {
    private let active = SessionRuntimeConsoleObservation(uid: 502, onConsole: true, loginDone: true)

    func testUnavailableForeignIncompleteAndOffConsoleEvidenceRetiresWorker() {
        let observations: [SessionRuntimeConsoleObservation?] = [
            nil, .init(uid: 501, onConsole: true, loginDone: true),
            .init(uid: 502, onConsole: false, loginDone: true),
            .init(uid: 502, onConsole: true, loginDone: false)
        ]
        for observation in observations {
            var state = SessionRuntimeEnvironmentState(expectedUID: 502)
            XCTAssertNil(state.observe(active))
            XCTAssertEqual(state.observe(observation), observation == nil ? .consoleObservationUnavailable : .consoleSessionInactive)
            XCTAssertNotNil(state.observe(active), "Session return must not revive a retired worker")
        }
        var root = SessionRuntimeEnvironmentState(expectedUID: 0)
        XCTAssertEqual(root.observe(.init(uid: 0, onConsole: true, loginDone: true)), .consoleSessionInactive)
    }

    func testPowerAndResignBoundariesLatchTheirFirstCauseAcrossWakeAndReturn() {
        for reason: SessionRuntimeEnvironmentState.Boundary in [.systemWillSleep, .sessionResignedActive, .systemWakeObserved] {
            var state = SessionRuntimeEnvironmentState(expectedUID: 502)
            XCTAssertNil(state.observe(active))
            XCTAssertEqual(state.retire(reason), reason)
            XCTAssertEqual(state.retire(.systemWakeObserved), reason)
            XCTAssertEqual(state.observe(active), reason)
        }
    }

    @MainActor
    func testProductionObserverCheckStopsHeldControlOnConsoleDepartureWithoutReturnResurrection() throws {
        var current: SessionRuntimeConsoleObservation? = active
        var outputs = SessionOutputState()
        _ = try outputs.translate(.init(value: 1, usagePage: 7, usage: 224))
        var causes: [SessionRuntimeEnvironmentState.Boundary] = []
        var releases: [SessionKeyOutput] = []
        let observer = SessionRuntimeEnvironmentObserver(expectedUID: 502, readConsole: { current }) { reason, acknowledge in
            causes.append(reason)
            releases += outputs.releaseAll()
            acknowledge?()
        }
        XCTAssertTrue(observer.check())
        XCTAssertEqual(outputs.heldUsages, [224])
        current = .init(uid: 502, onConsole: false, loginDone: true)
        XCTAssertFalse(observer.check())
        XCTAssertEqual(causes, [.consoleSessionInactive])
        XCTAssertEqual(releases.map(\.keyCode), [59])
        XCTAssertTrue(releases.allSatisfy { !$0.isDown })
        XCTAssertTrue(outputs.heldUsages.isEmpty)
        current = active
        XCTAssertFalse(observer.check())
        XCTAssertEqual(causes.count, 1)
        XCTAssertEqual(releases.count, 1)
    }

    @MainActor
    func testProductionObserverUnavailableReadFailsOpenAndKeepsCauseAfterReturn() {
        var current: SessionRuntimeConsoleObservation?
        var causes: [SessionRuntimeEnvironmentState.Boundary] = []
        let observer = SessionRuntimeEnvironmentObserver(expectedUID: 502, readConsole: { current }) { reason, _ in causes.append(reason) }
        XCTAssertFalse(observer.check())
        current = active
        XCTAssertFalse(observer.check())
        XCTAssertEqual(causes, [.consoleObservationUnavailable])
    }

    @MainActor
    func testProductionTerminationReleasesAndReportsBeforePowerAcknowledgementAndUnregister() throws {
        var outputs = SessionOutputState()
        _ = try outputs.translate(.init(value: 1, usagePage: 7, usage: 224))
        _ = try outputs.translate(.init(value: 1, usagePage: 7, usage: 4))
        var sequence: [String] = []
        let observer = SessionRuntimeEnvironmentObserver(expectedUID: 502, readConsole: { self.active }) { reason, acknowledge in
            XCTAssertEqual(reason, .systemWillSleep)
            SessionRuntimeWorker.completeTermination(releaseOutputs: {
                let releases = outputs.releaseAll()
                XCTAssertEqual(releases.map(\.keyCode), [0, 59])
                sequence.append("release")
            }, publishTerminalReport: {
                XCTAssertTrue(outputs.heldUsages.isEmpty)
                sequence.append("report")
            }, acknowledge: acknowledge, unregisterObservers: {
                sequence.append("unregister")
            })
        }
        observer.observePowerEvent(.willSleep) { sequence.append("ack") }
        XCTAssertEqual(sequence, ["release", "report", "ack", "unregister"])
        observer.retire(.systemWakeObserved) { sequence.append("duplicate-ack") }
        XCTAssertFalse(observer.check())
        XCTAssertEqual(sequence, ["release", "report", "ack", "unregister", "duplicate-ack"])
    }

    func testCanSleepOnlyAcknowledgesAndEarlyWakeLatchesWithoutCallbackIO() {
        var acknowledgements = 0
        var causes: [SessionRuntimeEnvironmentState.Boundary] = []
        let observer = SessionRuntimeEnvironmentObserver(expectedUID: 502, readConsole: { self.active }) { reason, _ in
            causes.append(reason)
        }
        observer.observePowerEvent(.canSleep) { acknowledgements += 1 }
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertTrue(causes.isEmpty)
        XCTAssertTrue(observer.check())
        observer.observePowerEvent(.willPowerOn) { acknowledgements += 1 }
        XCTAssertTrue(causes.isEmpty, "Early wake handler must not release/post/write a report")
        XCTAssertEqual(acknowledgements, 1, "Wake messages must not be acknowledged")
        XCTAssertFalse(observer.check(), "Latched retirement must reject old output before powered-on")
        XCTAssertEqual(causes, [.systemWakeObserved])
        observer.observePowerEvent(.hasPoweredOn) { acknowledgements += 1 }
        XCTAssertEqual(causes.count, 1)
        XCTAssertEqual(acknowledgements, 1)
    }

    func testPublicQuartzDictionaryParserRejectsMalformedAndCoercedEvidence() {
        let uidKey = "kCGSSessionUserIDKey"
        let onConsoleKey = "kCGSSessionOnConsoleKey"
        let loginDoneKey = "kCGSessionLoginDoneKey"
        let dictionary: [String: Any] = [uidKey: NSNumber(value: 502),
                                       onConsoleKey: NSNumber(value: true), loginDoneKey: NSNumber(value: true)]
        XCTAssertEqual(SessionRuntimeEnvironmentObserver.parseConsole(dictionary), active)
        XCTAssertNil(SessionRuntimeEnvironmentObserver.parseConsole(nil))
        for key in [uidKey, onConsoleKey, loginDoneKey] {
            var incomplete = dictionary
            incomplete.removeValue(forKey: key)
            XCTAssertNil(SessionRuntimeEnvironmentObserver.parseConsole(incomplete))
        }
        for badUID: Any in [NSNumber(value: true), NSNumber(value: -1), NSNumber(value: 502.5),
                           NSNumber(value: UInt64(UInt32.max) + 1), "502"] {
            var malformed = dictionary
            malformed[uidKey] = badUID
            XCTAssertNil(SessionRuntimeEnvironmentObserver.parseConsole(malformed))
        }
        for key in [onConsoleKey, loginDoneKey] {
            var malformed = dictionary
            malformed[key] = NSNumber(value: 1)
            XCTAssertNil(SessionRuntimeEnvironmentObserver.parseConsole(malformed))
        }
    }

    func testNotificationBaselineDrainsFirstTrueAndLaterChangeRetiresAfterReturn() {
        var replies: [Bool?] = [true, false, true]
        var causes: [SessionRuntimeEnvironmentState.Boundary] = []
        let observer = SessionRuntimeEnvironmentObserver(expectedUID: 502, readConsole: { self.active },
                                                        readNotification: { _ in replies.removeFirst() }) { reason, _ in
            causes.append(reason)
        }
        XCTAssertTrue(observer.baselineNotification(123))
        XCTAssertTrue(causes.isEmpty)
        XCTAssertTrue(observer.checkNotification(123))
        XCTAssertTrue(observer.check())
        // Coalesced departure+return leaves current evidence active, but a
        // post-baseline notification still permanently retires old queues.
        XCTAssertFalse(observer.checkNotification(123))
        XCTAssertFalse(observer.check())
        XCTAssertEqual(causes, [.consoleSessionChangeObserved])
    }

    func testNotificationUnavailableAtBaselineOrPollingNeverAdmitsOldOutput() {
        var causes: [SessionRuntimeEnvironmentState.Boundary] = []
        let observer = SessionRuntimeEnvironmentObserver(expectedUID: 502, readConsole: { self.active },
                                                        readNotification: { _ in nil }) { reason, _ in
            causes.append(reason)
        }
        XCTAssertFalse(observer.baselineNotification(123))
        XCTAssertFalse(observer.checkNotification(123))
        XCTAssertFalse(observer.check())
        XCTAssertEqual(causes, [.consoleObservationUnavailable])
    }

    func testFailedControlReleaseRetainsOnlyUnpostedLedgerAndDoesNotSkipPowerAck() throws {
        var outputs = SessionOutputState()
        _ = try outputs.translate(.init(value: 1, usagePage: 7, usage: 224))
        _ = try outputs.translate(.init(value: 1, usagePage: 7, usage: 4))
        var posted: [UInt16] = []
        var reported: Set<UInt32> = []
        var sequence: [String] = []
        SessionRuntimeWorker.completeTermination(releaseOutputs: {
            SessionRuntimeWorker.releaseOwnedOutputs(&outputs) { output in
                posted.append(output.keyCode)
                return output.keyCode != 59 // Allocation fails for Control up.
            }
            sequence.append("release")
        }, publishTerminalReport: {
            reported = outputs.heldUsages
            sequence.append("report")
        }, acknowledge: {
            sequence.append("ack")
        }, unregisterObservers: {
            sequence.append("unregister")
        })
        XCTAssertEqual(posted, [0, 59])
        XCTAssertEqual(reported, [224])
        XCTAssertEqual(outputs.heldUsages, [224])
        XCTAssertEqual(sequence, ["release", "report", "ack", "unregister"])
        posted.removeAll()
        SessionRuntimeWorker.releaseOwnedOutputs(&outputs) { output in
            posted.append(output.keyCode)
            return true
        }
        XCTAssertEqual(posted, [59], "Only the preserved release is eligible for later recovery")
        XCTAssertTrue(outputs.heldUsages.isEmpty)
    }
}
