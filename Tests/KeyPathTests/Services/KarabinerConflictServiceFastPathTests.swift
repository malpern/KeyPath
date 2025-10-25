import XCTest
@testable import KeyPath

@MainActor
final class KarabinerConflictServiceFastPathTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testIsKarabinerElementsRunningRespectsDisabledMarker() async {
        // Create the disabled marker file to force early return path
        let marker = tempHome.appendingPathComponent(".keypath/karabiner-grabber-disabled")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())

        let svc = KarabinerConflictService()
        let running = svc.isKarabinerElementsRunning()
        XCTAssertFalse(running, "Disabled marker should short-circuit to false without shelling out")
    }

    func testKillCommandContainsExpectedPieces() {
        let cmd = KarabinerConflictService().getKillKarabinerCommand()
        XCTAssertTrue(cmd.contains("launchctl unload"))
        XCTAssertTrue(cmd.contains("pkill -f karabiner_grabber"))
    }
}

