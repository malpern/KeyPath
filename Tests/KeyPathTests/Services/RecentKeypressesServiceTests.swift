@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Tests for event deduplication in RecentKeypressesService
@MainActor
final class RecentKeypressesServiceTests: XCTestCase {
    var service: RecentKeypressesService!
    private var notificationCenter: NotificationCenter!

    private func waitForEventsCount(
        _ expected: Int,
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if service.events.count == expected { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms backoff
        }
        XCTFail("Timed out waiting for events.count == \(expected). Got \(service.events.count)", file: file, line: line)
    }

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

    private func postKey(_ key: String, action: String) {
        notificationCenter.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: ["key": key, "action": action]
        )
    }

    private func postLayer(_ layerName: String) {
        notificationCenter.post(
            name: .kanataLayerChanged,
            object: nil,
            userInfo: ["layerName": layerName]
        )
    }

    // MARK: - Deduplication Tests

    func testDeduplication_DuplicateWithin100ms_IsSkipped() async {
        // Post first event
        postKey("a", action: "press")

        await waitForEventsCount(1)

        let eventsAfterFirst = service.events.count
        XCTAssertEqual(eventsAfterFirst, 1, "First event should be added")

        // Post duplicate within 100ms
        postKey("a", action: "press")

        await waitForEventsCount(1)

        let eventsAfterDuplicate = service.events.count
        XCTAssertEqual(
            eventsAfterDuplicate, 1,
            "Duplicate event within 100ms should be skipped"
        )
    }

    func testDeduplication_DifferentKeyWithin100ms_IsAccepted() async {
        // Post first event
        postKey("a", action: "press")

        await waitForEventsCount(1)

        // Post different key within 100ms
        postKey("b", action: "press")

        await waitForEventsCount(2)

        XCTAssertEqual(
            service.events.count, 2,
            "Different key within 100ms should be accepted"
        )
    }

    func testDeduplication_DifferentActionWithin100ms_IsAccepted() async {
        // Post press event
        postKey("a", action: "press")

        await waitForEventsCount(1)

        // Post release event within 100ms
        postKey("a", action: "release")

        await waitForEventsCount(2)

        XCTAssertEqual(
            service.events.count, 2,
            "Different action within 100ms should be accepted"
        )
    }

    func testDeduplication_SameKeyAfter100ms_IsAccepted() async throws {
        // Post first event
        postKey("a", action: "press")

        // Wait longer than deduplication window
        try await Task.sleep(nanoseconds: 110_000_000) // 110ms

        // Post same key after 100ms
        postKey("a", action: "press")

        await waitForEventsCount(2)

        XCTAssertEqual(
            service.events.count, 2,
            "Same key after 100ms should be accepted (legitimate double letter)"
        )
    }

    func testDeduplication_DoubleLetterTyping_IsAccepted() async throws {
        // Simulate typing double 't' (like in "letter")
        // The two 't' presses should both be accepted

        // Type first 't'
        postKey("t", action: "press")
        try await Task.sleep(nanoseconds: 60_000_000) // 60ms hold

        postKey("t", action: "release")
        try await Task.sleep(nanoseconds: 60_000_000) // 60ms gap (total 120ms from first press)

        // Type second 't' - should be >100ms after first 't' press
        postKey("t", action: "press")
        try await Task.sleep(nanoseconds: 60_000_000) // 60ms hold

        postKey("t", action: "release")
        try await Task.sleep(nanoseconds: 10_000_000) // Wait for processing

        await waitForEventsCount(4)

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

    func testDeduplication_LayerChange_IsTreatedSeparately() async {
        // Post event in base layer
        postLayer("base")

        postKey("a", action: "press")
        await waitForEventsCount(1)

        // Change layer
        postLayer("nav")

        // Post same key in different layer within 100ms
        postKey("a", action: "press")
        await waitForEventsCount(2)

        XCTAssertEqual(
            service.events.count, 2,
            "Same key in different layer should be accepted (different context)"
        )
    }

    func testDeduplication_TCPReplayScenario_IsFiltered() async throws {
        // Simulate TCP duplicate: same event arrives twice within milliseconds

        // First event
        postKey("a", action: "press")

        // Duplicate arrives 2ms later (TCP buffer replay)
        try await Task.sleep(nanoseconds: 2_000_000) // 2ms

        postKey("a", action: "press")

        await waitForEventsCount(1)

        XCTAssertEqual(
            service.events.count, 1,
            "TCP duplicate within 2ms should be filtered"
        )
    }

    func testDeduplication_RapidPressRelease_BothAccepted() async throws {
        // Simulate rapid press-release cycle (like fast typing)

        postKey("a", action: "press")

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        postKey("a", action: "release")

        await waitForEventsCount(2)

        XCTAssertEqual(
            service.events.count, 2,
            "Press and release should both be recorded"
        )

        // Verify order (newest first)
        XCTAssertEqual(service.events[0].action, "release")
        XCTAssertEqual(service.events[1].action, "press")
    }

    func testMetadata_ListenerSessionAndKanataTimestamp_AreStoredOnEvent() async {
        notificationCenter.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: [
                "key": "a",
                "action": "press",
                "listenerSessionID": 17,
                "kanataTimestamp": UInt64(55),
                "observedAt": Date(timeIntervalSince1970: 1)
            ]
        )

        await waitForEventsCount(1)

        XCTAssertEqual(service.events[0].listenerSessionID, 17)
        XCTAssertEqual(service.events[0].kanataTimestamp, 55)
    }

    // MARK: - Recording Toggle Tests

    func testRecordingToggle_WhenDisabled_EventsNotAdded() async {
        service.isRecording = false

        postKey("a", action: "press")

        await waitForEventsCount(0)

        XCTAssertEqual(
            service.events.count, 0,
            "Events should not be added when recording is disabled"
        )
    }

    func testRecordingToggle_WhenReEnabled_EventsAdded() async {
        service.isRecording = false
        service.toggleRecording()

        XCTAssertTrue(service.isRecording, "Recording should be re-enabled")

        postKey("a", action: "press")

        await waitForEventsCount(1)

        XCTAssertEqual(
            service.events.count, 1,
            "Events should be added when recording is re-enabled"
        )
    }

    // MARK: - Edge Case Tests

    func testDeduplication_ChecksLast10Events() async throws {
        // Add 15 events of different keys
        for i in 0 ..< 15 {
            postKey("key\(i)", action: "press")
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms between events
        }

        await waitForEventsCount(15)

        // Now post duplicate of first key within 100ms total
        // But it's the 16th event, so more than 10 events ago
        postKey("key0", action: "press")

        await waitForEventsCount(16)

        // Should be accepted because deduplication only checks last 10 events
        XCTAssertEqual(
            service.events.count, 16,
            "Event should be accepted if duplicate is beyond last 10 events"
        )
    }

    func testClearEvents_RemovesAllEvents() async {
        // Add some events
        postKey("a", action: "press")

        await waitForEventsCount(1)

        XCTAssertGreaterThan(service.events.count, 0)

        service.clearEvents()

        XCTAssertEqual(service.events.count, 0, "Clear should remove all events")
    }
}
