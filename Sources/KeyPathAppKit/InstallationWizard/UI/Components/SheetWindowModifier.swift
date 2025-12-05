import AppKit
import ObjectiveC
import SwiftUI

/// Modifier to customize sheet window appearance (remove border, set background)
/// Also ensures window resizes from bottom (top-left corner stays stable)
struct SheetWindowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WizardDesign.Colors.wizardBackground)
            .onAppear {
                // Customize the sheet window appearance when it appears
                // Use a slight delay to ensure the window is fully created
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    // Find the sheet window
                    for window in NSApp.windows {
                        // Check if this is a sheet window (has a parent or is a sheet)
                        if window.isSheet || window.sheetParent != nil {
                            // Remove border by setting transparent background and removing border
                            window.backgroundColor = .clear
                            window.isOpaque = false
                            window.hasShadow = true

                            // Configure window to resize from bottom (keep top-left stable)
                            // Store the initial top-left position
                            let initialFrame = window.frame
                            let topLeft = NSPoint(x: initialFrame.minX, y: initialFrame.maxY)

                            // Set up a delegate to maintain top-left position during resize
                            if window.delegate == nil {
                                let resizeDelegate = SheetWindowResizeDelegate(topLeft: topLeft)
                                window.delegate = resizeDelegate
                                // Retain the delegate
                                objc_setAssociatedObject(
                                    window, "SheetResizeDelegate", resizeDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                                )
                            }

                            // Remove border from content view
                            if let contentView = window.contentView {
                                contentView.wantsLayer = true
                                if let layer = contentView.layer {
                                    layer.borderWidth = 0
                                    layer.borderColor = nil
                                }
                                // Also remove border from subviews
                                removeBorders(from: contentView)
                            }
                        }
                    }
                }
            }
    }

    /// Recursively remove borders from all subviews
    private func removeBorders(from view: NSView) {
        if let layer = view.layer {
            layer.borderWidth = 0
            layer.borderColor = nil
        }
        for subview in view.subviews {
            removeBorders(from: subview)
        }
    }
}

/// Window delegate to maintain top-left corner position during resize
class SheetWindowResizeDelegate: NSObject, NSWindowDelegate {
    private var topLeft: NSPoint
    private var isResizing = false

    init(topLeft: NSPoint) {
        self.topLeft = topLeft
        super.init()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Capture current top-left before resize
        let currentFrame = sender.frame
        topLeft = NSPoint(x: currentFrame.minX, y: currentFrame.maxY)
        isResizing = true
        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isResizing else { return }

        // Restore top-left position after resize (grow from bottom)
        let newFrame = window.frame
        let newOrigin = NSPoint(
            x: topLeft.x,
            y: topLeft.y - newFrame.height
        )

        window.setFrameOrigin(newOrigin)
        isResizing = false
    }
}

extension View {
    /// Customizes sheet window appearance (removes border, sets dark mode-aware background)
    /// Also ensures window resizes from bottom (top-left corner stays stable)
    func customizeSheetWindow() -> some View {
        modifier(SheetWindowModifier())
    }
}
