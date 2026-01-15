import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Notification posted when wizard content size changes
extension Notification.Name {
    static let wizardContentSizeChanged = Notification.Name("wizardContentSizeChanged")
}

/// Controller for showing the Installation Wizard in its own window.
/// This allows the wizard to be shown regardless of which KeyPath window is currently frontmost.
@MainActor
final class WizardWindowController {
    static let shared = WizardWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var windowDelegate: WizardWindowDelegate?
    private var onDismiss: (() -> Void)?
    private var sizeObserver: NSObjectProtocol?

    private init() {}

    /// Show the wizard window, optionally starting at a specific page
    func showWindow(
        initialPage: WizardPage? = nil,
        kanataViewModel: KanataViewModel? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.onDismiss = onDismiss

        // If window already exists and is visible, just bring it to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        AppLogger.shared.log("🔮 [WizardWindow] Opening wizard window (initialPage: \(initialPage?.displayName ?? "nil"))")

        let wizardView = InstallationWizardView(initialPage: initialPage)

        // Create hosting view - let SwiftUI determine ideal height
        let hosting: NSHostingView<AnyView> = if let viewModel = kanataViewModel {
            NSHostingView(rootView:
                AnyView(
                    wizardView
                        .environmentObject(viewModel)
                        .frame(width: 700)
                        .fixedSize(horizontal: false, vertical: true)
                ))
        } else {
            NSHostingView(rootView:
                AnyView(
                    wizardView
                        .frame(width: 700)
                        .fixedSize(horizontal: false, vertical: true)
                ))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyPath Setup"

        // Allow flexible height but fixed width
        let minContentSize = NSSize(width: 700, height: 250)
        let maxContentSize = NSSize(width: 700, height: 800)
        window.contentMinSize = minContentSize
        window.contentMaxSize = maxContentSize
        window.contentView = hosting
        window.isReleasedWhenClosed = false

        // Disable focus ring on hosting view to prevent blue outline
        hosting.focusRingType = .none

        let delegate = WizardWindowDelegate(controller: self)
        window.delegate = delegate
        windowDelegate = delegate
        hostingView = hosting

        // Center on first show, then remember position
        window.setFrameAutosaveName("WizardWindow")
        if !window.setFrameUsingName("WizardWindow") {
            window.center()
        }

        // Set initial size based on content
        let idealSize = hosting.intrinsicContentSize
        if idealSize.height > 0 {
            resizeWindowToHeight(idealSize.height, animated: false)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window

        // Observe content size changes to resize window dynamically
        sizeObserver = NotificationCenter.default.addObserver(
            forName: .wizardContentSizeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowSizeToFitContent()
            }
        }

        // Auto-hide overlay when wizard opens
        LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
    }

    /// Close the wizard window
    func closeWindow() {
        AppLogger.shared.log("🔮 [WizardWindow] Closing wizard window")
        if let observer = sizeObserver {
            NotificationCenter.default.removeObserver(observer)
            sizeObserver = nil
        }
        window?.close()
        handleWindowClosed()
        windowDelegate = nil
    }

    /// Update window size to fit current content, keeping top edge fixed
    private func updateWindowSizeToFitContent() {
        guard let hosting = hostingView else { return }

        // Force layout update
        hosting.layoutSubtreeIfNeeded()

        let idealSize = hosting.intrinsicContentSize
        guard idealSize.height > 0 else { return }

        // Clamp to min/max
        let clampedHeight = max(250, min(800, idealSize.height))
        resizeWindowToHeight(clampedHeight, animated: true)
    }

    /// Resize window to a specific height, keeping top edge fixed
    private func resizeWindowToHeight(_ newHeight: CGFloat, animated: Bool) {
        guard let window = window else { return }

        let currentFrame = window.frame
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height

        // Calculate new frame keeping top edge fixed
        let newContentHeight = newHeight
        let newWindowHeight = newContentHeight + titleBarHeight
        let heightDelta = newWindowHeight - currentFrame.height

        var newFrame = currentFrame
        newFrame.size.height = newWindowHeight
        newFrame.origin.y -= heightDelta // Move origin down to keep top fixed

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    /// Called when the window is closed (either programmatically or by user)
    func handleWindowClosed() {
        AppLogger.shared.log("🎭 [WizardWindow] ========== WIZARD CLOSED ==========")

        // Reset overlay auto-hide guard
        LiveKeyboardOverlayController.shared.resetSettingsAutoHideGuard()

        // Call dismiss handler
        onDismiss?()
        onDismiss = nil
    }

    /// Check if the wizard window is currently visible
    var isVisible: Bool {
        window?.isVisible ?? false
    }
}

// MARK: - Window Delegate

private class WizardWindowDelegate: NSObject, NSWindowDelegate {
    private weak var controller: WizardWindowController?

    init(controller: WizardWindowController) {
        self.controller = controller
    }

    func windowWillClose(_: Notification) {
        Task { @MainActor in
            controller?.handleWindowClosed()
        }
    }
}
