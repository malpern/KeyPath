@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class KeystrokeHistoryServiceTests: XCTestCase {
    private func postKeyInput(
        _ center: NotificationCenter,
        key: String,
        action: KanataKeyAction = .press,
        kanataTimestamp: UInt64? = nil
    ) {
        center.post(KanataObservedKeyInput(
            key: key, action: action, kanataTimestamp: kanataTimestamp, sessionID: 1, observedAt: Date()
        ))
    }

    private func flushNotificationsAndBatch(_ service: KeystrokeHistoryService) async {
        // Let notification handlers enqueue events, then flush the batch timer deterministically.
        await Task.yield()
        await Task.yield()
        service.flushPendingEventsForTesting()
    }

    func testDisablingPackStopsRecordingAndClearsHistory() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 1)
        service.applyPackState(false)
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.eventCount, 0)
        postKeyInput(center, key: "b")
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 0)
    }

    // MARK: - Event Ingestion

    func testKeyInputCreatesEvent() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 1)
    }

    func testMultipleKeysGroupIntoTextRun() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        for key in ["h", "e", "l", "l", "o"] {
            postKeyInput(center, key: key)
        }
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 5)
        XCTAssertEqual(service.segments.count, 1)
        if case let .textRun(run) = service.segments.first {
            XCTAssertEqual(run.characters.count, 5)
            XCTAssertEqual(run.characters.map(\.displayChar).joined(), "hello")
        } else {
            XCTFail("Expected text run segment")
        }
    }

    func testReleaseEventsAreFiltered() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a", action: .press)
        postKeyInput(center, key: "a", action: .release)
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 2)
        // Release events are not shown in segments (filtered by grouper)
        XCTAssertEqual(service.segments.count, 1)
        if case let .textRun(run) = service.segments.first {
            XCTAssertEqual(run.characters.count, 1)
        } else {
            XCTFail("Expected text run segment")
        }
    }

    // MARK: - Layer Changes

    func testLayerChangeUpdatesCurrentLayer() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        XCTAssertEqual(service.currentLayer, "base")
        center.post(KanataLayerChange(layerName: "nav", source: .kanata))
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.currentLayer, "nav")
    }

    func testLayerChangeCreatesLayerDivider() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        center.post(KanataLayerChange(layerName: "nav", source: .kanata))
        postKeyInput(center, key: "b")
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.segments.count, 3)
        if case let .layerDivider(divider) = service.segments[1] {
            XCTAssertEqual(divider.layerName, "nav")
        } else {
            XCTFail("Expected layer divider at index 1")
        }
    }

    // MARK: - Tap-Hold Events

    func testHoldActivatedCreatesEventCard() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        center.post(KanataHoldActivation(
            key: "caps", action: "lctl+lmet+lalt+lsft", timestamp: 1000, sessionID: 1,
            observedAt: Date(), reason: "opposite-hand"
        ))
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.segments.count, 1)
        if case let .eventCard(card) = service.segments.first,
           case let .tapHold(data) = card.cardKind
        {
            XCTAssertEqual(data.key, "caps")
            XCTAssertEqual(data.outputAction, "lctl+lmet+lalt+lsft")
            XCTAssertTrue(data.isHold)
            XCTAssertEqual(data.reason, "opposite-hand")
        } else {
            XCTFail("Expected tap-hold event card")
        }
    }

    func testTapActivatedCreatesEventCard() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        center.post(KanataTapActivation(
            key: "caps", action: "esc", timestamp: 1000, sessionID: 1,
            observedAt: Date(), reason: "release-before-timeout"
        ))
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.segments.count, 1)
        if case let .eventCard(card) = service.segments.first,
           case let .tapHold(data) = card.cardKind
        {
            XCTAssertEqual(data.key, "caps")
            XCTAssertEqual(data.outputAction, "esc")
            XCTAssertFalse(data.isHold)
        } else {
            XCTFail("Expected tap-hold event card")
        }
    }

    func testTypedOneShotChordAndTapDanceCreateOrderedEventCards() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        let observedAt = Date()
        center.post(KanataOneShotActivation(
            key: "lsft", modifiers: "lctl+lsft", timestamp: 10, sessionID: 1, observedAt: observedAt
        ))
        center.post(KanataChordResolution(
            keys: "s+d", action: "esc", timestamp: 20, sessionID: 1, observedAt: observedAt
        ))
        center.post(KanataTapDanceResolution(
            key: "q", tapCount: 2, action: "tab", timestamp: 30, sessionID: 1, observedAt: observedAt
        ))
        await flushNotificationsAndBatch(service)

        let cards = service.segments.compactMap { segment -> EventCardKind? in
            guard case let .eventCard(card) = segment else { return nil }
            return card.cardKind
        }
        guard cards.count == 3,
              case let .oneShot(oneShot) = cards[0],
              case let .chord(chord) = cards[1],
              case let .tapDance(tapDance) = cards[2]
        else { return XCTFail("Expected one-shot, chord, and tap-dance cards in order") }
        XCTAssertEqual(oneShot.key, "lsft")
        XCTAssertEqual(oneShot.modifiers, "lctl+lsft")
        XCTAssertEqual(chord.keys, "s+d")
        XCTAssertEqual(chord.action, "esc")
        XCTAssertEqual(tapDance.key, "q")
        XCTAssertEqual(tapDance.tapCount, 2)
        XCTAssertEqual(tapDance.action, "tab")
    }

    func testTypedHrmTraceAndActionPreserveHistoryDetails() async throws {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        service.thresholdLookup = { (baseMs: 200, offsets: ["f": 10]) }
        let uri = try XCTUnwrap(KeyPathActionURI(string: "keypath://launch/Safari"))

        center.post(KanataHrmTraceEvent(
            key: "f", decision: .hold, reason: .oppositeHand, decideLatencyMs: 209,
            nextKey: "j", nextKeyHand: .right
        ))
        center.post(KanataActionDispatched(uri: uri))
        await flushNotificationsAndBatch(service)

        let cards = service.segments.compactMap { segment -> EventCardKind? in
            guard case let .eventCard(card) = segment else { return nil }
            return card.cardKind
        }
        guard cards.count == 2,
              case let .hrmDecision(trace) = cards[0],
              case let .actionDispatched(action) = cards[1]
        else { return XCTFail("Expected HRM and action cards in order") }
        XCTAssertEqual(trace.key, "f")
        XCTAssertEqual(trace.decision, .hold)
        XCTAssertEqual(trace.reason, .oppositeHand)
        XCTAssertEqual(trace.nextKey, "j")
        XCTAssertEqual(trace.decideLatencyMs, 209)
        XCTAssertEqual(trace.configuredThresholdMs, 210)
        XCTAssertEqual(action.action, uri.action)
        XCTAssertEqual(action.target, uri.target)
        XCTAssertEqual(action.uri, uri.url.absoluteString)
    }

    // MARK: - Recording Toggle

    func testRecordingPauseSuppressesIngestion() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        service.isRecording = false
        postKeyInput(center, key: "a")
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 0)
    }

    // MARK: - Clear

    func testClearRemovesAllEvents() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        await flushNotificationsAndBatch(service)
        XCTAssertEqual(service.eventCount, 1)
        service.clearEvents()
        XCTAssertEqual(service.eventCount, 0)
        XCTAssertTrue(service.segments.isEmpty)
    }

    // MARK: - Threshold

    func testNearThresholdComputation() {
        XCTAssertTrue(KeystrokeHistoryService.computeNearThreshold(latencyMs: 190, thresholdMs: 200))
        XCTAssertTrue(KeystrokeHistoryService.computeNearThreshold(latencyMs: 210, thresholdMs: 200))
        XCTAssertFalse(KeystrokeHistoryService.computeNearThreshold(latencyMs: 100, thresholdMs: 200))
        XCTAssertFalse(KeystrokeHistoryService.computeNearThreshold(latencyMs: nil, thresholdMs: 200))
        XCTAssertFalse(KeystrokeHistoryService.computeNearThreshold(latencyMs: 190, thresholdMs: nil))
    }

    // MARK: - Non-Printable Keys

    func testNonPrintableKeyBreaksTextRun() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        postKeyInput(center, key: "b")
        postKeyInput(center, key: "bspc")
        postKeyInput(center, key: "c")
        await flushNotificationsAndBatch(service)
        // Should be: textRun("ab"), eventCard(bspc), textRun("c")
        XCTAssertEqual(service.segments.count, 3)
        if case let .textRun(run) = service.segments[0] {
            XCTAssertEqual(run.characters.map(\.displayChar).joined(), "ab")
        } else {
            XCTFail("Expected text run at index 0")
        }
        if case let .eventCard(card) = service.segments[1],
           case let .nonPrintableKeys(keys) = card.cardKind
        {
            XCTAssertEqual(keys.first?.key, "bspc")
        } else {
            XCTFail("Expected non-printable key card at index 1")
        }
    }
}
