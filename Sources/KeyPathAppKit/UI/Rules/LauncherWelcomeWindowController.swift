import AppKit
import SwiftUI

/// Window controller for the LauncherWelcomeDialog.
/// Presents the dialog as an independent centered window rather than a sheet.
@MainActor
final class LauncherWelcomeWindowController: NSWindowController {
    /// Singleton to prevent multiple instances
    private static var currentController: LauncherWelcomeWindowController?

    private var onDismiss: (() -> Void)?

    /// Shows the launcher welcome dialog centered on screen.
    /// - Parameters:
    ///   - config: Binding to the launcher grid configuration
    ///   - onComplete: Called when the user completes the welcome flow
    ///   - onDismiss: Called when the window is closed (by any means)
    static func show(
        config: Binding<LauncherGridConfig>,
        onComplete: @escaping (LauncherGridConfig, LauncherWelcomeDialog.WelcomeAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // Dismiss any existing instance
        currentController?.close()
        currentController = nil

        let controller = LauncherWelcomeWindowController(
            config: config,
            onComplete: onComplete,
            onDismiss: onDismiss
        )
        currentController = controller
        controller.showWindow(nil)
    }

    /// Dismisses the current welcome window if one is showing
    static func dismiss() {
        currentController?.close()
        currentController = nil
    }

    private init(
        config: Binding<LauncherGridConfig>,
        onComplete: @escaping (LauncherGridConfig, LauncherWelcomeDialog.WelcomeAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss

        // Create the SwiftUI view with a dismiss environment that closes this window
        let dialogView = LauncherWelcomeDialogWrapper(
            config: config,
            onComplete: { finalConfig, action in
                onComplete(finalConfig, action)
                LauncherWelcomeWindowController.dismiss()
            }
        )

        let hostingController = NSHostingController(rootView: dialogView)

        // Create a panel-style window (floats above other windows)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure window appearance
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Make it float above other windows but not aggressively
        window.level = .floating
        window.hidesOnDeactivate = false

        // Center on screen
        window.center()

        super.init(window: window)

        window.contentViewController = hostingController
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSWindowDelegate

extension LauncherWelcomeWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        onDismiss?()
        LauncherWelcomeWindowController.currentController = nil
    }
}

// MARK: - Wrapper View

/// Wrapper that provides a dismiss action for the dialog
private struct LauncherWelcomeDialogWrapper: View {
    @Binding var config: LauncherGridConfig
    let onComplete: (LauncherGridConfig, LauncherWelcomeDialog.WelcomeAction) -> Void

    var body: some View {
        LauncherWelcomeDialog(
            config: $config,
            onComplete: onComplete
        )
        .background(VisualEffectBlur())
    }
}

/// Visual effect blur background for the dialog
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
