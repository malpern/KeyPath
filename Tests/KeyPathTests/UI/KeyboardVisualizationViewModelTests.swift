import CoreGraphics
@testable import KeyPathAppKit
import XCTest

@MainActor
final class KeyboardVisualizationViewModelTests: XCTestCase {
    func testCommandAndOptionStayPressedTogether() async {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 55)
        await Task.yield()

        viewModel.simulateFlagsChanged(flags: [.maskCommand, .maskAlternate], keyCode: 58)
        await Task.yield()

        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55))
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(58))
    }

    func testCommandClearsWhenFlagDrops() async {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 55)
        await Task.yield()

        viewModel.simulateFlagsChanged(flags: [], keyCode: 55)
        await Task.yield()

        XCTAssertFalse(viewModel.pressedKeyCodes.contains(55))
    }

    func testOptionReleaseKeepsCommandPressed() async {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 55)
        await Task.yield()

        viewModel.simulateFlagsChanged(flags: [.maskCommand, .maskAlternate], keyCode: 58)
        await Task.yield()

        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 58)
        await Task.yield()

        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55))
        XCTAssertFalse(viewModel.pressedKeyCodes.contains(58))
    }

    func testSimultaneousCommandReleaseClearsBothSides() async {
        let viewModel = KeyboardVisualizationViewModel()

        // Press both command keys
        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 55)
        await Task.yield()
        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 54)
        await Task.yield()

        XCTAssertTrue(viewModel.pressedKeyCodes.contains(55))
        XCTAssertTrue(viewModel.pressedKeyCodes.contains(54))

        // Release both – flags snapshot shows none pressed
        viewModel.simulateFlagsChanged(flags: [], keyCode: 55)
        await Task.yield()
        viewModel.simulateFlagsChanged(flags: [], keyCode: 54)
        await Task.yield()

        XCTAssertFalse(viewModel.pressedKeyCodes.contains(55))
        XCTAssertFalse(viewModel.pressedKeyCodes.contains(54))
    }

    func testZeroKeyCodeSnapshotClearsCommandsWhenFlagAbsent() async {
        let viewModel = KeyboardVisualizationViewModel()

        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 55)
        await Task.yield()
        viewModel.simulateFlagsChanged(flags: [.maskCommand], keyCode: 54)
        await Task.yield()

        // System can emit keyCode 0 with flags cleared; ensure we reconcile both sides
        viewModel.simulateFlagsChanged(flags: [], keyCode: 0)
        await Task.yield()

        XCTAssertFalse(viewModel.pressedKeyCodes.contains(55))
        XCTAssertFalse(viewModel.pressedKeyCodes.contains(54))
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

    // MARK: - Key Emphasis Tests

    func testEmphasizedKeyCodesOnNavLayer() async {
        let viewModel = KeyboardVisualizationViewModel()
        viewModel.currentLayerName = "nav"

        let emphasized = viewModel.emphasizedKeyCodes

        // h=4, j=38, k=40, l=37 should be emphasized
        XCTAssertTrue(emphasized.contains(4), "h (keyCode 4) should be emphasized")
        XCTAssertTrue(emphasized.contains(38), "j (keyCode 38) should be emphasized")
        XCTAssertTrue(emphasized.contains(40), "k (keyCode 40) should be emphasized")
        XCTAssertTrue(emphasized.contains(37), "l (keyCode 37) should be emphasized")
    }

    func testEmphasizedKeyCodesOnBaseLayer() async {
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
}
