import AppKit
import KeyPathCore

/// Carries out OverlayLayerRevealPolicy: the overlay appears while a layer is active
/// when Settings → "When you switch layers" includes the keyboard overlay.
extension LiveKeyboardOverlayController {
    func noteLayerForReveal(_ normalizedLayer: String) {
        // The launcher layer runs its own show/hide session.
        guard normalizedLayer != "launcher" else { return }
        let preferences = PreferencesService.shared
        layerReveal.configuration = .make(
            displayMode: preferences.contextHUDDisplayMode,
            triggerMode: preferences.contextHUDTriggerMode,
            showsOnlyWhileLayerHeld: preferences.overlayShowsOnlyWhileLayerHeld
        )
        let effects = layerReveal.layerChanged(
            isBase: normalizedLayer == "base",
            overlayAlreadyVisible: window?.isVisible ?? false
        )
        applyLayerRevealEffects(effects)
    }

    func applyLayerRevealEffects(_ effects: [OverlayLayerRevealPolicy.Effect]) {
        for effect in effects {
            switch effect {
            case let .scheduleReveal(delay):
                layerRevealWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.applyLayerRevealEffects(self.layerReveal.revealTimerFired())
                    }
                }
                layerRevealWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            case .cancelReveal:
                layerRevealWorkItem?.cancel()
                layerRevealWorkItem = nil
            case .show:
                revealForLayer()
            case let .scheduleConceal(delay):
                layerConcealWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.applyLayerRevealEffects(self.layerReveal.concealTimerFired())
                    }
                }
                layerConcealWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            case .cancelConceal:
                layerConcealWorkItem?.cancel()
                layerConcealWorkItem = nil
            case .hide:
                AppLogger.shared.log("🫥 [OverlayController] Layer ended - hiding revealed overlay")
                hideWindow()
            }
        }
    }

    /// "Show only while a layer is held" was switched on: put away an overlay the user
    /// had open, and forget any pending restore, so it is hidden until a layer is held.
    func overlayShowsOnlyWhileLayerHeldChanged(_ enabled: Bool) {
        guard enabled else { return }
        forgetPendingVisibilityRestores()
        if isVisibleByChoice {
            isVisible = false
        }
    }

    /// Shows the overlay without touching the saved visibility, the explicit-hide flag
    /// or app focus: an overlay revealed by a layer is not the user's open overlay.
    private func revealForLayer() {
        guard !hasAutoHiddenForCurrentSettingsSession, !isAppSuppressed else {
            _ = layerReveal.userTookControl()
            return
        }
        AppLogger.shared.log("👁️ [OverlayController] Layer held - revealing overlay")
        showWindow(showingHints: false)
    }
}
