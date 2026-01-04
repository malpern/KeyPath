import XCTest

@testable import KeyPathAppKit

@MainActor
final class IconResolverServiceTests: XCTestCase {
    // MARK: - System Action SF Symbols

    func testSystemActionSymbol_spotlight() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "spotlight")
        XCTAssertEqual(symbol, "magnifyingglass")
    }

    func testSystemActionSymbol_missionControl() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "mission-control")
        XCTAssertEqual(symbol, "rectangle.3.group")
    }

    func testSystemActionSymbol_launchpad() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "launchpad")
        XCTAssertEqual(symbol, "square.grid.3x3")
    }

    func testSystemActionSymbol_dnd() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "dnd")
        XCTAssertEqual(symbol, "moon")
    }

    func testSystemActionSymbol_notificationCenter() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "notification-center")
        XCTAssertEqual(symbol, "bell")
    }

    // MARK: - Media Key SF Symbols (the key fix)

    func testSystemActionSymbol_brightnessUp() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "brightness-up")
        XCTAssertEqual(symbol, "sun.max")
    }

    func testSystemActionSymbol_brightnessDown() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "brightness-down")
        XCTAssertEqual(symbol, "sun.min")
    }

    func testSystemActionSymbol_volumeUp() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "volume-up")
        XCTAssertEqual(symbol, "speaker.wave.3")
    }

    func testSystemActionSymbol_volumeDown() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "volume-down")
        XCTAssertEqual(symbol, "speaker.wave.1")
    }

    func testSystemActionSymbol_mute() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "mute")
        XCTAssertEqual(symbol, "speaker.slash")
    }

    func testSystemActionSymbol_playPause() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "play-pause")
        XCTAssertEqual(symbol, "playpause")
    }

    func testSystemActionSymbol_nextTrack() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "next-track")
        XCTAssertEqual(symbol, "forward")
    }

    func testSystemActionSymbol_prevTrack() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "prev-track")
        XCTAssertEqual(symbol, "backward")
    }

    // MARK: - Unknown Action

    func testSystemActionSymbol_unknownReturnsNil() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "nonexistent")
        XCTAssertNil(symbol)
    }

    func testSystemActionSymbol_emptyReturnsNil() {
        let symbol = IconResolverService.shared.systemActionSymbol(for: "")
        XCTAssertNil(symbol)
    }

    // MARK: - Lookup Consistency with SystemActionInfo

    func testSystemActionSymbol_matchesSystemActionInfo() {
        // Verify IconResolverService returns same symbols as SystemActionInfo
        for action in SystemActionInfo.allActions {
            let symbol = IconResolverService.shared.systemActionSymbol(for: action.id)
            XCTAssertEqual(symbol, action.sfSymbol, "Mismatch for action: \(action.id)")
        }
    }
}
