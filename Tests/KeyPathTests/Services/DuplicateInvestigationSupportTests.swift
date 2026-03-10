@testable import KeyPathAppKit
@preconcurrency import XCTest

final class DuplicateInvestigationSupportTests: XCTestCase {
    func testEnvironmentOverrideEnablesAndDisablesInvestigation() {
        XCTAssertTrue(DuplicateInvestigationSupport.isEnabled(environment: [DuplicateInvestigationSupport.envKey: "1"]))
        XCTAssertFalse(DuplicateInvestigationSupport.isEnabled(environment: [DuplicateInvestigationSupport.envKey: "0"]))
    }

    func testSessionRelationReportsSameCrossAndUnknown() {
        XCTAssertEqual(DuplicateInvestigationSupport.sessionRelation(previous: 4, current: 4), "same-session")
        XCTAssertEqual(DuplicateInvestigationSupport.sessionRelation(previous: 4, current: 5), "cross-session")
        XCTAssertEqual(DuplicateInvestigationSupport.sessionRelation(previous: nil, current: 5), "unknown-session")
    }

    func testKeypressObservationMetadataParsesNotificationUserInfo() {
        let observedAt = Date(timeIntervalSince1970: 123)
        let metadata = KeypressObservationMetadata.from(userInfo: [
            "listenerSessionID": 9,
            "kanataTimestamp": UInt64(321),
            "observedAt": observedAt
        ])

        XCTAssertEqual(metadata.listenerSessionID, 9)
        XCTAssertEqual(metadata.kanataTimestamp, 321)
        XCTAssertEqual(metadata.observedAt, observedAt)
    }

    func testObservedKeyInputLogIncludesSessionAndTimestamp() {
        let event = KanataObservedKeyInput(
            key: "a",
            action: .press,
            kanataTimestamp: 42,
            sessionID: 7,
            observedAt: Date(timeIntervalSince1970: 0)
        )

        let log = DuplicateInvestigationSupport.makeObservedKeyInputLog(event)
        XCTAssertTrue(log.contains("session=7"))
        XCTAssertTrue(log.contains("key=a"))
        XCTAssertTrue(log.contains("action=press"))
        XCTAssertTrue(log.contains("kanata_t=42"))
    }

    func testTrackerClassifiesPressWhileHeldAndReleaseAfterHold() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 100)

        await tracker.handleSessionStart(sessionID: 3)

        let firstPress = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 10,
                sessionID: 3,
                observedAt: start
            )
        )
        XCTAssertEqual(firstPress.kind, .freshPress)
        XCTAssertEqual(firstPress.heldKeyCount, 1)

        let secondPress = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 20,
                sessionID: 3,
                observedAt: start.addingTimeInterval(0.150)
            )
        )
        XCTAssertEqual(secondPress.kind, .pressWhileHeld)
        XCTAssertEqual(secondPress.sameKeyGapMs, 149)
        XCTAssertEqual(secondPress.heldDurationMs, 149)

        let release = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .release,
                kanataTimestamp: 30,
                sessionID: 3,
                observedAt: start.addingTimeInterval(0.220)
            )
        )
        XCTAssertEqual(release.kind, .releaseAfterHold)
        XCTAssertEqual(release.heldDurationMs, 70)
        XCTAssertEqual(release.heldKeyCount, 0)
    }

    func testTrackerSnapshotReportsHeldKeysAndLastEventAge() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 200)

        await tracker.handleSessionStart(sessionID: 8)
        _ = await tracker.record(
            KanataObservedKeyInput(
                key: "leftshift",
                action: .press,
                kanataTimestamp: 1,
                sessionID: 8,
                observedAt: start
            )
        )
        _ = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 2,
                sessionID: 8,
                observedAt: start.addingTimeInterval(0.050)
            )
        )

        let snapshot = await tracker.snapshot(
            phase: "reload-requested",
            reason: "test",
            observedAt: start.addingTimeInterval(0.200)
        )

        XCTAssertEqual(snapshot.sessionID, 8)
        XCTAssertEqual(snapshot.heldKeys.map(\.key), ["leftshift", "a"])
        XCTAssertEqual(snapshot.heldKeys.map(\.heldDurationMs), [200, 150])
        XCTAssertEqual(snapshot.msSinceLastEvent, 150)

        let log = DuplicateInvestigationSupport.makeReloadBoundaryLog(snapshot)
        XCTAssertTrue(log.contains("phase=reload-requested"))
        XCTAssertTrue(log.contains("held_key_count=2"))
        XCTAssertTrue(log.contains("leftshift:200ms"))
        XCTAssertTrue(log.contains("a:150ms"))
    }

    func testTrackerCorrelatesActivationWithHeldKeyState() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 300)

        await tracker.handleSessionStart(sessionID: 11)
        _ = await tracker.record(
            KanataObservedKeyInput(
                key: "caps",
                action: .press,
                kanataTimestamp: 100,
                sessionID: 11,
                observedAt: start
            )
        )

        let correlation = await tracker.recordActivation(
            KanataObservedActivation(
                kind: .holdActivated,
                key: "caps",
                action: "lctl",
                kanataTimestamp: 140,
                sessionID: 11,
                observedAt: start.addingTimeInterval(0.180)
            )
        )

        XCTAssertEqual(correlation.kind, .holdActivated)
        XCTAssertTrue(correlation.wasKeyHeld)
        XCTAssertEqual(correlation.heldKeyCount, 1)
        XCTAssertEqual(correlation.heldDurationMs, 179)
        XCTAssertEqual(correlation.previousAction, .press)
        XCTAssertEqual(correlation.sameKeyGapMs, 179)

        let log = DuplicateInvestigationSupport.makeActivationLog(correlation)
        XCTAssertTrue(log.contains("kind=hold-activated"))
        XCTAssertTrue(log.contains("key=caps"))
        XCTAssertTrue(log.contains("was_key_held=true"))
        XCTAssertTrue(log.contains("held_duration_ms=179"))
    }

    func testTrackerCorrelatesSystemEventWithLastKanataEvent() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 400)

        await tracker.handleSessionStart(sessionID: 12)
        _ = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 200,
                sessionID: 12,
                observedAt: start
            )
        )

        let correlation = await tracker.recordSystemEvent(
            InvestigationSystemKeyEvent(
                key: "a",
                keyCode: 0,
                eventType: "keyDown",
                isAutorepeat: false,
                flagsRawValue: 0x20000,
                sourcePID: nil,
                observedAt: start.addingTimeInterval(0.033)
            )
        )

        XCTAssertEqual(correlation.key, "a")
        XCTAssertEqual(correlation.previousKanataAction, .press)
        XCTAssertEqual(correlation.previousKanataSessionID, 12)
        XCTAssertEqual(correlation.sameKeyGapMs, 32)
        XCTAssertEqual(correlation.msSinceAnyKanataEvent, 32)
        XCTAssertFalse(correlation.suggestsUnmatchedAutorepeat)

        let log = DuplicateInvestigationSupport.makeSystemKeyEventLog(correlation)
        XCTAssertTrue(log.contains("event_type=keyDown"))
        XCTAssertTrue(log.contains("is_autorepeat=false"))
        XCTAssertTrue(log.contains("previous_kanata_action=press"))
        XCTAssertTrue(log.contains("previous_kanata_session=12"))
        XCTAssertTrue(log.contains("suggests_unmatched_autorepeat=false"))
    }

    func testKeyNameForKeyCodeFallsBackForUnknownValues() {
        XCTAssertEqual(DuplicateInvestigationSupport.keyName(forKeyCode: 49), "space")
        XCTAssertEqual(DuplicateInvestigationSupport.keyName(forKeyCode: 999), "keycode-999")
    }

    func testSessionBoundaryDoesNotBleedLastEventByKey() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 600)

        // Session 1: record a press
        await tracker.handleSessionStart(sessionID: 20)
        _ = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 50,
                sessionID: 20,
                observedAt: start
            )
        )

        // Session 2: different ID should clear lastEventByKey
        await tracker.handleSessionStart(sessionID: 21)
        let firstInNewSession = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 60,
                sessionID: 21,
                observedAt: start.addingTimeInterval(1.0)
            )
        )

        // previousAction should be nil because session boundary cleared lastEventByKey
        XCTAssertNil(firstInNewSession.previousAction)
        XCTAssertNil(firstInNewSession.previousSessionID)
        XCTAssertNil(firstInNewSession.sameKeyGapMs)
    }

    func testReleaseWithoutTrackedPress() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 700)

        await tracker.handleSessionStart(sessionID: 30)
        let release = await tracker.record(
            KanataObservedKeyInput(
                key: "b",
                action: .release,
                kanataTimestamp: 70,
                sessionID: 30,
                observedAt: start
            )
        )

        XCTAssertEqual(release.kind, .releaseWithoutTrackedPress)
        XCTAssertNil(release.heldDurationMs)
    }

    func testRepeatWithoutTrackedPress() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 800)

        await tracker.handleSessionStart(sessionID: 31)
        let repeatEvent = await tracker.record(
            KanataObservedKeyInput(
                key: "c",
                action: .repeat,
                kanataTimestamp: 80,
                sessionID: 31,
                observedAt: start
            )
        )

        XCTAssertEqual(repeatEvent.kind, .repeatWithoutTrackedPress)
        XCTAssertNil(repeatEvent.heldDurationMs)
    }

    func testMultipleKeysHeldSimultaneously() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 900)

        await tracker.handleSessionStart(sessionID: 32)

        let pressA = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .press,
                kanataTimestamp: 90,
                sessionID: 32,
                observedAt: start
            )
        )
        XCTAssertEqual(pressA.heldKeyCount, 1)

        let pressB = await tracker.record(
            KanataObservedKeyInput(
                key: "b",
                action: .press,
                kanataTimestamp: 91,
                sessionID: 32,
                observedAt: start.addingTimeInterval(0.050)
            )
        )
        XCTAssertEqual(pressB.heldKeyCount, 2)

        let releaseA = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .release,
                kanataTimestamp: 92,
                sessionID: 32,
                observedAt: start.addingTimeInterval(0.100)
            )
        )
        XCTAssertEqual(releaseA.heldKeyCount, 1)
    }

    func testKeypressObservationMetadataFromNilUserInfo() {
        let metadata = KeypressObservationMetadata.from(userInfo: nil)
        XCTAssertNil(metadata.listenerSessionID)
        XCTAssertNil(metadata.kanataTimestamp)
        XCTAssertNil(metadata.observedAt)
    }

    func testSystemAutorepeatMismatchFlagsWhenKanataDidNotRepeat() async {
        let tracker = DuplicateKeyInvestigationTracker()
        let start = Date(timeIntervalSince1970: 500)

        await tracker.handleSessionStart(sessionID: 14)
        _ = await tracker.record(
            KanataObservedKeyInput(
                key: "a",
                action: .release,
                kanataTimestamp: 300,
                sessionID: 14,
                observedAt: start
            )
        )

        let correlation = await tracker.recordSystemEvent(
            InvestigationSystemKeyEvent(
                key: "a",
                keyCode: 0,
                eventType: "keyDown",
                isAutorepeat: true,
                flagsRawValue: 0x100,
                sourcePID: nil,
                observedAt: start.addingTimeInterval(0.120)
            )
        )

        XCTAssertTrue(correlation.suggestsUnmatchedAutorepeat)

        let mismatch = DuplicateInvestigationSupport.makeAutorepeatMismatchLog(correlation)
        XCTAssertTrue(mismatch.contains("AutorepeatMismatch"))
        XCTAssertTrue(mismatch.contains("previous_kanata_action=release"))
    }
}
