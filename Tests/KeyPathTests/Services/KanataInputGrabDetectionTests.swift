@testable import KeyPathInstallationWizard
import XCTest

/// Tests for detecting kanata "up but not grabbing the keyboard" from stderr.
///
/// Regression for #624: kanata can panic/abort while initializing the Karabiner
/// virtual-HID input path — it stays alive (process + TCP) but never grabs the
/// keyboard, so no remapping happens, yet the health check reported green. The fix
/// teaches `diagnoseDaemonStderr` to recognize this via `detectsInputGrabFailure`,
/// which flips `inputCaptureReady` false → the existing health decision marks it
/// unhealthy (recoverable).
final class KanataInputGrabDetectionTests: XCTestCase {
    /// Verbatim stderr block captured from the live failure (2026-05-29).
    private let realCrashBlock = """
    [kanata-launcher] Using kanata binary: /Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata

    thread 'main' (322660) panicked at /Users/malpern/.cargo/registry/src/index.crates.io/karabiner-driverkit-0.1.0/src/lib.rs:42:
    CString::new failed: NulError(12, [49, 239, 191, 189, 43, 239, 191, 189, 43, 239, 191, 189, 0, 0])
    note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace

    kanata: aborted while talking to the Karabiner virtual HID daemon.
    The most likely causes, in order:
    1) kanata is not running as root.
    2) Karabiner-DriverKit-VirtualHIDDevice is not installed or its
    system extension has not been approved.
    3) Another process is already grabbing your keyboard exclusively.
    """

    func testDetectsFullAbortBlock() {
        XCTAssertTrue(ServiceHealthChecker.detectsInputGrabFailure(in: realCrashBlock))
    }

    func testDetectsAbortLineAlone() {
        let log = "kanata: aborted while talking to the Karabiner virtual HID daemon."
        XCTAssertTrue(ServiceHealthChecker.detectsInputGrabFailure(in: log))
    }

    func testDetectsExclusiveGrabCause() {
        let log = "3) Another process is already grabbing your keyboard exclusively."
        XCTAssertTrue(ServiceHealthChecker.detectsInputGrabFailure(in: log))
    }

    func testDetectsDriverkitPanic() {
        let log = "thread 'main' panicked at .../karabiner-driverkit-0.1.0/src/lib.rs:42:"
        XCTAssertTrue(ServiceHealthChecker.detectsInputGrabFailure(in: log))
    }

    func testHealthyLogIsNotFlagged() {
        let log = """
        [kanata-launcher] Launching Kanata for user=malpern config=/Users/malpern/.config/keypath/keypath.kbd
        [kanata-launcher] Host bridge validated config successfully
        [kanata-launcher] Host bridge created runtime successfully: layer_count=2
        14:41:22 [INFO] listening for incoming messages 127.0.0.1:60819
        virtual_hid_keyboard_ready true
        """
        XCTAssertFalse(ServiceHealthChecker.detectsInputGrabFailure(in: log))
    }

    func testUnrelatedPanicIsNotFlagged() {
        // A panic NOT in the karabiner-driverkit path should not be mistaken for a
        // keyboard-grab failure (avoids over-matching generic Rust panics).
        let log = "thread 'main' panicked at src/main.rs:10: some unrelated error"
        XCTAssertFalse(ServiceHealthChecker.detectsInputGrabFailure(in: log))
    }

    func testConfigParseErrorIsNotGrabFailure() {
        let log = "[ERROR] Error in configuration\nhelp: Duplicate alias: foo\nfailed to parse file"
        XCTAssertFalse(ServiceHealthChecker.detectsInputGrabFailure(in: log))
    }
}
