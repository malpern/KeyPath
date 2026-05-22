@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class KeystrokeHistoryServiceTests: XCTestCase {
    private func postKeyInput(
        _ center: NotificationCenter,
        key: String,
        action: String = "press",
        kanataTimestamp: UInt64? = nil
    ) {
        var userInfo: [String: Any] = [
            "key": key,
            "action": action,
            "observedAt": Date(),
        ]
        if let ts = kanataTimestamp {
            userInfo["kanataTimestamp"] = ts
        }
        center.post(name: .kanataKeyInput, object: nil, userInfo: userInfo)
    }

    private func yieldForBatch() async {
        // Wait for notification dispatch + batch timer flush (100ms)
        try? await Task.sleep(nanoseconds: 150_000_000)
        await Task.yield()
        await Task.yield()
    }

    // MARK: - Event Ingestion

    func testKeyInputCreatesEvent() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        await yieldForBatch()
        XCTAssertEqual(service.eventCount, 1)
    }

    func testMultipleKeysGroupIntoTextRun() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        for key in ["h", "e", "l", "l", "o"] {
            postKeyInput(center, key: key)
        }
        await yieldForBatch()
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
        postKeyInput(center, key: "a", action: "press")
        postKeyInput(center, key: "a", action: "release")
        await yieldForBatch()
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
        center.post(name: .kanataLayerChanged, object: nil, userInfo: ["layerName": "nav"])
        await yieldForBatch()
        XCTAssertEqual(service.currentLayer, "nav")
    }

    func testLayerChangeCreatesLayerDivider() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        center.post(name: .kanataLayerChanged, object: nil, userInfo: ["layerName": "nav"])
        postKeyInput(center, key: "b")
        await yieldForBatch()
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
        center.post(name: .kanataHoldActivated, object: nil, userInfo: [
            "key": "caps",
            "action": "lctl+lmet+lalt+lsft",
            "reason": "opposite-hand",
            "kanataTimestamp": UInt64(1000),
        ])
        await yieldForBatch()
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
        center.post(name: .kanataTapActivated, object: nil, userInfo: [
            "key": "caps",
            "action": "esc",
            "reason": "release-before-timeout",
            "kanataTimestamp": UInt64(1000),
        ])
        await yieldForBatch()
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

    // MARK: - Recording Toggle

    func testRecordingPauseSuppressesIngestion() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        service.isRecording = false
        postKeyInput(center, key: "a")
        await yieldForBatch()
        XCTAssertEqual(service.eventCount, 0)
    }

    // MARK: - Clear

    func testClearRemovesAllEvents() async {
        let center = NotificationCenter()
        let service = KeystrokeHistoryService.makeTestInstance(notificationCenter: center)
        postKeyInput(center, key: "a")
        await yieldForBatch()
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
        await yieldForBatch()
        // Should be: textRun("ab"), eventCard(bspc), textRun("c")
        XCTAssertEqual(service.segments.count, 3)
        if case let .textRun(run) = service.segments[0] {
            XCTAssertEqual(run.characters.map(\.displayChar).joined(), "ab")
        } else {
            XCTFail("Expected text run at index 0")
        }
        if case let .eventCard(card) = service.segments[1],
           case let .nonPrintableKey(key, _) = card.cardKind
        {
            XCTAssertEqual(key, "bspc")
        } else {
            XCTFail("Expected non-printable key card at index 1")
        }
    }
}
