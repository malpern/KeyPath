import Foundation

extension LiveKeyboardOverlayController {
    // MARK: - App-Scoped Suppression

    func suppressForApp() {
        guard !isAppSuppressed else { return }
        isAppSuppressed = true
        wasVisibleBeforeAppSuppression = isVisible
        if isVisible {
            isVisible = false
        }
    }

    func restoreFromAppSuppression() {
        guard isAppSuppressed else { return }
        let shouldRestore = wasVisibleBeforeAppSuppression
        isAppSuppressed = false
        wasVisibleBeforeAppSuppression = false
        if shouldRestore, !isVisible {
            isVisible = true
        }
    }
}
