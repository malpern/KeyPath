import XCTest
@testable import KeyPathAppKit

final class FeatureFlagsWizardAutoFixerTests: XCTestCase {
    func testLegacyVHIDRestartFallbackDefaultsOff() {
        // Ensure default is OFF to avoid legacy paths unless explicitly enabled.
        XCTAssertFalse(FeatureFlags.useLegacyVHIDRestartFallback)
    }

    func testLegacyVHIDRestartFallbackCanBeToggled() {
        FeatureFlags.setUseLegacyVHIDRestartFallback(true)
        XCTAssertTrue(FeatureFlags.useLegacyVHIDRestartFallback)

        FeatureFlags.setUseLegacyVHIDRestartFallback(false)
        XCTAssertFalse(FeatureFlags.useLegacyVHIDRestartFallback)
    }
}
