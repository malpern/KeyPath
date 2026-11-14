import AppKit
import KeyPathCore

/// The prompts KeyPath shows before running a script for the first time, or
/// before acting on a link from another app that presses a virtual key.
///
/// A prompt never blocks: it is a window (NonModalAlertPresenter), not a modal
/// run loop, so the engine's event reader and every other main-actor task keep
/// running while the user decides. One prompt shows at a time; a request that
/// arrives while one is open is cancelled.
@MainActor
enum ActionConfirmationPrompts {
    private static var isShowing = false

    static func confirmScript(_ request: ScriptConfirmation) {
        present(onBusy: request.cancel) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Run this script?")
            alert.informativeText = String(localized: """
            \(request.path)

            Scripts can run any command, and read or change your files. Run it only if you trust it. \
            "Always Allow" remembers this script; if it changes, KeyPath asks again.
            """)
            addButtons(to: alert, [
                (String(localized: "Run Once"), "script-confirm-run-once-button"),
                (String(localized: "Always Allow"), "script-confirm-always-allow-button"),
                (String(localized: "Cancel"), "script-confirm-cancel-button")
            ])
            NonModalAlertPresenter.present(alert) { index in
                isShowing = false
                switch index {
                case 0: request.runOnce()
                case 1: request.alwaysAllow()
                default: request.cancel()
                }
            }
        }
    }

    static func confirmExternalAction(_ request: ExternalActionConfirmation) {
        present(onBusy: request.deny) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Allow another app to press the virtual key “\(request.virtualKey)”?")
            alert.informativeText = String(localized: """
            A keypath:// link from another app asked for this. A virtual key does whatever your config binds to it, \
            which can include running a script. Links can come from web pages and documents, so allow this only if \
            you started it, for example from Raycast or Hammerspoon. "Always Allow" lets links from other apps press \
            virtual keys without asking; you can turn that off in Settings.
            """)
            addButtons(to: alert, [
                (String(localized: "Allow"), "link-confirm-allow-button"),
                (String(localized: "Always Allow"), "link-confirm-always-allow-button"),
                (String(localized: "Don't Allow"), "link-confirm-deny-button")
            ])
            NonModalAlertPresenter.present(alert) { index in
                isShowing = false
                switch index {
                case 0: request.allow()
                case 1: request.alwaysAllow()
                default: request.deny()
                }
            }
        }
    }

    private static func present(onBusy: @escaping () -> Void, _ show: @escaping @MainActor () -> Void) {
        guard !isShowing else {
            AppLogger.shared.log("🛡️ [ActionConfirmationPrompts] A prompt is already open; declining the new request")
            onBusy()
            return
        }
        // Cleared when the prompt is answered.
        isShowing = true
        NSApp.activate(ignoringOtherApps: true)
        show()
    }

    private static func addButtons(to alert: NSAlert, _ buttons: [(String, String)]) {
        for (title, identifier) in buttons {
            alert.addButton(withTitle: title).setAccessibilityIdentifier(identifier)
        }
        alert.buttons.last?.keyEquivalent = "\u{1b}"
    }
}
