import CoreGraphics
@testable import KeyPathAppKit
import XCTest

/// Re-posted keys keep the flags macOS attaches to the key itself. Without Fn
/// and the keypad flag, Ctrl+arrow no longer matches the Mission Control
/// Space-switch shortcuts, which are registered as Control + Fn.
final class SessionKeyIntrinsicFlagsTests: XCTestCase {
    private func defaultFlags(_ keyCode: CGKeyCode) throws -> CGEventFlags {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        return try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)).flags
    }

    func testArrowOutputKeepsFnAndKeypadWithKanataControl() throws {
        for arrow: CGKeyCode in [123, 124, 125, 126] {
            let flags = try SessionRuntimeWorker.outputFlags(
                keyDefault: defaultFlags(arrow), output: CGEventFlags.maskControl.rawValue, passthrough: 0, capsLock: 0
            )
            XCTAssertTrue(flags.contains(.maskControl), "arrow \(arrow)")
            XCTAssertTrue(flags.contains(.maskSecondaryFn), "arrow \(arrow)")
            XCTAssertTrue(flags.contains(.maskNumericPad), "arrow \(arrow)")
        }
    }

    func testLetterOutputGainsNoIntrinsicFlags() throws {
        let flags = try SessionRuntimeWorker.outputFlags(
            keyDefault: defaultFlags(0), output: CGEventFlags.maskShift.rawValue, passthrough: 0, capsLock: 0
        )
        XCTAssertEqual(flags, .maskShift)
    }

    func testOnlyIntrinsicFlagsComeFromTheDefaultEvent() {
        // A stale modifier in the event source's state must not leak into output.
        let flags = SessionRuntimeWorker.outputFlags(
            keyDefault: [.maskCommand, .maskSecondaryFn], output: 0, passthrough: 0, capsLock: 0
        )
        XCTAssertEqual(flags, .maskSecondaryFn)
    }

    func testPassthroughCapsLockBitDefersToLiveState() {
        let flags = SessionRuntimeWorker.outputFlags(
            keyDefault: [], output: 0,
            passthrough: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskAlphaShift.rawValue, capsLock: 0
        )
        XCTAssertEqual(flags, .maskAlternate)
    }
}
