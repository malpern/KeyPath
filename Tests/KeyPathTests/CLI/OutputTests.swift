@testable import KeyPathCLI
import XCTest

final class OutputTests: XCTestCase {
    func testShouldOutputJSON_whenForceJSON() {
        let ctx = OutputContext(isInteractive: true, forceJSON: true, forceHuman: false, noColor: false)
        XCTAssertTrue(ctx.shouldOutputJSON)
    }

    func testShouldOutputJSON_whenNotInteractive() {
        let ctx = OutputContext(isInteractive: false, forceJSON: false, forceHuman: false, noColor: false)
        XCTAssertTrue(ctx.shouldOutputJSON)
    }

    func testShouldOutputHuman_whenInteractiveNoFlags() {
        let ctx = OutputContext(isInteractive: true, forceJSON: false, forceHuman: false, noColor: false)
        XCTAssertFalse(ctx.shouldOutputJSON)
    }

    func testShouldOutputHuman_whenForceNoJSON() {
        let ctx = OutputContext(isInteractive: false, forceJSON: false, forceHuman: true, noColor: false)
        XCTAssertFalse(ctx.shouldOutputJSON)
    }

    func testNoColorRespectsEnvironment() {
        let ctx = OutputContext(isInteractive: true, forceJSON: false, forceHuman: false, noColor: true)
        XCTAssertTrue(ctx.noColor)

        let ctx2 = OutputContext(isInteractive: true, forceJSON: false, forceHuman: false, noColor: false)
        XCTAssertFalse(ctx2.noColor)
    }

    func testForceJSONOverridesForceHuman() {
        let ctx = OutputContext(isInteractive: true, forceJSON: true, forceHuman: true, noColor: false)
        XCTAssertTrue(ctx.shouldOutputJSON, "--json should win when both flags are set")
    }
}
