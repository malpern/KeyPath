import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Controller for showing the Installation Wizard in its own window.
/// This allows the wizard to be shown regardless of which KeyPath window is currently frontmost.
@MainActor
final class WizardWindowController {
    static let shared = WizardWindowController()

    private var window: NSWindow?
    private var windowDelegate: WizardWindowDelegate?
    private var onDismiss: (() -> Void)?

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

        let hostingView: NSHostingView<AnyView> = if let viewModel = kanataViewModel {
            NSHostingView(rootView:
                AnyView(
                    wizardView
                        .environmentObject(viewModel)
                        .frame(minWidth: 700, minHeight: 500)
                ))
        } else {
            NSHostingView(rootView:
                AnyView(
                    wizardView
                        .frame(minWidth: 700, minHeight: 500)
                ))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyPath Setup"
        let minContentSize = NSSize(
            width: WizardDesign.Layout.pageWidth,
            height: WizardDesign.Layout.pageHeight
        )
        let maxContentSize = NSSize(
            width: WizardDesign.Layout.pageWidth,
            height: 720
        )
        window.contentMinSize = minContentSize
        window.contentMaxSize = maxContentSize
        window.minSize = NSSize(width: minContentSize.width, height: minContentSize.height)
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        let delegate = WizardWindowDelegate(controller: self)
        window.delegate = delegate
        windowDelegate = delegate

        // Persistent window position
        window.setFrameAutosaveName("WizardWindow")
        if !window.setFrameUsingName("WizardWindow") {
            window.center()
        }
        if window.contentLayoutRect.size.height > maxContentSize.height
            || window.contentLayoutRect.size.width > maxContentSize.width {
            window.setContentSize(maxContentSize)
        } else if window.contentLayoutRect.size.height < minContentSize.height
            || window.contentLayoutRect.size.width < minContentSize.width {
            window.setContentSize(minContentSize)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window

        // Auto-hide overlay when wizard opens
        LiveKeyboardOverlayController.shared.autoHideOnceForSettings()
    }

    /// Close the wizard window
    func closeWindow() {
        AppLogger.shared.log("🔮 [WizardWindow] Closing wizard window")
        window?.close()
        handleWindowClosed()
        windowDelegate = nil
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
