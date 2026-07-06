@testable import KeyPathAppKit
import Testing

@Suite("ReopenPolicy")
struct ReopenPolicyTests {
    @Test("Running app with visible overlay just activates")
    func overlayVisibleActivatesOnly() {
        let surface = ReopenPolicy.surface(
            hasExistingConfig: true,
            hasCompletedInitialWizard: true,
            overlayVisible: true
        )
        #expect(surface == .activateOnly)
    }

    @Test("Running app with hidden overlay shows the overlay, never the splash")
    func overlayHiddenShowsOverlay() {
        // The Raycast relaunch bug: reopen with the overlay hidden used to fall
        // through to the splash window, which has no dismiss affordance.
        let surface = ReopenPolicy.surface(
            hasExistingConfig: true,
            hasCompletedInitialWizard: true,
            overlayVisible: false
        )
        #expect(surface == .showOverlay)
    }

    @Test("Existing config does not show overlay before initial wizard completes")
    func configBeforeInitialWizardCompletionShowsSplash() {
        let surface = ReopenPolicy.surface(
            hasExistingConfig: true,
            hasCompletedInitialWizard: false,
            overlayVisible: false
        )
        #expect(surface == .showSplash)
    }

    @Test("Initial wizard completion is required even if overlay is somehow visible")
    func incompleteWizardOverridesOverlayVisibility() {
        let surface = ReopenPolicy.surface(
            hasExistingConfig: true,
            hasCompletedInitialWizard: false,
            overlayVisible: true
        )
        #expect(surface == .showSplash)
    }

    @Test("First run (no config) shows the splash onboarding surface")
    func firstRunShowsSplash() {
        let surface = ReopenPolicy.surface(
            hasExistingConfig: false,
            hasCompletedInitialWizard: false,
            overlayVisible: false
        )
        #expect(surface == .showSplash)
    }

    @Test("No config always means splash, even if the overlay is somehow visible")
    func noConfigOverridesOverlayVisibility() {
        let surface = ReopenPolicy.surface(
            hasExistingConfig: false,
            hasCompletedInitialWizard: true,
            overlayVisible: true
        )
        #expect(surface == .showSplash)
    }
}
