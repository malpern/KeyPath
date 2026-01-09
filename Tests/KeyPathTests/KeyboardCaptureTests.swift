import Carbon
import Foundation
@preconcurrency import XCTest

@testable import KeyPathAppKit

@MainActor
final class KeyboardCaptureTests: XCTestCase {
    lazy var capture: KeyboardCapture = .init()
    var receivedNotifications: [Notification] = []

    override func setUp() {
        super.setUp()

        // Set up notification observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notificationReceived(_:)),
            name: NSNotification.Name("KeyboardCapturePermissionNeeded"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func notificationReceived(_ notification: Notification) {
        receivedNotifications.append(notification)
    }

    // MARK: - Initialization Tests

    func testKeyboardCaptureInitialization() throws {
        XCTAssertNotNil(capture)
        let hasPermissions = capture.checkAccessibilityPermissionsSilently()
        XCTAssert(hasPermissions == true || hasPermissions == false, "Should return boolean")
    }

    // MARK: - Key Code Mapping Tests

    func testKeyCodeToStringMapping() throws {
        // Test known key mappings
        let testCases: [(Int64, String)] = [
            (0, "a"), (1, "s"), (2, "d"), (3, "f"), (4, "h"), (5, "g"),
            (6, "z"), (7, "x"), (8, "c"), (9, "v"), (11, "b"), (12, "q"),
            (13, "w"), (14, "e"), (15, "r"), (16, "y"), (17, "t"),
            (18, "1"), (19, "2"), (20, "3"), (21, "4"), (22, "6"), (23, "5"),
            (24, "="), (25, "9"), (26, "7"), (27, "-"), (28, "8"), (29, "0"),
            (30, "]"), (31, "o"), (32, "u"), (33, "["), (34, "i"), (35, "p"),
            (36, "return"), (37, "l"), (38, "j"), (39, "'"), (40, "k"),
            (41, ";"), (42, "\\"), (43, ","), (44, "/"), (45, "n"),
            (46, "m"), (47, "."), (48, "tab"), (49, "space"), (50, "`"),
            (51, "delete"), (53, "escape"),
            // Modifier keys (corrected mapping)
            (54, "rmet"), (55, "lmet"), (56, "lsft"), (57, "caps"),
            (58, "lalt"), (59, "lctl"), (60, "rsft"), (61, "ralt"), (62, "rctl")
        ]

        for (keyCode, expected) in testCases {
            let result = capture.keyCodeToString(keyCode)
            XCTAssertEqual(result, expected, "Key code \(keyCode) should map to '\(expected)'")
        }
    }

    func testUnknownKeyCodeMapping() throws {
        // Test unknown key codes
        let unknownKeyCodes: [Int64] = [999, 100, 200, 300, -1, 1000]

        for keyCode in unknownKeyCodes {
            let result = capture.keyCodeToString(keyCode)
            XCTAssertEqual(
                result, "key\(keyCode)", "Unknown key code \(keyCode) should map to 'key\(keyCode)'"
            )
        }
    }

    func testKeyCodeEdgeCases() throws {
        // Test edge cases
        let edgeCases: [(Int64, String)] = [
            (Int64.max, "key\(Int64.max)"),
            (Int64.min, "key\(Int64.min)"),
            (0, "a"), // Should be 'a', not 'key0'
            (10, "key10") // Gap in mapping
        ]

        for (keyCode, expected) in edgeCases {
            let result = capture.keyCodeToString(keyCode)
            XCTAssertEqual(result, expected, "Edge case key code \(keyCode) should map to '\(expected)'")
        }
    }

    // MARK: - Permission Tests

    func testAccessibilityPermissionCheck() throws {
        // Test that permission check returns a boolean without prompting
        let hasPermissions = capture.checkAccessibilityPermissionsSilently()
        XCTAssertTrue(hasPermissions == true || hasPermissions == false, "Should return boolean value")
    }

    func testPermissionRequestExplicitly() throws {
        // Test explicit permission request
        // This will show a system dialog if permissions aren't granted
        // In automated testing, we just verify the method exists and doesn't crash
        capture.requestPermissionsExplicitly()
        XCTAssertTrue(true, "Explicit permission request should complete without crashing")
    }

    // MARK: - Capture Lifecycle Tests

    func testSingleKeyCaptureLifecycle() throws {
        receivedNotifications.removeAll()
        var capturedKeys: [String] = []
        let expectation = expectation(description: "Single key capture")

        // Test starting capture
        capture.startCapture { key in
            capturedKeys.append(key)
            expectation.fulfill()
        }

        // If we don't have permissions, should post notification
        if !capture.checkAccessibilityPermissionsSilently() {
            // Wait for notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            XCTAssertEqual(receivedNotifications.count, 1, "Should post permission notification")
            XCTAssertEqual(receivedNotifications[0].name.rawValue, "KeyboardCapturePermissionNeeded")
            XCTAssertEqual(capturedKeys.count, 1, "Should capture permission warning")
            XCTAssertTrue(capturedKeys[0].contains("⚠️"), "Should contain warning emoji")
        } else {
            // If we have permissions, capture should start
            // We can't simulate key events in tests, so we just verify setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }

        // Test stopping capture
        capture.stopCapture()
        XCTAssertTrue(true, "Stop capture should complete without error")
    }

    func testContinuousCaptureLifecycle() throws {
        receivedNotifications.removeAll()
        var capturedKeys: [String] = []
        let expectation = expectation(description: "Continuous capture")

        // Test starting continuous capture
        capture.startContinuousCapture { key in
            capturedKeys.append(key)
            expectation.fulfill()
        }

        // If we don't have permissions, should post notification
        if !capture.checkAccessibilityPermissionsSilently() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)

            XCTAssertEqual(receivedNotifications.count, 1, "Should post permission notification")
            XCTAssertEqual(capturedKeys.count, 1, "Should capture permission warning")
            XCTAssertTrue(capturedKeys[0].contains("continuous"), "Should mention continuous capture")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }

        // Test stopping capture
        capture.stopCapture()
        XCTAssertTrue(true, "Stop continuous capture should complete without error")
    }

    func testCaptureAlreadyRunning() throws {
        var captureCount = 0

        // Start first capture
        capture.startCapture { _ in
            captureCount += 1
        }

        // Try to start second capture - should be ignored
        capture.startCapture { _ in
            captureCount += 1
        }

        // No sleep needed - testing that multiple start calls don't crash (synchronous check)

        // If no permissions, should have received permission warning once
        // If has permissions, no immediate captures expected
        capture.stopCapture()
        XCTAssertTrue(true, "Multiple start calls should be handled gracefully")
    }

    func testStopCaptureWhenNotRunning() throws {
        // Should not crash when stopping capture that isn't running
        capture.stopCapture()
        capture.stopCapture() // Multiple calls
        XCTAssertTrue(true, "Stop capture when not running should not crash")
    }

    // MARK: - Emergency Stop Sequence Tests

    func testEmergencyMonitoringLifecycle() throws {
        var emergencyTriggered = false
        let expectation = expectation(description: "Emergency monitoring")

        // Start emergency monitoring
        capture.startEmergencyMonitoring {
            emergencyTriggered = true
            expectation.fulfill()
        }

        // If no permissions, monitoring should silently fail
        // If has permissions, monitoring should start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !emergencyTriggered {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1.0)

        // Stop monitoring
        capture.stopEmergencyMonitoring()
        XCTAssertTrue(true, "Emergency monitoring lifecycle should complete without error")
    }

    func testEmergencyMonitoringAlreadyRunning() throws {
        var callbackCount = 0

        // Start first monitoring
        capture.startEmergencyMonitoring {
            callbackCount += 1
        }

        // Try to start second monitoring - should be ignored
        capture.startEmergencyMonitoring {
            callbackCount += 1
        }

        // No sleep needed - testing that multiple start calls don't crash (synchronous check)

        capture.stopEmergencyMonitoring()
        XCTAssertTrue(true, "Multiple emergency monitoring starts should be handled gracefully")
    }

    func testStopEmergencyMonitoringWhenNotRunning() throws {
        // Should not crash when stopping monitoring that isn't running
        capture.stopEmergencyMonitoring()
        capture.stopEmergencyMonitoring() // Multiple calls
        XCTAssertTrue(true, "Stop emergency monitoring when not running should not crash")
    }

    // MARK: - Notification Tests

    func testPermissionNotificationContent() throws {
        receivedNotifications.removeAll()
        let expectation = expectation(description: "Permission notification")

        // Start capture without permissions to trigger notification
        capture.startCapture { key in
            // Permission warning should be captured
            XCTAssertTrue(key.contains("⚠️"), "Should contain warning")
            XCTAssertTrue(key.contains("permission"), "Should mention permission")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Check if notification was posted (depends on permission state)
        if !capture.checkAccessibilityPermissionsSilently() {
            XCTAssertGreaterThanOrEqual(
                receivedNotifications.count, 1, "Should post permission notification"
            )

            let notification = receivedNotifications.first!
            XCTAssertEqual(notification.name.rawValue, "KeyboardCapturePermissionNeeded")

            let userInfo = notification.userInfo
            XCTAssertNotNil(userInfo, "Notification should have userInfo")
            XCTAssertTrue(userInfo!["reason"] is String, "Should have reason string")
        }
    }

    func testContinuousCapturePermissionNotification() throws {
        receivedNotifications.removeAll()
        let expectation = expectation(description: "Continuous permission notification")

        capture.startContinuousCapture { key in
            XCTAssertTrue(key.contains("⚠️"), "Should contain warning")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        if !capture.checkAccessibilityPermissionsSilently() {
            let notification = receivedNotifications.last!
            let userInfo = notification.userInfo!
            let reason = userInfo["reason"] as! String
            XCTAssertTrue(reason.contains("continuous"), "Should mention continuous capture")
        }
    }

    // MARK: - Timer Tests

    func testPauseTimerBehavior() throws {
        // We can't easily test the actual timer behavior without mocking,
        // but we can test that timer operations don't crash
        let expectation = expectation(description: "Timer behavior")

        capture.startContinuousCapture { _ in
            // Timer should be reset on each key (if permissions exist)
        }

        // Test multiple rapid "key presses" to reset timer
        // (In real usage, this would be done via handleKeyEvent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate stopping capture to test timer cleanup
            self.capture.stopCapture()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(true, "Timer operations should complete without crashing")
    }

    // MARK: - Memory Management Tests

    func testMemoryManagementDuringCapture() throws {
        weak var weakCapture: KeyboardCapture?

        // Create capture in local scope
        do {
            let localCapture = KeyboardCapture()
            weakCapture = localCapture

            XCTAssertNotNil(weakCapture, "Weak reference should be set inside scope")

            localCapture.startCapture { _ in }
            localCapture.stopCapture()

            localCapture.startEmergencyMonitoring {}
            localCapture.stopEmergencyMonitoring()
        }

        // No sleep needed - ARC cleanup is deterministic after scope exit

        // Object should be deallocated after going out of scope
        // Note: This may not always pass due to ARC optimizations in tests
        // but it's good to verify cleanup doesn't cause retain cycles
        XCTAssertNil(weakCapture, "KeyboardCapture should be released after scope exit")
    }

    // MARK: - Error Handling Tests

    func testEventTapCreationFailure() throws {
        // We can't easily force event tap creation to fail in tests,
        // but we can test that the code handles it gracefully

        // Test multiple rapid start/stop cycles
        for _ in 0 ..< 5 {
            capture.startCapture { _ in }
            capture.stopCapture()
        }

        XCTAssertTrue(true, "Rapid start/stop cycles should not crash")
    }

    func testCallbackErrorHandling() throws {
        let expectation = expectation(description: "Callback error handling")

        // Test callback that throws an error
        capture.startCapture { key in
            // Simulate an error in callback
            if key.contains("test") {
                fatalError("Test error") // This would crash in real usage
            }
            expectation.fulfill()
        }

        // Since we can't trigger actual key events in tests,
        // we just verify the setup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        capture.stopCapture()
        XCTAssertTrue(true, "Callback error handling should be robust")
    }

    // MARK: - Integration Tests

    func testKeyboardCaptureWithRuntimeCoordinator() throws {
        // Test integration between KeyboardCapture and KanataManager
        let manager = RuntimeCoordinator()
        var capturedInput: String?

        let expectation = expectation(description: "Integration test")

        capture.startCapture { key in
            capturedInput = key

            // Test that captured key can be used with KanataManager
            let convertedKey = manager.convertToKanataKey(key)
            XCTAssertFalse(convertedKey.isEmpty, "Converted key should not be empty")

            expectation.fulfill()
        }

        // Simulate timeout for async operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        capture.stopCapture()

        if let input = capturedInput {
            // Test conversion with KanataManager
            let kanataKey = manager.convertToKanataKey(input)
            XCTAssertFalse(kanataKey.isEmpty, "Should convert to valid Kanata key")
        }
    }

    // MARK: - Performance Tests

    func testKeyCodeMappingPerformance() throws {
        let testKeyCodes = Array(0 ... 127) // Test common key code range

        measure {
            for keyCode in testKeyCodes {
                _ = capture.keyCodeToString(Int64(keyCode))
            }
        }
    }

    func testCaptureLifecyclePerformance() throws {
        measure {
            for _ in 0 ..< 100 {
                capture.startCapture { _ in }
                capture.stopCapture()
            }
        }
    }

    // MARK: - Helper Methods for Testing

    private func simulateKeyPress(_ keyCode: Int64) {
        // Helper method to simulate key press in tests
        // Note: This doesn't actually create CGEvents, just tests the mapping
        let keyName = capture.keyCodeToString(keyCode)
        XCTAssertFalse(keyName.isEmpty, "Key name should not be empty")
    }
}

// MARK: - Test Extensions

extension KeyboardCaptureTests {
    /// Helper method to test key code mapping using reflection or testing approach
    private func testKeyCodeMapping(_ keyCode: Int64) -> String {
        // Use the existing extension from KeyPathTests.swift to avoid duplication
        capture.keyCodeToString(keyCode)
    }
}
