import AppKit
import KeyPathCore
import SwiftUI

/// Floating window that displays keyboard visualization
@MainActor
class KeyboardVisualizationWindow: NSWindow {
    private let viewModel: KeyboardVisualizationViewModel

    init() {
        let viewModel = KeyboardVisualizationViewModel()
        self.viewModel = viewModel

        // Calculate initial window size based on layout aspect ratio
        let layout = viewModel.layout
        let aspectRatio = layout.totalWidth / layout.totalHeight
        let defaultHeight: CGFloat = 300
        let defaultWidth = defaultHeight * aspectRatio

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth + 32, height: defaultHeight + 32),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        // Window configuration
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = true
        isMovableByWindowBackground = true
        hasShadow = true

        // Position at center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - (defaultWidth + 32) / 2
            let y = screenFrame.midY - (defaultHeight + 32) / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Set content view with SwiftUI
        contentView = NSHostingView(rootView: KeyboardView(viewModel: viewModel))
    }

    func show() {
        viewModel.startCapturing()
        alphaValue = 1.0
        orderFront(nil)
        AppLogger.shared.log("⌨️ [KeyboardViz] Window shown")
    }

    func hide() {
        viewModel.stopCapturing()
        orderOut(nil)
        AppLogger.shared.log("⌨️ [KeyboardViz] Window hidden")
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
}

/// Manager for the keyboard visualization window
@MainActor
class KeyboardVisualizationManager: ObservableObject {
    static let shared = KeyboardVisualizationManager()

    private var window: KeyboardVisualizationWindow?

    private init() {}

    func show() {
        if window == nil {
            window = KeyboardVisualizationWindow()
        }
        window?.show()
    }

    func hide() {
        window?.hide()
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
}

