import AppKit
import Foundation
import KeyPathCore

enum SafetyAlertPresenter {
    @MainActor
    static func presentSafetyTimeoutAlert() {
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [Safety] Suppressing NSAlert in test environment")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Safety Timeout Activated"
        alert.informativeText = """
        KeyPath automatically stopped the keyboard remapping service after 30 seconds as a safety precaution.

        If the service was working correctly, you can restart it from the main app window.

        If you experienced keyboard issues, this timeout prevented them from continuing.
        """
        alert.alertStyle = .informational
        alert.runModal()
    }
}


