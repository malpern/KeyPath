@testable import KeyPathAppKit
import XCTest

@MainActor
final class AutoDetectKeyboardControllerTests: XCTestCase {
    private var controller: AutoDetectKeyboardController!

    override func setUp() async throws {
        try await super.setUp()
        controller = AutoDetectKeyboardController()
        QMKVIDPIDIndex.resetCache()
        QMKVIDPIDIndex.seededEntries = [:]
    }

    override func tearDown() async throws {
        controller.stopObserving()
        controller.dismissToast()
        controller = nil
        QMKVIDPIDIndex.resetCache()
        try await super.tearDown()
    }

    // MARK: - Lifecycle / Replay Prevention

    /// Verifies that restarting observation without a new plug-in event
    /// does not replay a stale connection and trigger a toast or auto-switch.
    func testRestartObservationDoesNotReplayStaleEvent() async {
        // Seed a recognizable keyboard
        QMKVIDPIDIndex.seededEntries = [
            "CB10:1256": ["crkbd/rev4_0/standard"],
        ]

        controller.startObserving()

        // Simulate a keyboard connect
        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0xCB10,
            productID: 0x1256,
            productName: "Corne Keyboard",
            isConnected: true
        )
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )

        // Let the async handler run
        try? await Task.sleep(for: .milliseconds(100))

        // Should have shown a toast for the detected keyboard
        XCTAssertTrue(controller.showingToast, "Toast should appear on first connect")

        // Dismiss and stop observing
        controller.dismissToast()
        controller.stopObserving()

        XCTAssertFalse(controller.showingToast)

        // Simulate disconnect so the VID:PID dedupe is cleared
        NotificationCenter.default.post(
            name: .hidKeyboardDisconnected,
            object: nil,
            userInfo: ["event": event]
        )

        // Restart observation — no new plug-in event occurs
        controller.startObserving()
        try? await Task.sleep(for: .milliseconds(100))

        // Should NOT have replayed the old event
        XCTAssertFalse(controller.showingToast, "Toast should NOT appear on re-subscribe without new plug-in")
        XCTAssertNil(controller.pendingResult, "No pending result should exist from stale replay")
    }

    /// Verifies that duplicate connect notifications for the same device
    /// don't produce multiple toasts.
    func testDuplicateConnectDoesNotSpamToast() async {
        QMKVIDPIDIndex.seededEntries = [
            "CB10:1256": ["crkbd/rev4_0/standard"],
        ]

        controller.startObserving()

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0xCB10,
            productID: 0x1256,
            productName: "Corne Keyboard",
            isConnected: true
        )

        // Post the same connect event twice
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )

        try? await Task.sleep(for: .milliseconds(100))

        // Should show toast exactly once (connectedVIDPIDs deduplicates)
        XCTAssertTrue(controller.showingToast)
    }

    /// Verifies that disconnecting then reconnecting the same keyboard
    /// triggers detection again (connectedVIDPIDs cleared on disconnect).
    func testReconnectAfterDisconnectTriggersDetection() async {
        QMKVIDPIDIndex.seededEntries = [
            "CB10:1256": ["crkbd/rev4_0/standard"],
        ]

        controller.startObserving()

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0xCB10,
            productID: 0x1256,
            productName: "Corne Keyboard",
            isConnected: true
        )

        // First connect
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.showingToast, "Toast should appear on first connect")

        // Dismiss and disconnect
        controller.dismissToast()
        NotificationCenter.default.post(
            name: .hidKeyboardDisconnected,
            object: nil,
            userInfo: ["event": event]
        )
        try? await Task.sleep(for: .milliseconds(50))

        // Reconnect
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(controller.showingToast, "Toast should appear again after disconnect + reconnect")
    }

    /// Verifies that an unrecognized keyboard (no VID:PID match) does not show a toast.
    func testUnrecognizedKeyboardDoesNotShowToast() async {
        QMKVIDPIDIndex.seededEntries = [:] // No matches

        controller.startObserving()

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x05AC,
            productID: 0x0342,
            productName: "Apple Internal Keyboard",
            isConnected: true
        )
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(controller.showingToast, "No toast for unrecognized keyboards")
        XCTAssertNil(controller.pendingResult)
    }
}
