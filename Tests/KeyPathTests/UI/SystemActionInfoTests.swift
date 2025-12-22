import XCTest

@testable import KeyPathAppKit

final class SystemActionInfoTests: XCTestCase {
    // MARK: - Lookup by ID

    func testFindByID_spotlight() {
        let result = SystemActionInfo.find(byOutput: "spotlight")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "spotlight")
        XCTAssertEqual(result?.name, "Spotlight")
    }

    func testFindByID_playPause() {
        let result = SystemActionInfo.find(byOutput: "play-pause")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "play-pause")
        XCTAssertTrue(result?.isMediaKey ?? false)
    }

    // MARK: - Lookup by Display Name

    func testFindByName_missionControl() {
        let result = SystemActionInfo.find(byOutput: "Mission Control")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "mission-control")
    }

    func testFindByName_doNotDisturb() {
        let result = SystemActionInfo.find(byOutput: "Do Not Disturb")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "dnd")
    }

    // MARK: - Lookup by Kanata Keycode

    func testFindByKeycode_pp() {
        let result = SystemActionInfo.find(byOutput: "pp")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "play-pause")
        XCTAssertEqual(result?.kanataKeycode, "pp")
    }

    func testFindByKeycode_next() {
        let result = SystemActionInfo.find(byOutput: "next")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "next-track")
    }

    func testFindByKeycode_prev() {
        let result = SystemActionInfo.find(byOutput: "prev")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "prev-track")
    }

    func testFindByKeycode_mute() {
        let result = SystemActionInfo.find(byOutput: "mute")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "mute")
    }

    func testFindByKeycode_volumeUp() {
        let result = SystemActionInfo.find(byOutput: "volu")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "volume-up")
    }

    func testFindByKeycode_volumeDown() {
        let result = SystemActionInfo.find(byOutput: "voldwn")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "volume-down")
    }

    func testFindByKeycode_brightnessUp() {
        let result = SystemActionInfo.find(byOutput: "brup")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "brightness-up")
    }

    func testFindByKeycode_brightnessDown() {
        let result = SystemActionInfo.find(byOutput: "brdown")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "brightness-down")
    }

    // MARK: - Lookup by Simulator Name

    func testFindBySimulatorName_mediaPlayPause() {
        let result = SystemActionInfo.find(byOutput: "MediaPlayPause")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "play-pause")
    }

    func testFindBySimulatorName_mediaNextSong() {
        let result = SystemActionInfo.find(byOutput: "MediaNextSong")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "next-track")
    }

    func testFindBySimulatorName_mediaPreviousSong() {
        let result = SystemActionInfo.find(byOutput: "MediaPreviousSong")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "prev-track")
    }

    func testFindBySimulatorName_volUp() {
        let result = SystemActionInfo.find(byOutput: "VolUp")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "volume-up")
    }

    func testFindBySimulatorName_volDown() {
        let result = SystemActionInfo.find(byOutput: "VolDown")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "volume-down")
    }

    func testFindBySimulatorName_brightnessUp() {
        let result = SystemActionInfo.find(byOutput: "BrightnessUp")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "brightness-up")
    }

    func testFindBySimulatorName_brightnessDown() {
        let result = SystemActionInfo.find(byOutput: "BrightnessDown")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, "brightness-down")
    }

    // MARK: - Not Found

    func testFindByOutput_unknownReturnsNil() {
        let result = SystemActionInfo.find(byOutput: "nonexistent-action")
        XCTAssertNil(result)
    }

    func testFindByOutput_emptyStringReturnsNil() {
        let result = SystemActionInfo.find(byOutput: "")
        XCTAssertNil(result)
    }

    // MARK: - Kanata Output Generation

    func testKanataOutput_pushMsgAction() {
        let action = SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass")
        XCTAssertEqual(action.kanataOutput, "(push-msg \"system:spotlight\")")
    }

    func testKanataOutput_directKeycode() {
        let action = SystemActionInfo(id: "play-pause", name: "Play/Pause", sfSymbol: "playpause", kanataKeycode: "pp")
        XCTAssertEqual(action.kanataOutput, "pp")
    }

    // MARK: - isMediaKey

    func testIsMediaKey_withKeycode() {
        let mediaAction = SystemActionInfo.find(byOutput: "pp")
        XCTAssertTrue(mediaAction?.isMediaKey ?? false)
    }

    func testIsMediaKey_withoutKeycode() {
        let systemAction = SystemActionInfo.find(byOutput: "spotlight")
        XCTAssertFalse(systemAction?.isMediaKey ?? true)
    }

    // MARK: - All Actions Coverage

    func testAllActions_containsExpectedCount() {
        // 7 push-msg actions + 8 media keys = 15 total
        XCTAssertEqual(SystemActionInfo.allActions.count, 15)
    }

    func testAllActions_pushMsgActions() {
        let pushMsgActions = SystemActionInfo.allActions.filter { !$0.isMediaKey }
        XCTAssertEqual(pushMsgActions.count, 7)

        let ids = Set(pushMsgActions.map(\.id))
        XCTAssertTrue(ids.contains("spotlight"))
        XCTAssertTrue(ids.contains("mission-control"))
        XCTAssertTrue(ids.contains("launchpad"))
        XCTAssertTrue(ids.contains("dnd"))
        XCTAssertTrue(ids.contains("notification-center"))
        XCTAssertTrue(ids.contains("dictation"))
        XCTAssertTrue(ids.contains("siri"))
    }

    func testAllActions_mediaKeys() {
        let mediaKeys = SystemActionInfo.allActions.filter(\.isMediaKey)
        XCTAssertEqual(mediaKeys.count, 8)

        let ids = Set(mediaKeys.map(\.id))
        XCTAssertTrue(ids.contains("play-pause"))
        XCTAssertTrue(ids.contains("next-track"))
        XCTAssertTrue(ids.contains("prev-track"))
        XCTAssertTrue(ids.contains("mute"))
        XCTAssertTrue(ids.contains("volume-up"))
        XCTAssertTrue(ids.contains("volume-down"))
        XCTAssertTrue(ids.contains("brightness-up"))
        XCTAssertTrue(ids.contains("brightness-down"))
    }
}
