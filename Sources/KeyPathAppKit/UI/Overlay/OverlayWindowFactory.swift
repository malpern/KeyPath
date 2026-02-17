import AppKit
import CoreGraphics

enum OverlayWindowFactory {
    static let overlayWindowTitle = "Keypath"
    static let overlayAccessibilityLabel = "KeyPath Keyboard Overlay"

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
    static func configure(window: NSWindow, useAccessibilityTestMode: Bool) {
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.title = overlayWindowTitle
        window.setAccessibilityIdentifier("keypath-keyboard-overlay-window")
        window.setAccessibilityLabel(overlayAccessibilityLabel)

        // Always on top but not activating - prevents window from becoming key/main
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        if useAccessibilityTestMode {
            // In test mode, omit .ignoresCycle so the window appears in the
            // macOS accessibility tree and Peekaboo can discover it.
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
    }
}
