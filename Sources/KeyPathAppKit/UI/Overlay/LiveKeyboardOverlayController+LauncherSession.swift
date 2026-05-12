import AppKit
import Foundation
import KeyPathCore

extension LiveKeyboardOverlayController {
    // MARK: - Launcher Session

    func handleLauncherLayerTransition(normalizedLayer: String) {
        if normalizedLayer == "launcher" {
            handleLauncherLayerActivated()
            return
        }

        if isLauncherSessionActive {
            if shouldRestoreAppHidden || shouldRestoreOverlayHidden {
                AppLogger.shared.debug(
                    "🪟 [OverlayController] Launcher exited without action - clearing pending restore"
                )
            }
            isLauncherSessionActive = false
            shouldRestoreAppHidden = false
            shouldRestoreOverlayHidden = false
        }
    }

    func handleLauncherLayerActivated() {
        guard !isLauncherSessionActive else { return }
        isLauncherSessionActive = true

        let appWasHidden = NSApp.isHidden
        let overlayWasHidden = !isVisible
        shouldRestoreAppHidden = appWasHidden
        shouldRestoreOverlayHidden = overlayWasHidden

        guard appWasHidden || overlayWasHidden else { return }

        AppLogger.shared.log(
            "🪟 [OverlayController] Launcher activated while hidden (app=\(appWasHidden), overlay=\(overlayWasHidden)) - bringing to front"
        )

        if appWasHidden {
            NSApp.unhide(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        showForQuickLaunch(bypassHiddenCheck: true)
    }

    func noteLauncherActionDispatched() {
        guard shouldRestoreAppHidden || shouldRestoreOverlayHidden else { return }
        let restoreAppHidden = shouldRestoreAppHidden
        let restoreOverlayHidden = shouldRestoreOverlayHidden
        shouldRestoreAppHidden = false
        shouldRestoreOverlayHidden = false
        isLauncherSessionActive = false

        AppLogger.shared.log(
            "🪟 [OverlayController] Restoring hidden state after launcher action (app=\(restoreAppHidden), overlay=\(restoreOverlayHidden))"
        )

        if restoreOverlayHidden {
            isVisible = false
        }
        if restoreAppHidden {
            NSApp.hide(nil)
        }
    }

    static func launcherActionMessage(for action: KeyAction) -> String? {
        switch action {
        case let .launchApp(name, bundleId):
            return "launch:\(bundleId ?? name)"
        case let .openURL(urlString):
            let encoded = URLMappingFormatter.encodeForPushMessage(urlString)
            return "open:\(encoded)"
        case let .openFolder(path, _):
            return "folder:\(path)"
        case let .runScript(path, _):
            return "script:\(path)"
        default:
            return nil
        }
    }

    func bringOverlayToFront() {
        if !isVisible {
            isVisible = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFront(nil)
    }
}
