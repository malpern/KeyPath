import CoreGraphics
@testable import KeyPathAppKit
import XCTest

@MainActor
final class KeyboardVisualizationViewModelTests: XCTestCase {
    // MARK: - TCP-Based Key Press/Release Tests

    func testTcpKeyPressAddsToPressed() async {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.simulateTcpKeyInput(key: "lmet", action: "press")
        await Task.yield()

        // lmet (left command) = keyCode 55
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55))
    }

    func testTcpKeyReleaseRemovesFromPressed() async {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.simulateTcpKeyInput(key: "lmet", action: "press")
        await Task.yield()
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55))

        viewModel.simulateTcpKeyInput(key: "lmet", action: "release")
        await Task.yield()
        XCTAssertFalse(viewModel.pressedKeyCodes.contains(55))
    }

    func testMultipleModifiersCanBePressed() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press left command
        viewModel.simulateTcpKeyInput(key: "lmet", action: "press")
        await Task.yield()

        // Press left alt
        viewModel.simulateTcpKeyInput(key: "lalt", action: "press")
        await Task.yield()

        // Both should be pressed
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55)) // lmet
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(58)) // lalt
    }

    func testReleaseOneModifierKeepsOther() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press both modifiers
        viewModel.simulateTcpKeyInput(key: "lmet", action: "press")
        await Task.yield()
        viewModel.simulateTcpKeyInput(key: "lalt", action: "press")
        await Task.yield()

        // Release only alt
        viewModel.simulateTcpKeyInput(key: "lalt", action: "release")
        await Task.yield()

        // Command should still be pressed
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55))
        XCTAssertFalse(viewModel.pressedKeyCodes.contains(58))
    }

    func testHoldActivatedSetsLabelAndClearsOnRelease() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Simulate tap-hold crossing into hold state (Hyper)
        viewModel.simulateHoldActivated(key: "caps", action: "lctl+lmet+lalt+lsft")
        await Task.yield()

        // caps -> keyCode 57
        XCTAssertEqual(viewModel.holdLabels[57], "✦")

        // Releasing the key should clear the hold label
        viewModel.simulateTcpKeyInput(key: "caps", action: "release")
        await Task.yield()

        XCTAssertNil(viewModel.holdLabels[57])
    }

    func testKanataConnectedStateUpdatesOnTcpInput() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Initially not connected
        XCTAssertFalse(viewModel.isKanataConnected)

        // Simulate TCP input - should mark as connected
        viewModel.simulateTcpKeyInput(key: "a", action: "press")
        await Task.yield()

        XCTAssertTrue(viewModel.isKanataConnected)
    }

    func testKanataConnectedStateUpdatesOnLayerChange() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Initially not connected
        XCTAssertFalse(viewModel.isKanataConnected)

        // Layer change also marks as connected
        viewModel.updateLayer("nav")
        await Task.yield()

        XCTAssertTrue(viewModel.isKanataConnected)
    }

    func testCapslockKeyCodeMapping() async {
        let viewModel = KeyboardVisualizationViewModel()

        // caps/capslock should map to keyCode 57 (not 58)
        viewModel.simulateTcpKeyInput(key: "caps", action: "press")
        await Task.yield()

        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(57),
            "caps should map to keyCode 57"
        )
        XCTAssertFalse(
            viewModel.pressedKeyCodes.contains(58),
            "caps should NOT map to keyCode 58 (that's lalt)"
        )
    }

    func testCapslockAlternateNameMapping() async {
        let viewModel = KeyboardVisualizationViewModel()

        // 'capslock' should also map to keyCode 57
        viewModel.simulateTcpKeyInput(key: "capslock", action: "press")
        await Task.yield()

        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(57),
            "capslock should map to keyCode 57"
        )
    }

    // MARK: - Push-Msg Extraction Tests

    func testExtractPushMsgInfoLaunch() {
        let output = #"(push-msg "launch:Safari")"#
        let result = KeyboardVisualizationViewModel.extractPushMsgInfo(from: output, description: nil)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.appLaunchIdentifier, "Safari")
    }

    func testExtractPushMsgInfoSystem() {
        let output = #"(push-msg "system:spotlight")"#
        let result = KeyboardVisualizationViewModel.extractPushMsgInfo(from: output, description: nil)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.systemActionIdentifier, "spotlight")
        XCTAssertEqual(result?.displayLabel, "Spotlight")
    }

    func testExtractPushMsgInfoReturnsNilForNonMatching() {
        let output = "some random string"
        let result = KeyboardVisualizationViewModel.extractPushMsgInfo(from: output, description: nil)
        XCTAssertNil(result)
    }

    func testExtractAppLaunchIdentifier() {
        let output = #"(push-msg "launch:Terminal")"#
        let result = KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: output)
        XCTAssertEqual(result, "Terminal")
    }

    func testExtractAppLaunchIdentifierWithBundleId() {
        let output = #"(push-msg "launch:com.apple.finder")"#
        let result = KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: output)
        XCTAssertEqual(result, "com.apple.finder")
    }

    func testExtractAppLaunchIdentifierReturnsNilForNonLaunch() {
        let output = #"(push-msg "system:spotlight")"#
        let result = KeyboardVisualizationViewModel.extractAppLaunchIdentifier(from: output)
        XCTAssertNil(result)
    }

    func testExtractUrlIdentifier() {
        let output = #"(push-msg "open:github.com")"#
        let result = KeyboardVisualizationViewModel.extractUrlIdentifier(from: output)
        XCTAssertEqual(result, "github.com")
    }

    func testExtractUrlIdentifierWithHttps() {
        let output = #"(push-msg "open:https://example.com/path")"#
        let result = KeyboardVisualizationViewModel.extractUrlIdentifier(from: output)
        XCTAssertEqual(result, "https://example.com/path")
    }

    func testExtractUrlIdentifierReturnsNilForNonOpen() {
        let output = #"(push-msg "launch:Safari")"#
        let result = KeyboardVisualizationViewModel.extractUrlIdentifier(from: output)
        XCTAssertNil(result)
    }

    // MARK: - Key Emphasis Tests

    func testEmphasizedKeyCodesOnNavLayer() {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.currentLayerName = "nav"
        viewModel.layerKeyMap = [
            4: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: 123),
            38: .mapped(displayLabel: "↓", outputKey: "down", outputKeyCode: 125),
            40: .mapped(displayLabel: "↑", outputKey: "up", outputKeyCode: 126),
            37: .mapped(displayLabel: "→", outputKey: "right", outputKeyCode: 124),
        ]

        let emphasized = viewModel.emphasizedKeyCodes

        // h=4, j=38, k=40, l=37 should be emphasized
        XCTAssertTrue(emphasized.contains(4), "h (keyCode 4) should be emphasized")
        XCTAssertTrue(emphasized.contains(38), "j (keyCode 38) should be emphasized")
        XCTAssertTrue(emphasized.contains(40), "k (keyCode 40) should be emphasized")
        XCTAssertTrue(emphasized.contains(37), "l (keyCode 37) should be emphasized")
    }

    func testEmphasizedKeyCodesOnBaseLayer() {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.currentLayerName = "base"

        let emphasized = viewModel.emphasizedKeyCodes

        // HJKL should NOT be emphasized on base layer
        XCTAssertFalse(emphasized.contains(4))
        XCTAssertFalse(emphasized.contains(38))
        XCTAssertFalse(emphasized.contains(40))
        XCTAssertFalse(emphasized.contains(37))
    }

    func testKanataNameToKeyCodeMapsCorrectly() {
        // Test a few key mappings to ensure the lookup works
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("h"), 4)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("j"), 38)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("k"), 40)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("l"), 37)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("space"), 49)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("caps"), 57)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("capslock"), 57)
        XCTAssertNil(KeyboardVisualizationViewModel.kanataNameToKeyCode("unknown-key"))
    }

    func testKanataNameToKeyCode_navigationKeys() {
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("home"), 115)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("pageup"), 116)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("pgup"), 116)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("end"), 119)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("pagedown"), 121)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("pgdn"), 121)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("help"), 114)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("insert"), 114)
    }

    func testKanataNameToKeyCode_extendedFunctionKeys() {
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f13"), 105)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f14"), 107)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f15"), 113)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f16"), 106)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f17"), 64)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f18"), 79)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("f19"), 80)
    }

    func testKanataNameToKeyCode_rightControl() {
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("rightctrl"), 102)
        XCTAssertEqual(KeyboardVisualizationViewModel.kanataNameToKeyCode("rctl"), 102)
    }

    // MARK: - Tap-Hold Output Suppression Tests

    func testCapslockSuppressesEscFromLightingUp() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press capslock (tap-hold source key)
        viewModel.simulateTcpKeyInput(key: "caps", action: "press")
        await Task.yield()

        // Capslock should be in pressedKeyCodes
        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(57),
            "Capslock (57) should be pressed"
        )

        // Now simulate ESC KeyInput (tap output of capslock)
        viewModel.simulateTcpKeyInput(key: "esc", action: "press")
        await Task.yield()

        // ESC should NOT be in pressedKeyCodes (suppressed)
        XCTAssertFalse(
            viewModel.pressedKeyCodes.contains(53),
            "ESC (53) should be suppressed while capslock is pressed"
        )

        // Capslock should still be pressed
        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(57),
            "Capslock should still be pressed"
        )
    }

    func testEscWorksNormallyWhenCapslockNotPressed() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press ESC directly (no capslock active)
        viewModel.simulateTcpKeyInput(key: "esc", action: "press")
        await Task.yield()

        // ESC should be in pressedKeyCodes
        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(53),
            "ESC (53) should light up when pressed directly"
        )
    }

    func testEscWorksAfterCapslockReleased() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press and release capslock
        viewModel.simulateTcpKeyInput(key: "caps", action: "press")
        await Task.yield()
        viewModel.simulateTcpKeyInput(key: "caps", action: "release")
        await Task.yield()

        // Now press ESC - should work normally
        viewModel.simulateTcpKeyInput(key: "esc", action: "press")
        await Task.yield()

        // ESC should be in pressedKeyCodes
        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(53),
            "ESC (53) should light up after capslock is released"
        )
    }

    func testEffectivePressedKeyCodesShowsCapslockNotEsc() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press capslock
        viewModel.simulateTcpKeyInput(key: "caps", action: "press")
        await Task.yield()

        // Simulate ESC (suppressed)
        viewModel.simulateTcpKeyInput(key: "esc", action: "press")
        await Task.yield()

        // effectivePressedKeyCodes should contain capslock but not ESC
        let effective = viewModel.effectivePressedKeyCodes
        XCTAssertTrue(effective.contains(57), "Capslock should be in effectivePressedKeyCodes")
        XCTAssertFalse(effective.contains(53), "ESC should NOT be in effectivePressedKeyCodes")
    }

    // MARK: - TapActivated Dynamic Mapping Tests

    func testTapActivatedPopulatesDynamicMap() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Simulate TapActivated event (caps -> esc)
        viewModel.simulateTapActivated(key: "caps", action: "esc")
        await Task.yield()

        // Now press caps and then esc
        viewModel.simulateTcpKeyInput(key: "caps", action: "press")
        await Task.yield()

        viewModel.simulateTcpKeyInput(key: "esc", action: "press")
        await Task.yield()

        // ESC should be suppressed because dynamic map now knows caps -> esc
        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(57),
            "Capslock (57) should be pressed"
        )
        XCTAssertFalse(
            viewModel.pressedKeyCodes.contains(53),
            "ESC (53) should be suppressed via dynamic map"
        )
    }

    func testTapActivatedWithDifferentKey() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Simulate TapActivated event (space -> enter)
        viewModel.simulateTapActivated(key: "space", action: "enter")
        await Task.yield()

        // Press space, then enter
        viewModel.simulateTcpKeyInput(key: "space", action: "press")
        await Task.yield()

        viewModel.simulateTcpKeyInput(key: "enter", action: "press")
        await Task.yield()

        // Enter (36) should be suppressed because dynamic map now knows space -> enter
        XCTAssertTrue(
            viewModel.pressedKeyCodes.contains(49),
            "Space (49) should be pressed"
        )
        XCTAssertFalse(
            viewModel.pressedKeyCodes.contains(36),
            "Enter (36) should be suppressed via dynamic map"
        )
    }

    func testTapActivatedWithEmptyActionDoesNotCrash() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Simulate TapActivated with empty action (should not crash)
        viewModel.simulateTapActivated(key: "caps", action: "")
        await Task.yield()

        // Verify viewModel is still functional
        viewModel.simulateTcpKeyInput(key: "a", action: "press")
        await Task.yield()

        XCTAssertTrue(viewModel.pressedKeyCodes.contains(0), "Key 'a' should be pressed")
    }

    func testTapActivatedWithUnknownKeyDoesNotCrash() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Simulate TapActivated with unknown key (should not crash)
        viewModel.simulateTapActivated(key: "unknown-key", action: "esc")
        await Task.yield()

        // Verify viewModel is still functional
        viewModel.simulateTcpKeyInput(key: "b", action: "press")
        await Task.yield()

        XCTAssertTrue(viewModel.pressedKeyCodes.contains(11), "Key 'b' should be pressed")
    }

    // MARK: - Launcher Mode Detection Tests

    func testIsLauncherModeActiveWhenLayerIsLauncher() {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.updateLayer("launcher")

        XCTAssertTrue(viewModel.isLauncherModeActive, "Launcher mode should be active when layer is 'launcher'")
    }

    func testIsLauncherModeActiveIsCaseInsensitive() {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.updateLayer("Launcher")

        XCTAssertTrue(viewModel.isLauncherModeActive, "Launcher mode detection should be case insensitive")
    }

    func testIsLauncherModeInactiveForBaseLayer() {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.updateLayer("base")

        XCTAssertFalse(viewModel.isLauncherModeActive, "Launcher mode should be inactive for 'base' layer")
    }

    func testIsLauncherModeInactiveForNavLayer() {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.updateLayer("nav")

        XCTAssertFalse(viewModel.isLauncherModeActive, "Launcher mode should be inactive for 'nav' layer")
    }

    func testLauncherMappingsEmptyByDefault() {
        let viewModel = KeyboardVisualizationViewModel()

        XCTAssertTrue(viewModel.launcherMappings.isEmpty, "Launcher mappings should be empty by default")
    }

    func testLauncherMappingsClearedWhenExitingLauncherMode() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Enter launcher mode (which triggers async loading)
        viewModel.updateLayer("launcher")
        try? await Task.sleep(for: .milliseconds(100))

        // Exit launcher mode
        viewModel.updateLayer("base")

        XCTAssertTrue(viewModel.launcherMappings.isEmpty, "Launcher mappings should be cleared when exiting launcher mode")
    }

    // MARK: - Hovered Rule Key Code Tests

    func testHoveredRuleKeyCodeIsNilByDefault() {
        let viewModel = KeyboardVisualizationViewModel()
        XCTAssertNil(viewModel.hoveredRuleKeyCode, "hoveredRuleKeyCode should be nil by default")
    }

    func testHoveredRuleKeyCodeCanBeSet() {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.hoveredRuleKeyCode = 38 // j key
        XCTAssertEqual(viewModel.hoveredRuleKeyCode, 38)

        viewModel.hoveredRuleKeyCode = nil
        XCTAssertNil(viewModel.hoveredRuleKeyCode)
    }

    // MARK: - LogicalKeymap Reverse Lookup Tests

    func testKeyCodeForQwertyLabel_homeRowKeys() {
        // Test home row keys (ASDFGHJKL;)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "a"), 0)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "s"), 1)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "d"), 2)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "f"), 3)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "g"), 5)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "h"), 4)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "j"), 38)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "k"), 40)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "l"), 37)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: ";"), 41)
    }

    func testKeyCodeForQwertyLabel_topRowKeys() {
        // Test top row keys (QWERTYUIOP)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "q"), 12)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "w"), 13)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "e"), 14)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "r"), 15)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "t"), 17)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "y"), 16)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "u"), 32)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "i"), 34)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "o"), 31)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "p"), 35)
    }

    func testKeyCodeForQwertyLabel_bottomRowKeys() {
        // Test bottom row keys (ZXCVBNM,./)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "z"), 6)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "x"), 7)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "c"), 8)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "v"), 9)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "b"), 11)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "n"), 45)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "m"), 46)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: ","), 43)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "."), 47)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "/"), 44)
    }

    func testKeyCodeForQwertyLabel_caseInsensitive() {
        // Should work with uppercase letters
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "A"), 0)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "J"), 38)
        XCTAssertEqual(LogicalKeymap.keyCode(forQwertyLabel: "Z"), 6)
    }

    func testKeyCodeForQwertyLabel_unknownKeyReturnsNil() {
        XCTAssertNil(LogicalKeymap.keyCode(forQwertyLabel: "unknown"))
        XCTAssertNil(LogicalKeymap.keyCode(forQwertyLabel: ""))
        XCTAssertNil(LogicalKeymap.keyCode(forQwertyLabel: "space"))
    }
}
