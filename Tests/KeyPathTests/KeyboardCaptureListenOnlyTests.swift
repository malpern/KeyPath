@testable import KeyPath
import XCTest

@MainActor
final class KeyboardCaptureListenOnlyTests: XCTestCase {
    func testListenOnlyEnabledWhenKanataRunning() {
        // Given
        FeatureFlags.setCaptureListenOnlyEnabled(true)
        let manager = KanataManager()
        manager.isRunning = true
        let capture = KeyboardCapture()
        capture.setEventRouter(nil, kanataManager: manager)

        // When
        let exp = expectation(description: "start")
        capture.startSequenceCapture(mode: .single) { _ in }
        // Allow setupEventTap to run on main loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // Then
        XCTAssertFalse(capture.suppressEvents, "Should not suppress events when using listen-only tap")

        capture.stopCapture()
    }

    func testRawModeWhenKanataNotRunning() {
        FeatureFlags.setCaptureListenOnlyEnabled(true)
        let manager = KanataManager()
        manager.isRunning = false
        let capture = KeyboardCapture()
        capture.setEventRouter(nil, kanataManager: manager)

        let exp = expectation(description: "start")
        capture.startSequenceCapture(mode: .single) { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(capture.suppressEvents, "Should suppress events in raw capture mode")

        capture.stopCapture()
    }

    func testRawModeWhenFeatureFlagDisabled() {
        FeatureFlags.setCaptureListenOnlyEnabled(false)
        let manager = KanataManager()
        manager.isRunning = true
        let capture = KeyboardCapture()
        capture.setEventRouter(nil, kanataManager: manager)

        let exp = expectation(description: "start")
        capture.startSequenceCapture(mode: .single) { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(capture.suppressEvents, "Flag off forces raw/suppress mode even if Kanata is running")

        capture.stopCapture()
        FeatureFlags.setCaptureListenOnlyEnabled(true) // cleanup
    }
}
