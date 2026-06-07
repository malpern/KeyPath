@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Tests for event deduplication in RecentKeypressesService
@MainActor
final class RecentKeypressesServiceTests: XCTestCase {
    var service: RecentKeypressesService!
    private var notificationCenter: NotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        // Create fresh service for each test with isolated notification center
        notificationCenter = NotificationCenter()
        service = RecentKeypressesService.makeTestInstance(notificationCenter: notificationCenter)
        service.clearEvents()
        service.isRecording = true
    }

    override func tearDown() async throws {
        service.clearEvents()
        notificationCenter = nil
        try await super.tearDown()
    }

    private func postKey(
        _ key: String,
        action: String,
        observedAt: Date = Date(timeIntervalSince1970: 1)
    ) {
        service.recordKeypressForTesting(key: key, action: action, observedAt: observedAt)
    }

    private func postLayer(_ layerName: String) {
        service.setCurrentLayerForTesting(layerName)
    }

    private func postKeyNotification(
        _ key: String,
        action: String,
        observedAt: Date = Date(timeIntervalSince1970: 1),
        listenerSessionID: Int? = nil,
        kanataTimestamp: UInt64? = nil
    ) {
        var userInfo: [String: Any] = [
            "key": key,
            "action": action,
            "observedAt": observedAt,
        ]
        if let listenerSessionID {
            userInfo["listenerSessionID"] = listenerSessionID
        }
        if let kanataTimestamp {
            userInfo["kanataTimestamp"] = kanataTimestamp
        }
        notificationCenter.post(name: .kanataKeyInput, object: nil, userInfo: userInfo)
    }

    // MARK: - Deduplication Tests

    func testDeduplication_DuplicateWithin100ms_IsSkipped() {
        // Post first event
        postKey("a", action: "press")

        let eventsAfterFirst = service.events.count
        XCTAssertEqual(eventsAfterFirst, 1, "First event should be added")

        // Post duplicate within 100ms
        postKey("a", action: "press")

        let eventsAfterDuplicate = service.events.count
        XCTAssertEqual(
            eventsAfterDuplicate, 1,
            "Duplicate event within 100ms should be skipped"
        )
    }

    func testDeduplication_DifferentKeyWithin100ms_IsAccepted() {
        // Post first event
        postKey("a", action: "press")

        // Post different key within 100ms
        postKey("b", action: "press")

        XCTAssertEqual(
            service.events.count, 2,
            "Different key within 100ms should be accepted"
        )
    }

    func testDeduplication_DifferentActionWithin100ms_IsAccepted() {
        // Post press event
        postKey("a", action: "press")

        // Post release event within 100ms
        postKey("a", action: "release")

        XCTAssertEqual(
            service.events.count, 2,
            "Different action within 100ms should be accepted"
        )
    }

    func testDeduplication_SameKeyAfter100ms_IsAccepted() {
        let first = Date(timeIntervalSince1970: 1)
        // Post first event
        postKey("a", action: "press", observedAt: first)

        // Post same key after 100ms
        postKey("a", action: "press", observedAt: first.addingTimeInterval(0.110))

        XCTAssertEqual(
            service.events.count, 2,
            "Same key after 100ms should be accepted (legitimate double letter)"
        )
    }

    func testDeduplication_DoubleLetterTyping_IsAccepted() {
        let start = Date(timeIntervalSince1970: 1)
        // Simulate typing double 't' (like in "letter")
        // The two 't' presses should both be accepted

        // Type first 't'
        postKey("t", action: "press", observedAt: start)

        postKey("t", action: "release", observedAt: start.addingTimeInterval(0.060))

        // Type second 't' - should be >100ms after first 't' press
        postKey("t", action: "press", observedAt: start.addingTimeInterval(0.120))

        postKey("t", action: "release", observedAt: start.addingTimeInterval(0.180))

        // Should have 4 events (2 't' presses + 2 't' releases)
        XCTAssertEqual(
            service.events.count, 4,
            "Double letter typing should produce all 4 events (press/release x2)"
        )

        // Count 't' press events - should be 2
        let tPressEvents = service.events.filter { $0.key == "t" && $0.action == "press" }
        XCTAssertEqual(
            tPressEvents.count, 2,
            "Both 't' press events should be recorded"
        )

        // Count 't' release events - should be 2
        let tReleaseEvents = service.events.filter { $0.key == "t" && $0.action == "release" }
        XCTAssertEqual(
            tReleaseEvents.count, 2,
            "Both 't' release events should be recorded"
        )
    }

    func testDeduplication_LayerChange_IsTreatedSeparately() {
        // Post event in base layer
        postLayer("base")

        postKey("a", action: "press")

        // Change layer
        postLayer("nav")

        // Post same key in different layer within 100ms
        postKey("a", action: "press")

        XCTAssertEqual(
            service.events.count, 2,
            "Same key in different layer should be accepted (different context)"
        )
    }

    func testDeduplication_TCPReplayScenario_IsFiltered() {
        let first = Date(timeIntervalSince1970: 1)
        // Simulate TCP duplicate: same event arrives twice within milliseconds

        // First event
        postKey("a", action: "press", observedAt: first)

        postKey("a", action: "press", observedAt: first.addingTimeInterval(0.002))

        XCTAssertEqual(
            service.events.count, 1,
            "TCP duplicate within 2ms should be filtered"
        )
    }

    func testDeduplication_RapidPressRelease_BothAccepted() {
        let first = Date(timeIntervalSince1970: 1)
        // Simulate rapid press-release cycle (like fast typing)

        postKey("a", action: "press", observedAt: first)
        postKey("a", action: "release", observedAt: first.addingTimeInterval(0.050))

        XCTAssertEqual(
            service.events.count, 2,
            "Press and release should both be recorded"
        )

        // Verify order (newest first)
        XCTAssertEqual(service.events[0].action, "release")
        XCTAssertEqual(service.events[1].action, "press")
    }

    func testMetadata_ListenerSessionAndKanataTimestamp_AreStoredOnEvent() {
        service.recordKeypressForTesting(
            key: "a",
            action: "press",
            observedAt: Date(timeIntervalSince1970: 1),
            listenerSessionID: 17,
            kanataTimestamp: 55
        )

        XCTAssertEqual(service.events[0].listenerSessionID, 17)
        XCTAssertEqual(service.events[0].kanataTimestamp, 55)
    }

    func testNotificationCenterKeyInputPath_ParsesUserInfo() async {
        postKeyNotification(
            "a",
            action: "press",
            observedAt: Date(timeIntervalSince1970: 2),
            listenerSessionID: 18,
            kanataTimestamp: 56
        )
        await Task.yield()

        XCTAssertEqual(service.events.count, 1)
        XCTAssertEqual(service.events[0].key, "a")
        XCTAssertEqual(service.events[0].action, "press")
        XCTAssertEqual(service.events[0].timestamp, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(service.events[0].listenerSessionID, 18)
        XCTAssertEqual(service.events[0].kanataTimestamp, 56)
    }

    // MARK: - Recording Toggle Tests

    func testRecordingToggle_WhenDisabled_EventsNotAdded() {
        service.isRecording = false

        postKey("a", action: "press")

        XCTAssertEqual(
            service.events.count, 0,
            "Events should not be added when recording is disabled"
        )
    }

    func testRecordingToggle_WhenReEnabled_EventsAdded() {
        service.isRecording = false
        service.toggleRecording()

        XCTAssertTrue(service.isRecording, "Recording should be re-enabled")

        postKey("a", action: "press")

        XCTAssertEqual(
            service.events.count, 1,
            "Events should be added when recording is re-enabled"
        )
    }

    // MARK: - Edge Case Tests

    func testDeduplication_ChecksLast10Events() {
        // Add 15 events of different keys
        let start = Date(timeIntervalSince1970: 1)
        for i in 0 ..< 15 {
            postKey("key\(i)", action: "press", observedAt: start.addingTimeInterval(Double(i) * 0.001))
        }

        // Now post duplicate of first key within 100ms total
        // But it's the 16th event, so more than 10 events ago
        postKey("key0", action: "press", observedAt: start.addingTimeInterval(0.016))

        // Should be accepted because deduplication only checks last 10 events
        XCTAssertEqual(
            service.events.count, 16,
            "Event should be accepted if duplicate is beyond last 10 events"
        )
    }

    func testClearEvents_RemovesAllEvents() {
        // Add some events
        postKey("a", action: "press")

        XCTAssertGreaterThan(service.events.count, 0)

        service.clearEvents()

        XCTAssertEqual(service.events.count, 0, "Clear should remove all events")
    }
}
