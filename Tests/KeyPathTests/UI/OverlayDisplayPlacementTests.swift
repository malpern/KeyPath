@testable import KeyPathAppKit
import XCTest

final class OverlayDisplayPlacementTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let studio = CGRect(x: 1512, y: 0, width: 2560, height: 1415)

    func testADisplaysOwnFrameWins() {
        let mine = CGRect(x: 1600, y: 40, width: 800, height: 300)
        let frame = OverlayDisplayPlacement.frame(
            savedOnTarget: mine,
            lastFrame: CGRect(x: 20, y: 20, width: 600, height: 220),
            lastVisibleFrame: laptop,
            targetVisibleFrame: studio
        )
        XCTAssertEqual(frame, mine)
    }

    func testANewDisplayGetsTheSameRelativeSpot() throws {
        // Bottom-right corner of the laptop...
        let last = CGRect(x: 1512 - 620, y: 20, width: 600, height: 220)
        let frame = try XCTUnwrap(OverlayDisplayPlacement.frame(
            savedOnTarget: nil, lastFrame: last, lastVisibleFrame: laptop, targetVisibleFrame: studio
        ))
        // ...lands toward the bottom-right of the studio display, same size, fully on screen.
        XCTAssertEqual(frame.size, last.size)
        XCTAssertTrue(studio.contains(frame))
        XCTAssertGreaterThan(frame.midX, studio.midX)
        XCTAssertLessThan(frame.midY, studio.midY)
    }

    func testAFrameTooLargeForTheTargetIsScaledToFit() throws {
        let big = CGRect(x: 1600, y: 100, width: 2200, height: 800)
        let frame = try XCTUnwrap(OverlayDisplayPlacement.frame(
            savedOnTarget: nil, lastFrame: big, lastVisibleFrame: studio, targetVisibleFrame: laptop
        ))
        XCTAssertTrue(laptop.contains(frame))
        XCTAssertEqual(frame.width / frame.height, big.width / big.height, accuracy: 0.01)
    }

    func testAFrameSavedOffTheTargetIsIgnored() throws {
        let stale = CGRect(x: 5000, y: 5000, width: 600, height: 220)
        let last = CGRect(x: 40, y: 40, width: 600, height: 220)
        let frame = try XCTUnwrap(OverlayDisplayPlacement.frame(
            savedOnTarget: stale, lastFrame: last, lastVisibleFrame: laptop, targetVisibleFrame: laptop
        ))
        XCTAssertEqual(frame, last)
    }

    func testNoSavedFrameMeansDefaultPlacement() {
        XCTAssertNil(OverlayDisplayPlacement.frame(
            savedOnTarget: nil, lastFrame: nil, lastVisibleFrame: nil, targetVisibleFrame: laptop
        ))
    }

    func testFrameStoreRemembersEachDisplayAndClearForgetsThem() throws {
        let suite = "OverlayDisplayPlacementTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OverlayWindowFrameStore(defaults: defaults)

        let onLaptop = CGRect(x: 10, y: 10, width: 600, height: 220)
        let onStudio = CGRect(x: 1600, y: 10, width: 900, height: 330)
        store.save(frame: onLaptop, displayKey: "Built-in-1512x982", visibleFrame: laptop)
        store.save(frame: onStudio, displayKey: "Studio-2560x1440", visibleFrame: studio)

        XCTAssertEqual(store.frame(forDisplay: "Built-in-1512x982"), onLaptop)
        XCTAssertEqual(store.frame(forDisplay: "Studio-2560x1440"), onStudio)
        XCTAssertEqual(store.restore(), onStudio, "the last saved frame is still the global one")
        XCTAssertEqual(store.lastVisibleFrame(), studio)

        store.clear()
        XCTAssertNil(store.frame(forDisplay: "Studio-2560x1440"))
        XCTAssertNil(store.restore())
    }
}
