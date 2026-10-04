@testable import KeyPathAppKit
import XCTest

final class ApplicationLaunchGateTests: XCTestCase {
    func testBootstrapLaunchEventWaitsForDependencies() {
        var gate = ApplicationLaunchGate()
        XCTAssertFalse(gate.didFinishLaunching())
        XCTAssertFalse(gate.didFinishLaunching())
        XCTAssertTrue(gate.didConfigure())
        XCTAssertFalse(gate.didFinishLaunching())
    }

    func testNormalLaunchAfterConfigurationStartsOnce() {
        var gate = ApplicationLaunchGate()
        XCTAssertFalse(gate.didConfigure())
        XCTAssertTrue(gate.didFinishLaunching())
        XCTAssertFalse(gate.didFinishLaunching())
        XCTAssertFalse(gate.didConfigure())
    }

    func testConfigurationAloneCannotInventLaunchEvent() {
        var gate = ApplicationLaunchGate()
        XCTAssertFalse(gate.didConfigure())
        XCTAssertFalse(gate.didConfigure())
    }
}
