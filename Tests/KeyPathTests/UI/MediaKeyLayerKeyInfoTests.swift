@testable import KeyPathAppKit
import XCTest

/// Tests for verifying that media keys in custom rules are properly
/// converted to LayerKeyInfo with systemActionIdentifier set.
///
/// This is critical for the icon rendering fix where media keys like "brup"
/// need to display SF Symbols instead of text like "BRIGHT..."
final class MediaKeyLayerKeyInfoTests: XCTestCase {
    // MARK: - SystemActionInfo Detection

    func testMediaKeyDetection_brightnessUp() {
        // "brup" should be detected as a system action, not a simple remap
        let action = SystemActionInfo.find(byOutput: "brup")
        XCTAssertNotNil(action, "brup should be found by SystemActionInfo.find")
        XCTAssertEqual(action?.id, "brightness-up")
        XCTAssertEqual(action?.sfSymbol, "sun.max")
    }

    func testMediaKeyDetection_brightnessDown() {
        let action = SystemActionInfo.find(byOutput: "brdown")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "brightness-down")
        XCTAssertEqual(action?.sfSymbol, "sun.min")
    }

    func testMediaKeyDetection_volumeUp() {
        let action = SystemActionInfo.find(byOutput: "volu")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "volume-up")
        XCTAssertEqual(action?.sfSymbol, "speaker.wave.3")
    }

    func testMediaKeyDetection_volumeDown() {
        let action = SystemActionInfo.find(byOutput: "voldwn")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "volume-down")
        XCTAssertEqual(action?.sfSymbol, "speaker.wave.1")
    }

    func testMediaKeyDetection_playPause() {
        let action = SystemActionInfo.find(byOutput: "pp")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "play-pause")
        XCTAssertEqual(action?.sfSymbol, "playpause")
    }

    func testMediaKeyDetection_next() {
        let action = SystemActionInfo.find(byOutput: "next")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "next-track")
    }

    func testMediaKeyDetection_prev() {
        let action = SystemActionInfo.find(byOutput: "prev")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "prev-track")
    }

    func testMediaKeyDetection_mute() {
        let action = SystemActionInfo.find(byOutput: "mute")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.id, "mute")
    }

    // MARK: - Regular Keys Should NOT Match

    func testRegularKey_letterA() {
        let action = SystemActionInfo.find(byOutput: "a")
        XCTAssertNil(action, "Regular letter 'a' should not match SystemActionInfo")
    }

    func testRegularKey_letterB() {
        let action = SystemActionInfo.find(byOutput: "b")
        XCTAssertNil(action)
    }

    func testRegularKey_escape() {
        let action = SystemActionInfo.find(byOutput: "esc")
        XCTAssertNil(action, "esc is a regular key, not a system action")
    }

    func testRegularKey_enter() {
        let action = SystemActionInfo.find(byOutput: "ret")
        XCTAssertNil(action)
    }

    // MARK: - LayerKeyInfo Creation

    func testLayerKeyInfo_systemAction_hasSystemActionIdentifier() {
        let info = LayerKeyInfo.systemAction(action: "brightness-up", description: "Brightness Up")
        XCTAssertEqual(info.systemActionIdentifier, "brightness-up")
        XCTAssertEqual(info.displayLabel, "Brightness Up")
        XCTAssertFalse(info.isTransparent)
        XCTAssertFalse(info.isLayerSwitch)
    }

    func testLayerKeyInfo_mapped_noSystemActionIdentifier() {
        let info = LayerKeyInfo.mapped(displayLabel: "B", outputKey: "b", outputKeyCode: 11)
        XCTAssertNil(info.systemActionIdentifier)
        XCTAssertEqual(info.displayLabel, "B")
        XCTAssertEqual(info.outputKey, "b")
    }

    // MARK: - End-to-End: Icon Resolution

    @MainActor
    func testIconResolution_mediaKeyHasSymbol() {
        // Simulate the full flow: brup → SystemActionInfo → IconResolverService
        guard let action = SystemActionInfo.find(byOutput: "brup") else {
            XCTFail("brup should be found")
            return
        }

        let symbol = IconResolverService.shared.systemActionSymbol(for: action.id)
        XCTAssertEqual(symbol, "sun.max", "Brightness up should resolve to sun.max SF Symbol")
    }

    @MainActor
    func testIconResolution_allMediaKeysHaveSymbols() {
        let mediaKeys = SystemActionInfo.allActions.filter(\.isMediaKey)

        for key in mediaKeys {
            let symbol = IconResolverService.shared.systemActionSymbol(for: key.id)
            XCTAssertNotNil(symbol, "Media key \(key.id) should have an SF Symbol")
            XCTAssertEqual(symbol, key.sfSymbol, "Symbol mismatch for \(key.id)")
        }
    }
}
