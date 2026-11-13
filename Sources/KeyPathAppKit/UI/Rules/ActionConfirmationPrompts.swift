import AppKit

/// The prompts KeyPath shows before running a script for the first time, or
/// before acting on a link from another app that could fire a macro.
@MainActor
enum ActionConfirmationPrompts {
    static func confirmScript(_ request: ScriptConfirmation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Run this script?")
        alert.informativeText = String(localized: """
        \(request.path)

        Scripts can run any command, and read or change your files. Run it only if you trust it. \
        "Always Allow" remembers this script; if it changes, KeyPath asks again.
        """)
        alert.addButton(withTitle: String(localized: "Run Once"))
        alert.addButton(withTitle: String(localized: "Always Allow"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: request.runOnce()
        case .alertSecondButtonReturn: request.alwaysAllow()
        default: request.cancel()
        }
    }

    static func confirmExternalAction(_ request: ExternalActionConfirmation) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Allow another app to \(request.summary)?")
        alert.informativeText = String(localized: """
        A keypath:// link from another app asked for this. Links can come from web pages and documents, \
        so allow it only if you started it, for example from Raycast or Hammerspoon. \
        "Always Allow" lets links from other apps press virtual keys without asking.
        """)
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Always Allow"))
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: request.allow()
        case .alertSecondButtonReturn: request.alwaysAllow()
        default: request.deny()
        }
    }
}
