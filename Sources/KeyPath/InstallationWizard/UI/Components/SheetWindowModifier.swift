import SwiftUI
import AppKit

/// Modifier to customize sheet window appearance (remove border, set background)
struct SheetWindowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WizardDesign.Colors.wizardBackground)
            .onAppear {
                // Customize the sheet window appearance when it appears
                // Use a slight delay to ensure the window is fully created
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Find the sheet window
                    for window in NSApp.windows {
                        // Check if this is a sheet window (has a parent or is a sheet)
                        if window.isSheet || window.sheetParent != nil {
                            // Remove border by setting transparent background and removing border
                            window.backgroundColor = .clear
                            window.isOpaque = false
                            window.hasShadow = true

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

extension View {
    /// Customizes sheet window appearance (removes border, sets dark mode-aware background)
    func customizeSheetWindow() -> some View {
        modifier(SheetWindowModifier())
    }
}
