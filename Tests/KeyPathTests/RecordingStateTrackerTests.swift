@testable import KeyPathAppKit
import XCTest

final class RecordingStateTrackerTests: XCTestCase {
    func testBeginInputSetsActiveAndFlags() {
        var tracker = CustomRuleEditorView.RecordingStateTracker()

        tracker.begin(.input)

        XCTAssertEqual(tracker.active, .input)
        XCTAssertTrue(tracker.isRecording(.input, tapDanceIndex: nil))
        XCTAssertFalse(tracker.isRecording(.output, tapDanceIndex: nil))
        XCTAssertFalse(tracker.isRecording(.hold, tapDanceIndex: nil))
    }

    func testBeginOutputCancelsPrevious() {
        var tracker = CustomRuleEditorView.RecordingStateTracker()
        tracker.begin(.input)

        tracker.begin(.output)

        XCTAssertEqual(tracker.active, .output)
        XCTAssertFalse(tracker.isRecording(.input, tapDanceIndex: nil))
        XCTAssertTrue(tracker.isRecording(.output, tapDanceIndex: nil))
    }

    func testBeginHoldCancelsOtherFlags() {
        var tracker = CustomRuleEditorView.RecordingStateTracker()
        tracker.begin(.output)

        tracker.begin(.hold)

        XCTAssertEqual(tracker.active, .hold)
        XCTAssertFalse(tracker.isRecording(.input, tapDanceIndex: nil))
        XCTAssertFalse(tracker.isRecording(.output, tapDanceIndex: nil))
        XCTAssertTrue(tracker.isRecording(.hold, tapDanceIndex: nil))
    }

    func testBeginTapDanceLeavesKeycapFlagsOff() {
        var tracker = CustomRuleEditorView.RecordingStateTracker()
        tracker.begin(.tapDance(index: 2))

        XCTAssertEqual(tracker.active, .tapDance(index: 2))
        XCTAssertFalse(tracker.isRecording(.input, tapDanceIndex: 2))
        XCTAssertFalse(tracker.isRecording(.output, tapDanceIndex: 2))
        XCTAssertFalse(tracker.isRecording(.hold, tapDanceIndex: 2))
        XCTAssertTrue(tracker.isRecording(.tapDance(index: 2), tapDanceIndex: 2))
        XCTAssertFalse(tracker.isRecording(.tapDance(index: 1), tapDanceIndex: 2))
    }

    func testCancelClearsAll() {
        var tracker = CustomRuleEditorView.RecordingStateTracker()
        tracker.begin(.output)

        tracker.cancel()

        XCTAssertNil(tracker.active)
        XCTAssertFalse(tracker.isRecording(.input, tapDanceIndex: nil))
        XCTAssertFalse(tracker.isRecording(.output, tapDanceIndex: nil))
        XCTAssertFalse(tracker.isRecording(.hold, tapDanceIndex: nil))
        XCTAssertFalse(tracker.isRecording(.tapDance(index: 0), tapDanceIndex: nil))
    }
}
