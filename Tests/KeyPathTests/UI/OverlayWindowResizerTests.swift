@testable import KeyPathAppKit
import XCTest

final class OverlayWindowResizerTests: XCTestCase {
    func testConstrainedSizeAnchorsWidthAndRespectsMinHeight() {
        let size = OverlayWindowResizer.constrainedSize(
            targetSize: CGSize(width: 120, height: 80),
            currentSize: CGSize(width: 200, height: 200),
            aspect: 2.0,
            verticalChrome: 20,
            horizontalChrome: 10,
            minSize: CGSize(width: 150, height: 120),
            maxSize: CGSize(width: 400, height: 400),
            anchor: .width
        )

        XCTAssertGreaterThanOrEqual(size.width, 150)
        XCTAssertGreaterThanOrEqual(size.height, 120)
    }

    func testResolveAnchorPrefersExisting() {
        let resolved = OverlayWindowResizer.resolveAnchor(
            existing: .height,
            startFrame: CGRect(x: 0, y: 0, width: 200, height: 200),
            currentFrame: CGRect(x: 0, y: 0, width: 210, height: 205),
            startMouse: CGPoint(x: 0, y: 0),
            currentMouse: CGPoint(x: 2, y: 2),
            widthDelta: 10,
            heightDelta: 5,
            threshold: 6
        )

        XCTAssertEqual(resolved, .height)
    }

    func testWidthForAspectUsesChromeAndAspect() {
        let width = OverlayWindowResizer.widthForAspect(
            currentHeight: 200,
            aspect: 2.0,
            verticalChrome: 20,
            horizontalChrome: 10
        )

        // keyboardHeight = 180, keyboardWidth = 360, total width = 370
        XCTAssertEqual(width, 370, accuracy: 0.001)
    }
}
