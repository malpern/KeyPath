import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class OrphanDetectorTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/test-home", isDirectory: true)
    private let launch = Date(timeIntervalSince1970: 1_000)

    func testCurrentLaunchPathsDoNotLookLikeOrphans() {
        let detector = makeDetector(dates: [
            "Library/Application Support/KeyPath": launch.addingTimeInterval(1),
            "Library/Logs/KeyPath": launch.addingTimeInterval(2),
            "Library/Preferences/com.keypath.KeyPath.plist": launch.addingTimeInterval(3)
        ])

        XCTAssertFalse(detector.detectOrphanedInstall())
    }

    func testTwoPathsPredatingLaunchAreAnOrphanedInstall() {
        let detector = makeDetector(dates: [
            "Library/Application Support/KeyPath": launch.addingTimeInterval(-100),
            "Library/Logs/KeyPath": launch.addingTimeInterval(-90)
        ])

        XCTAssertTrue(detector.detectOrphanedInstall())
    }

    func testOneOldPathAndCurrentLaunchOutputIsNotEnough() {
        let detector = makeDetector(dates: [
            "Library/Application Support/KeyPath": launch.addingTimeInterval(-100),
            "Library/Logs/KeyPath": launch.addingTimeInterval(1),
            "Library/Preferences/com.keypath.KeyPath.plist": launch.addingTimeInterval(2)
        ])

        XCTAssertFalse(detector.detectOrphanedInstall())
    }

    private func makeDetector(dates: [String: Date]) -> OrphanDetector {
        OrphanDetector(
            homeDirectory: home,
            creationDate: { [home] url in
                dates[url.path.replacingOccurrences(of: home.path + "/", with: "")]
            },
            launchDate: { [launch] in launch }
        )
    }
}
