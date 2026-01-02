import AppKit
import CoreGraphics

enum OverlayWindowFactory {
    static let overlayWindowTitle = "KeyPath Keyboard Overlay"

    static func windowStyle(useAccessibilityTestMode: Bool) -> NSWindow.StyleMask {
        useAccessibilityTestMode ? [.titled, .resizable, .closable] : [.borderless, .resizable]
    }

    static func defaultOrigin(visibleFrame: CGRect, windowSize: CGSize, margin: CGFloat) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - windowSize.width - margin,
            y: visibleFrame.minY + margin
        )
    }

    @MainActor
    static func configure(window: NSWindow, useAccessibilityTestMode _: Bool) {
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.title = overlayWindowTitle
        window.setAccessibilityIdentifier("keypath-keyboard-overlay-window")
        window.setAccessibilityLabel(overlayWindowTitle)

        // Always on top but not activating - prevents window from becoming key/main
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
    }
}
