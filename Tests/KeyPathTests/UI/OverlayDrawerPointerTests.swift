import AppKit
@testable import KeyPathAppKit
import SwiftUI
import XCTest

@MainActor
final class OverlayDrawerPointerTests: XCTestCase {
    func testDrawerKeyRespondsToPointerWhenClosed() async throws {
        try await checkPointerClick(inspectorVisible: false)
    }

    func testDrawerKeyRespondsToPointerWhenOpen() async throws {
        try await checkPointerClick(inspectorVisible: true)
    }

    private func checkPointerClick(inspectorVisible: Bool) async throws {
        _ = NSApplication.shared
        // Exactly one click: a second fulfillment fails the test.
        let clickedOnce = expectation(description: "drawer key clicked once")
        clickedOnce.assertForOverFulfill = true
        let key = PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 0, y: 0, width: 1, height: 1)
        let view = OverlayKeyboardView(
            layout: PhysicalLayout(id: "drawer-test", name: "Drawer", keys: [key]),
            keymap: .qwertyUS, includeKeymapPunctuation: false, pressedKeyCodes: [],
            onKeyClick: { clicked, _ in
                XCTAssertEqual(clicked.keyCode, 0xFFFF)
                clickedOnce.fulfill()
            },
            isInspectorVisible: inspectorVisible
        )
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            view.frame(width: 100, height: 100)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { _ in }.onEnded { _ in }))
        window.orderFront(nil)
        defer { window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        // Let SwiftUI install its recognizers before delivering local window events.
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: type == .leftMouseDown ? 50 : 51, y: 50), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }
        // Tap disambiguation is asynchronous: the recognizer waits out the
        // double-click interval before reporting the click.
        await fulfillment(of: [clickedOnce], timeout: NSEvent.doubleClickInterval + 5)
    }
}
