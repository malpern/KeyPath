@testable import KeyPathAppKit
import XCTest

/// Tests for multi-tap index mapping and tap-dance step management.
final class MapperMultiTapTests: XCTestCase {

    // MARK: - multiTapAction Index Mapping

    @MainActor
    func testMultiTapAction_Count1_ReturnsNil() {
        let vm = MapperViewModel()
        XCTAssertNil(vm.multiTapAction(for: 1))
    }

    @MainActor
    func testMultiTapAction_Count2_ReturnsDoubleTapAction() {
        let vm = MapperViewModel()
        vm.doubleTapAction = "b"
        XCTAssertEqual(vm.multiTapAction(for: 2), "b")
    }

    @MainActor
    func testMultiTapAction_Count2_ReturnsNilWhenEmpty() {
        let vm = MapperViewModel()
        vm.doubleTapAction = ""
        XCTAssertNil(vm.multiTapAction(for: 2))
    }

    @MainActor
    func testMultiTapAction_Count3_ReturnsTapDanceStep0() {
        let vm = MapperViewModel()
        vm.tapDanceSteps = [
            (label: "Triple Tap", action: "c", isRecording: false),
        ]
        XCTAssertEqual(vm.multiTapAction(for: 3), "c")
    }

    @MainActor
    func testMultiTapAction_Count4_ReturnsTapDanceStep1() {
        let vm = MapperViewModel()
        vm.tapDanceSteps = [
            (label: "Triple Tap", action: "c", isRecording: false),
            (label: "Quad Tap", action: "d", isRecording: false),
        ]
        XCTAssertEqual(vm.multiTapAction(for: 4), "d")
    }

    @MainActor
    func testMultiTapAction_OutOfBounds_ReturnsNil() {
        let vm = MapperViewModel()
        XCTAssertNil(vm.multiTapAction(for: 5))
    }

    // MARK: - setMultiTapAction

    @MainActor
    func testSetMultiTapAction_Count2_SetsDoubleTap() {
        let vm = MapperViewModel()
        vm.setMultiTapAction("x", for: 2)
        XCTAssertEqual(vm.doubleTapAction, "x")
    }

    @MainActor
    func testSetMultiTapAction_Count2_ClearsWithNil() {
        let vm = MapperViewModel()
        vm.doubleTapAction = "x"
        vm.setMultiTapAction(nil, for: 2)
        XCTAssertEqual(vm.doubleTapAction, "")
    }

    @MainActor
    func testSetMultiTapAction_Count3_AutoExpands() {
        let vm = MapperViewModel()
        XCTAssertTrue(vm.tapDanceSteps.isEmpty)
        vm.setMultiTapAction("z", for: 3)
        XCTAssertEqual(vm.tapDanceSteps.count, 1)
        XCTAssertEqual(vm.tapDanceSteps[0].action, "z")
    }

    @MainActor
    func testSetMultiTapAction_Count1_IsIgnored() {
        let vm = MapperViewModel()
        vm.setMultiTapAction("a", for: 1)
        XCTAssertTrue(vm.tapDanceSteps.isEmpty)
        XCTAssertTrue(vm.doubleTapAction.isEmpty)
    }

    // MARK: - clearMultiTapAction

    @MainActor
    func testClearMultiTapAction_Count2_ClearsDoubleTap() {
        let vm = MapperViewModel()
        vm.doubleTapAction = "x"
        vm.clearMultiTapAction(for: 2)
        XCTAssertEqual(vm.doubleTapAction, "")
    }

    @MainActor
    func testClearMultiTapAction_Count3_ClearsAndTrims() {
        let vm = MapperViewModel()
        vm.setMultiTapAction("z", for: 3)
        XCTAssertEqual(vm.tapDanceSteps.count, 1)

        vm.clearMultiTapAction(for: 3)
        XCTAssertTrue(vm.tapDanceSteps.isEmpty, "Should trim trailing empty steps")
    }

    @MainActor
    func testClearMultiTapAction_PreservesEarlierNonEmptySteps() {
        let vm = MapperViewModel()
        vm.setMultiTapAction("a", for: 3)
        vm.setMultiTapAction("b", for: 4)
        XCTAssertEqual(vm.tapDanceSteps.count, 2)

        vm.clearMultiTapAction(for: 4)
        XCTAssertEqual(vm.tapDanceSteps.count, 1, "Should trim only trailing empty steps")
        XCTAssertEqual(vm.tapDanceSteps[0].action, "a")
    }

    // MARK: - isRecordingMultiTap

    @MainActor
    func testIsRecordingMultiTap_Count2_ChecksDoubleTap() {
        let vm = MapperViewModel()
        XCTAssertFalse(vm.isRecordingMultiTap(for: 2))
        vm.isRecordingDoubleTap = true
        XCTAssertTrue(vm.isRecordingMultiTap(for: 2))
    }

    @MainActor
    func testIsRecordingMultiTap_Count1_ReturnsFalse() {
        let vm = MapperViewModel()
        XCTAssertFalse(vm.isRecordingMultiTap(for: 1))
    }

    @MainActor
    func testIsRecordingMultiTap_Count3_ChecksTapDanceStep() {
        let vm = MapperViewModel()
        vm.tapDanceSteps = [
            (label: "Triple Tap", action: "", isRecording: true),
        ]
        XCTAssertTrue(vm.isRecordingMultiTap(for: 3))
    }

    // MARK: - Tap-Dance Labels

    @MainActor
    func testTapDanceLabelsAreNonEmpty() {
        XCTAssertFalse(MapperViewModel.tapDanceLabels.isEmpty)
    }

    @MainActor
    func testTapDanceLabelsStartWithTripleTap() {
        XCTAssertEqual(MapperViewModel.tapDanceLabels.first, "Triple Tap")
    }
}
