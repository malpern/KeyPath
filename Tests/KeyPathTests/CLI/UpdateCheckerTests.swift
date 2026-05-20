@testable import KeyPathCLI
import XCTest

final class UpdateCheckerTests: XCTestCase {
    func testNewerMajorVersion() {
        XCTAssertTrue(UpdateChecker.compareVersions("2.0.0", isNewerThan: "1.0.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(UpdateChecker.compareVersions("1.1.0", isNewerThan: "1.0.0"))
    }

    func testNewerPatchVersion() {
        XCTAssertTrue(UpdateChecker.compareVersions("1.0.1", isNewerThan: "1.0.0"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.compareVersions("1.0.0", isNewerThan: "1.0.0"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.compareVersions("1.0.0", isNewerThan: "2.0.0"))
    }

    func testReleaseBeatsPreRelease() {
        XCTAssertTrue(UpdateChecker.compareVersions("1.0.0", isNewerThan: "1.0.0-beta3"))
    }

    func testPreReleaseDoesNotBeatRelease() {
        XCTAssertFalse(UpdateChecker.compareVersions("1.0.0-beta3", isNewerThan: "1.0.0"))
    }

    func testNewerWithBetaSuffix() {
        XCTAssertTrue(UpdateChecker.compareVersions("1.1.0-beta1", isNewerThan: "1.0.0"))
    }
}
