import AppKit
import SwiftUI

/// Window controller for the `FirstSuccessDialog` (issue #954).
/// Presents the celebration + tour as an independent floating panel, following the
/// same pattern as `LauncherWelcomeWindowController`.
@MainActor
final class FirstSuccessWindowController: NSWindowController {
    /// Singleton to prevent multiple instances
    private static var currentController: FirstSuccessWindowController?

    /// Shows the first-success celebration panel centered on screen.
    /// - Parameter viewModel: Injected into the SwiftUI environment so the dialog
    ///   can enable the starter collection via the existing rule-collections
    ///   coordinator plumbing.
    static func show(viewModel: KanataViewModel) {
        // Dismiss any existing instance
        currentController?.close()
        currentController = nil

        let controller = FirstSuccessWindowController(viewModel: viewModel)
        currentController = controller
        controller.showWindow(nil)
    }

    /// Dismisses the current celebration panel if one is showing
    static func dismiss() {
        currentController?.close()
        currentController = nil
    }

    private init(viewModel: KanataViewModel) {
        let dialogView = FirstSuccessDialog(onFinished: {
            FirstSuccessWindowController.dismiss()
        })
        .environment(viewModel)
        .background(VisualEffectBlur())

        let hostingController = NSHostingController(rootView: dialogView)

        // Create a panel-style window (floats above other windows)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
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

extension FirstSuccessWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        FirstSuccessWindowController.currentController = nil
    }
}

// MARK: - Visual Effect Blur

/// Visual effect blur background for the panel (hudWindow material, matching the
/// Launcher welcome panel's floating-panel treatment).
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
