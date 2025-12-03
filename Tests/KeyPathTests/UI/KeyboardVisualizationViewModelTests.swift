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
}
