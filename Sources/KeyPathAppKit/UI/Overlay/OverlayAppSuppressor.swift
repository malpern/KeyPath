// Watches NSWorkspace for frontmost-app changes and suppresses/restores
// the live keyboard overlay based on the user's
// `PreferencesService.overlaySuppressedBundleIDs` list.
//
// The ContextHUD already checks the same list inline when deciding whether
// to show, so it doesn't need a parallel suppressor — this type handles
// the overlay's longer-lived visibility state.

import AppKit
import Foundation
import KeyPathCore

@MainActor
final class OverlayAppSuppressor {
    static let shared = OverlayAppSuppressor()

    private var activationObserver: NSObjectProtocol?
    private var preferenceChangeObserver: NSObjectProtocol?

    func start() {
        guard activationObserver == nil else { return }

        // Apply state for whatever app is frontmost right now.
        applyForCurrentApp()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyForCurrentApp()
            }
        }

        // When the user edits the list in Settings, re-evaluate so the
        // overlay doesn't stay suppressed in an app the user just removed.
        preferenceChangeObserver = NotificationCenter.default.addObserver(
            forName: .overlaySuppressedBundleIDsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyForCurrentApp()
            }
        }
    }

    func stop() {
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = nil
        preferenceChangeObserver.map(NotificationCenter.default.removeObserver)
        preferenceChangeObserver = nil
    }

    private func applyForCurrentApp() {
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let suppressed = PreferencesService.shared.overlaySuppressedBundleIDs
        if let frontBundle, suppressed.contains(frontBundle) {
            LiveKeyboardOverlayController.shared.suppressForApp()
        } else {
            LiveKeyboardOverlayController.shared.restoreFromAppSuppression()
        }
    }
}
