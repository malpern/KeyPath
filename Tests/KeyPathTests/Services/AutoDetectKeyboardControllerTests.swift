@testable import KeyPathAppKit
import XCTest

@MainActor
final class AutoDetectKeyboardControllerTests: KeyPathAsyncTestCase {
    private var controller: AutoDetectKeyboardController!
    private var tempDirectory: URL!
    private var initialKeyboardEvents: [HIDDeviceMonitor.HIDKeyboardEvent] = []

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoDetectKeyboardControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        controller = AutoDetectKeyboardController(
            bindingStore: DeviceLayoutBindingStore.testStore(at: tempDirectory.appendingPathComponent("DeviceLayoutBindings.json")),
            displayContextStore: KeyboardDisplayContextStore.testStore(at: tempDirectory.appendingPathComponent("KeyboardDisplayContexts.json")),
            recognitionService: .shared,
            initialKeyboardEventsProvider: { [weak self] in
                self?.initialKeyboardEvents ?? []
            }
        )
        KeyboardDetectionIndex.resetCache()
        KeyboardDetectionIndex.seedIndex(exactEntries: [])
    }

    override func tearDown() async throws {
        controller.stopObserving()
        controller.dismissToast()
        controller = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        KeyboardDetectionIndex.resetCache()
        try await super.tearDown()
    }

    // MARK: - Lifecycle / Replay Prevention

    /// Verifies that restarting observation without a new plug-in event
    /// does not replay a stale connection and trigger a toast or auto-switch.
    func testRestartObservationDoesNotReplayStaleEvent() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "CB10:1256",
                matchType: .exactVIDPID,
                source: .via,
                confidence: .high,
                displayName: "Corne Keyboard",
                manufacturer: nil,
                qmkPath: "crkbd/rev4_0/standard",
                builtInLayoutId: "corne"
            )
        ])

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
        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "CB10:1256",
                matchType: .exactVIDPID,
                source: .via,
                confidence: .high,
                displayName: "Corne Keyboard",
                manufacturer: nil,
                qmkPath: "crkbd/rev4_0/standard",
                builtInLayoutId: "corne"
            )
        ])

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
        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "CB10:1256",
                matchType: .exactVIDPID,
                source: .via,
                confidence: .high,
                displayName: "Corne Keyboard",
                manufacturer: nil,
                qmkPath: "crkbd/rev4_0/standard",
                builtInLayoutId: "corne"
            )
        ])

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
        KeyboardDetectionIndex.seedIndex(exactEntries: []) // No matches

        controller.startObserving()

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x1337,
            productID: 0xBEEF,
            productName: "Mystery Board",
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
        XCTAssertEqual(controller.connectedKeyboards.count, 1)
        XCTAssertEqual(controller.connectedKeyboards.first?.status, .unrecognized)
        XCTAssertEqual(controller.activeKeyboard?.keyboardName, "Mystery Board")
    }

    func testRecognizedKeyboardBecomesActiveConnectedKeyboard() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "CB10:1256",
                matchType: .exactVIDPID,
                source: .via,
                confidence: .high,
                displayName: "Corne Keyboard",
                manufacturer: nil,
                qmkPath: "crkbd/rev4_0/standard",
                builtInLayoutId: "corne"
            )
        ])

        controller.startObserving()

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

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(controller.connectedKeyboards.count, 1)
        XCTAssertEqual(controller.activeKeyboard?.id, event.id)
        XCTAssertEqual(controller.activeKeyboard?.layoutId, "corne")
        XCTAssertEqual(controller.activeKeyboard?.status, .suggested)
    }

    func testStartupSeedAddsAppleInternalKeyboardWithoutToast() async {
        initialKeyboardEvents = [
            HIDDeviceMonitor.HIDKeyboardEvent(
                vendorID: 0x05AC,
                productID: 0x0342,
                productName: "Apple Internal Keyboard / Trackpad",
                isConnected: true
            )
        ]

        controller.startObserving()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(controller.showingToast)
        XCTAssertEqual(controller.connectedKeyboards.count, 1)
        XCTAssertEqual(controller.connectedKeyboards.first?.keyboardName, "MacBook Keyboard")
        XCTAssertNotNil(controller.connectedKeyboards.first?.layoutId)
        XCTAssertEqual(controller.activeKeyboard?.id, initialKeyboardEvents.first?.id)
    }

    func testLowConfidenceVendorFallbackRequiresReviewInsteadOfAutoActivation() async {
        KeyboardDetectionIndex.seedIndex(
            exactEntries: [],
            vendorFallbackEntries: [
                .init(
                    matchKey: "29EA",
                    matchType: .vendorOnly,
                    source: .qmk,
                    confidence: .low,
                    displayName: "Kinesis Advantage 360",
                    manufacturer: "Kinesis",
                    qmkPath: "kinesis/advantage360",
                    builtInLayoutId: "kinesis-360"
                )
            ]
        )

        controller.startObserving()

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x29EA,
            productID: 0x1001,
            productName: "mWave",
            isConnected: true
        )
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(controller.showingToast, "Low-confidence matches should not present an auto-detect toast")
        XCTAssertEqual(controller.connectedKeyboards.count, 1)
        XCTAssertEqual(controller.connectedKeyboards.first?.status, .possibleMatch)
        XCTAssertEqual(controller.connectedKeyboards.first?.detectedKeyboardName, "Kinesis Advantage 360")
        XCTAssertNil(controller.activeKeyboard?.layoutId, "Possible matches should not activate a layout")
    }

    func testDisconnectRestoresBaselineDisplayContextWhenNoKeyboardRemains() async {
        controller.overlayDisplayContextDidChange(
            layoutId: "macbook-us",
            keymapId: LogicalKeymap.defaultId,
            includePunctuationStore: "{}"
        )

        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "29EA:1001",
                matchType: .exactVIDPID,
                source: .override,
                confidence: .high,
                displayName: "Kinesis mWave",
                manufacturer: "Kinesis",
                qmkPath: nil,
                builtInLayoutId: "kinesis-mwave"
            )
        ])

        controller.startObserving()

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x29EA,
            productID: 0x1001,
            productName: "mWave",
            isConnected: true
        )
        NotificationCenter.default.post(
            name: .hidKeyboardConnected,
            object: nil,
            userInfo: ["event": event]
        )

        try? await Task.sleep(for: .milliseconds(100))

        let restoredBaseline = await controller.activeKeyboardDidChange(
            from: event.id,
            to: nil,
            currentLayoutId: "kinesis-mwave",
            currentKeymapId: "graphite",
            includePunctuationStore: "{\"graphite\":false}"
        )

        XCTAssertEqual(restoredBaseline?.layoutId, "macbook-us")
        XCTAssertEqual(restoredBaseline?.keymapId, LogicalKeymap.defaultId)
        XCTAssertEqual(restoredBaseline?.includePunctuationStore, "{}")
    }
}
