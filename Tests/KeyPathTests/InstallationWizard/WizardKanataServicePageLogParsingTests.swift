@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import XCTest

final class WizardKanataServicePageLogParsingTests: XCTestCase {
    func testServiceActionsDoNotDiscardLifecycleResults() throws {
        let sourceURL = projectRootURL()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/UI/Pages/WizardKanataServicePage.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("_ = await kanataManager.startKanata"))
        XCTAssertFalse(source.contains("_ = await kanataManager.restartKanata"))
        XCTAssertFalse(source.contains("_ = await kanataManager.stopKanata"))
        XCTAssertEqual(source.components(separatedBy: "await completeServiceAction(").count - 1, 3)
    }

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

    private func projectRootURL(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
