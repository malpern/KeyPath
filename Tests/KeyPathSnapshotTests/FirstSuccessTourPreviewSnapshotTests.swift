@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
import XCTest

/// Capture the composed tour, including the copy column, footer, and app label.
@MainActor
final class FirstSuccessTourPreviewSnapshotTests: ScreenshotTestCase {
    func testComposedTourPages() {
        let renderer = FeatureFlags.keyboardStageRendererPreference
        FeatureFlags.setKeyboardStageRendererPreference(.swiftUI)
        defer { FeatureFlags.setKeyboardStageRendererPreference(renderer) }
        let model = FirstSuccessTourPreviewModel()
        for page in FirstSuccessOnboardingSession.Step.allCases {
            model.select(page: page, scenario: page == .launcher ? .selected : .installed)
            assertScreenshot(
                of: model.dialog(),
                size: CGSize(width: 1120, height: 720),
                named: "tour-page-\(page.ordinal)", precision: 0.99
            )
        }
    }
}
