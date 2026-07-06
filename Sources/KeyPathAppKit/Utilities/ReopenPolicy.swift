import Foundation

/// Decides which surface to present when the user re-opens the running app
/// (Dock click, Raycast/Spotlight launch, menu-bar "Show KeyPath").
///
/// The splash/main window is the onboarding surface while setup is incomplete.
/// Once a config exists and the initial wizard has completed, reopen should
/// present the overlay instead — re-showing the splash on a fully running app
/// leaves it stuck on screen with no way to close it.
enum ReopenPolicy {
    enum Surface: Equatable {
        /// Overlay already on screen — just activate and bring it forward.
        case activateOnly
        /// Set up but overlay hidden — show the overlay, never the splash.
        case showOverlay
        /// First-run onboarding (no config yet) — the splash window is the surface.
        case showSplash
    }

    static func surface(
        hasExistingConfig: Bool,
        hasCompletedInitialWizard: Bool,
        overlayVisible: Bool
    ) -> Surface {
        guard hasExistingConfig, hasCompletedInitialWizard else { return .showSplash }
        return overlayVisible ? .activateOnly : .showOverlay
    }
}
