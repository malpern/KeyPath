import AppKit
@testable import KeyPathAppKit
import XCTest

@MainActor
final class OverlayDismissalTests: XCTestCase {
    func testInstantCloseRejectsAlreadyQueuedOpeningTick() async throws {
        let controller = LiveKeyboardOverlayController.shared
        let previousWindow = controller.window
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.window = window
        defer {
            controller.finalizeInspectorAnimation()
            controller.window = previousWindow
            window.close()
        }
        controller.uiState.inspectorReveal = 0
        controller.uiState.isInspectorOpen = false
        controller.uiState.isInspectorAnimating = true
        controller.animateInspectorReveal(to: 1)
        let openingTimer = try XCTUnwrap(controller.inspectorAnimationTimer)
        openingTimer.fire() // Queues a MainActor update that must not survive the close.
        controller.closeInspector(animated: false)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertFalse(openingTimer.isValid)
        XCTAssertNil(controller.inspectorAnimationTimer)
        XCTAssertEqual(controller.uiState.inspectorReveal, 0)
        XCTAssertFalse(controller.uiState.isInspectorOpen)
        XCTAssertFalse(controller.uiState.isInspectorAnimating)
    }

    func testExplicitClosePreventsAutomaticShow() {
        let controller = LiveKeyboardOverlayController.shared
        let defaults = UserDefaults.standard
        let keys = ["LiveKeyboardOverlay.userExplicitlyHidden", "LiveKeyboardOverlay.isVisible"]
        let saved = keys.map { defaults.object(forKey: $0) }
        let previousWindow = controller.window
        controller.window = nil
        defer {
            controller.window = previousWindow
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: keys[0])
        controller.hideExplicitly()
        XCTAssertTrue(defaults.bool(forKey: keys[0]))
        XCTAssertFalse(controller.canAutoShow)
    }
}
