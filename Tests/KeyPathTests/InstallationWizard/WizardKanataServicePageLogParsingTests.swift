@testable import KeyPathAppKit
import XCTest

final class WizardKanataServicePageLogParsingTests: XCTestCase {
    func testIsLikelyActionableCrashLineReturnsFalseForBrokenPipeNoise() {
        let line = "10:11:51.9102 [ERROR] Error writing ReloadResult: Broken pipe (os error 32)"
        XCTAssertFalse(WizardKanataServicePage.isLikelyActionableCrashLine(line))
    }

    func testIsLikelyActionableCrashLineReturnsFalseForConnectionResetNoise() {
        let line = "[WARN] client sent an invalid message, disconnecting them. Err: Error(\"Connection reset by peer (os error 54)\")"
        XCTAssertFalse(WizardKanataServicePage.isLikelyActionableCrashLine(line))
    }

    func testIsLikelyActionableCrashLineReturnsFalseForKnownIOHIDNoise() {
        let line = "IOHIDDeviceOpen error: (iokit/common) exclusive access and device already open M80H V2"
        XCTAssertFalse(WizardKanataServicePage.isLikelyActionableCrashLine(line))
    }

    func testIsLikelyActionableCrashLineReturnsTrueForFatalLines() {
        let line = "[FATAL] panic in keyboard processing loop"
        XCTAssertTrue(WizardKanataServicePage.isLikelyActionableCrashLine(line))
    }

    func testIsLikelyActionableCrashLineReturnsFalseForNonErrorLines() {
        let line = "[INFO] Live reload successful"
        XCTAssertFalse(WizardKanataServicePage.isLikelyActionableCrashLine(line))
    }
}
