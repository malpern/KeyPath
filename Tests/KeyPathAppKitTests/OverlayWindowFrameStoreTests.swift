@testable import KeyPathAppKit
import XCTest

final class OverlayWindowFrameStoreTests: XCTestCase {
    private let suiteName = "OverlayWindowFrameStoreTests"

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSaveAndRestoreRoundTrip() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = OverlayWindowFrameStore(defaults: defaults, frameVersion: 1)
        let frame = CGRect(x: 10, y: 20, width: 300, height: 200)

        store.save(frame: frame)
        let restored = store.restore()

        XCTAssertEqual(restored?.origin.x, frame.origin.x, accuracy: 0.001)
        XCTAssertEqual(restored?.origin.y, frame.origin.y, accuracy: 0.001)
        XCTAssertEqual(restored?.size.width, frame.size.width, accuracy: 0.001)
        XCTAssertEqual(restored?.size.height, frame.size.height, accuracy: 0.001)
    }

    func testRestoreClearsOnVersionMismatch() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = OverlayWindowFrameStore(defaults: defaults, frameVersion: 2)

        defaults.set(1, forKey: "LiveKeyboardOverlay.frameVersion")
        defaults.set(100.0, forKey: "LiveKeyboardOverlay.windowWidth")
        defaults.set(100.0, forKey: "LiveKeyboardOverlay.windowHeight")
        defaults.set(10.0, forKey: "LiveKeyboardOverlay.windowX")
        defaults.set(20.0, forKey: "LiveKeyboardOverlay.windowY")

        XCTAssertNil(store.restore())
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowWidth"))
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowHeight"))
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowX"))
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowY"))
        XCTAssertEqual(defaults.integer(forKey: "LiveKeyboardOverlay.frameVersion"), 2)
    }

    func testRestoreClearsOnMissingHeight() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = OverlayWindowFrameStore(defaults: defaults, frameVersion: 1)

        defaults.set(1, forKey: "LiveKeyboardOverlay.frameVersion")
        defaults.set(100.0, forKey: "LiveKeyboardOverlay.windowWidth")
        defaults.set(10.0, forKey: "LiveKeyboardOverlay.windowX")
        defaults.set(20.0, forKey: "LiveKeyboardOverlay.windowY")

        XCTAssertNil(store.restore())
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowWidth"))
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowX"))
        XCTAssertNil(defaults.object(forKey: "LiveKeyboardOverlay.windowY"))
    }
}
