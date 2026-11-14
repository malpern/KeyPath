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
    /// One open alert. Reports which button was pressed, once.
    @MainActor
    final class Presentation: NSObject {
        let window: NSWindow
        private var onButton: ((Int) -> Void)?

        init(window: NSWindow, onButton: @escaping (Int) -> Void) {
            self.window = window
            self.onButton = onButton
        }

        @objc func buttonPressed(_ sender: NSButton) {
            finish(sender.tag)
        }

        /// Closes the alert as if button `index` had been pressed (0 is the first).
        func dismiss(asButton index: Int) {
            finish(index)
        }

        private func finish(_ index: Int) {
            guard let onButton else { return }
            self.onButton = nil
            window.orderOut(nil)
            NonModalAlertPresenter.presentations.removeAll { $0 === self }
            onButton(index)
        }
    }

    /// Keeps each open alert alive until it is answered.
    private static var presentations: [Presentation] = []

    /// Shows `alert`; `onButton` gets the index of the pressed button.
    @discardableResult
    static func present(_ alert: NSAlert, onButton: @escaping (Int) -> Void) -> Presentation {
        alert.layout()
        let window = alert.window
        let presentation = Presentation(window: window, onButton: onButton)
        for (index, button) in alert.buttons.enumerated() {
            button.tag = index
            button.target = presentation
            button.action = #selector(Presentation.buttonPressed(_:))
        }
        presentations.append(presentation)
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        return presentation
    }

    static func present(_ alert: NSAlert, onFirstButton: @escaping () -> Void) {
        present(alert) { index in
            if index == 0 { onFirstButton() }
        }
    }
}
