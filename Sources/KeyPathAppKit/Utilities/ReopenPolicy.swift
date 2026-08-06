import Foundation

/// Decides which surface to present when the user re-opens the running app
/// (Dock click, Raycast/Spotlight launch, menu-bar "Show KeyPath").
///
/// The setup wizard is the actionable surface while setup is incomplete.
/// Once a config exists and the initial wizard has completed, reopen should
/// present the overlay instead. The splash is only a brief launch beat and must
/// never become the destination for a user-initiated reopen.
enum ReopenPolicy {
    enum Surface: Equatable {
        /// Overlay already on screen — just activate and bring it forward.
        case activateOnly
        /// Set up but overlay hidden — show the overlay, never the splash.
        case showOverlay
        /// Setup incomplete — show the actionable wizard, not the splash.
        case showSetupWizard
    }

    static func surface(
        hasExistingConfig: Bool,
        hasCompletedInitialWizard: Bool,
        overlayVisible: Bool
    ) -> Surface {
        guard hasExistingConfig, hasCompletedInitialWizard else { return .showSetupWizard }
        return overlayVisible ? .activateOnly : .showOverlay
    }
}
