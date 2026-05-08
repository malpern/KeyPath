@testable import KeyPathAppKit
import XCTest

final class OverlayWindowSizingTests: XCTestCase {
    func testSizeUsesChromeAndAspectRatio() {
        let baseHeight: CGFloat = 200
        let scale: CGFloat = 1.3
        let aspectRatio: CGFloat = 2.0

        let size = OverlayWindowSizing.size(
            baseHeight: baseHeight,
            scale: scale,
            aspectRatio: aspectRatio,
            inspectorVisible: false,
            inspectorWidth: 240
        )

        let targetHeight = baseHeight * scale
        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: false,
            inspectorWidth: 240
        )
        let keyboardHeight = max(0, targetHeight - verticalChrome)
        let expectedWidth = (keyboardHeight * aspectRatio) + horizontalChrome

        XCTAssertEqual(size.height, targetHeight, accuracy: 0.001)
        XCTAssertEqual(size.width, expectedWidth, accuracy: 0.001)
    }

    func testCenteredFrameCentersWithinVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let frame = OverlayWindowSizing.centeredFrame(
            visibleFrame: visibleFrame,
            baseHeight: 200,
            scale: 1.0,
            aspectRatio: 2.0,
            inspectorVisible: false,
            inspectorWidth: 240
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.001)
    }

    func testCenteredFrameFallsBackToZeroOriginWithoutVisibleFrame() {
        let frame = OverlayWindowSizing.centeredFrame(
            visibleFrame: nil,
            baseHeight: 200,
            scale: 1.0,
            aspectRatio: 2.0,
            inspectorVisible: false,
            inspectorWidth: 240
        )

        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.001)
    }
}
