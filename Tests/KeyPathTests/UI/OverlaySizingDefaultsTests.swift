@testable import KeyPathAppKit
import XCTest

final class OverlaySizingDefaultsTests: XCTestCase {
    func testStartupSizeUsesBaseHeightAndScale() {
        let size = OverlaySizingDefaults.startupSize(
            aspectRatio: 2.0,
            inspectorWidth: 240
        )

        let expectedHeight = OverlaySizingDefaults.baseHeight * OverlaySizingDefaults.startupScale
        XCTAssertEqual(size.height, expectedHeight, accuracy: 0.001)
    }

    func testResetCenteredFrameUsesResetScale() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = OverlaySizingDefaults.resetCenteredFrame(
            visibleFrame: visibleFrame,
            aspectRatio: 2.0,
            inspectorWidth: 240
        )

        let expectedHeight = OverlaySizingDefaults.baseHeight * OverlaySizingDefaults.resetScale
        XCTAssertEqual(frame.size.height, expectedHeight, accuracy: 0.001)
        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
    }
}
