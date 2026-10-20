import AppKit

/// Shows an NSAlert as an ordinary window instead of running it modally.
///
/// `runModal()` blocks the main dispatch queue for as long as the alert is up, and
/// Swift main-actor tasks run on that queue, so every layer change, overlay reveal
/// and shortcut-list update waits behind an unanswered alert. That held true even
/// when `runModal()` was called from its own `DispatchQueue.main.async` block,
/// because the main queue is serial. See docs/bugs/modal-alert-inside-main-actor-task.md.
@MainActor
enum NonModalAlertPresenter {
    @MainActor
    private final class Handler: NSObject {
        let window: NSWindow
        let onFirstButton: () -> Void

        init(window: NSWindow, onFirstButton: @escaping () -> Void) {
            self.window = window
            self.onFirstButton = onFirstButton
        }

        @objc func firstButton(_: Any?) {
            onFirstButton()
            close()
        }

        @objc func otherButton(_: Any?) {
            close()
        }

        private func close() {
            window.orderOut(nil)
            NonModalAlertPresenter.handlers.removeAll { $0 === self }
        }
    }

    /// Keeps each open alert's handler alive until a button is pressed.
    private static var handlers: [Handler] = []

    static func present(_ alert: NSAlert, onFirstButton: @escaping () -> Void) {
        alert.layout()
        let window = alert.window
        let handler = Handler(window: window, onFirstButton: onFirstButton)
        for (index, button) in alert.buttons.enumerated() {
            button.target = handler
            button.action = index == 0 ? #selector(Handler.firstButton(_:)) : #selector(Handler.otherButton(_:))
        }
        handlers.append(handler)
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
