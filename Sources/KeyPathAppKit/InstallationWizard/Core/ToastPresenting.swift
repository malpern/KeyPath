import Foundation

/// Protocol for presenting toast notifications from Core layer
/// UI layer implements this to show actual toasts
@MainActor
protocol ToastPresenting {
    func showSuccess(_ message: String, duration: TimeInterval)
    func showError(_ message: String, duration: TimeInterval)
    func showInfo(_ message: String, duration: TimeInterval)
    func dismissToast()
}

/// Default duration values for toast protocol
extension ToastPresenting {
    func showSuccess(_ message: String) {
        showSuccess(message, duration: 3.0)
    }

    func showError(_ message: String) {
        showError(message, duration: 5.0)
    }

    func showInfo(_ message: String) {
        showInfo(message, duration: 3.0)
    }
}
