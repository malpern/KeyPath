@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

final class DuplicateAppDetectorTests: XCTestCase {
    override func tearDown() async throws {
        DuplicateAppDetector.testDuplicateAppPathsOverride = nil
        DuplicateAppDetector.testDuplicateScanRunner = nil
        DuplicateAppDetector.testReadOnlyVolumeOverride = nil
        try await super.tearDown()
    }

    func testDetectDuplicateAppCopiesFiltersBuildPathsAndSortsApplicationsFirst() async {
        DuplicateAppDetector.testDuplicateAppPathsOverride = {
            [
                "/Users/test/Downloads/KeyPath.app",
                "/dist/KeyPath.app",
                "/Volumes/Cache/Sparkle_generate_appcast/abc123/KeyPath.app",
                "/Applications/KeyPath.app",
                "/Users/test/KeyPath.app"
            ]
        }

        let copies = await DuplicateAppDetector.detectDuplicateAppCopies()
        XCTAssertEqual(copies.first, "/Applications/KeyPath.app")
        let remaining = Set(copies.dropFirst())
        XCTAssertEqual(
            remaining,
            Set([
                "/Users/test/KeyPath.app",
                "/Users/test/Downloads/KeyPath.app"
            ])
        )
    }

    func testDetectDuplicateAppCopiesUsesBoundedSpotlightScan() async {
        let runner = SubprocessRunnerFake()
        await runner.configureRunResult { _, _ in
            ProcessResult(
                exitCode: 0,
                stdout: "/Applications/KeyPath.app\n/Users/test/Downloads/KeyPath.app\n",
                stderr: "",
                duration: 0.01
            )
        }
        DuplicateAppDetector.testDuplicateScanRunner = runner

        let copies = await DuplicateAppDetector.detectDuplicateAppCopies()

        XCTAssertEqual(copies, ["/Applications/KeyPath.app", "/Users/test/Downloads/KeyPath.app"])
        let commands = await runner.executedCommands
        XCTAssertEqual(commands.first?.executable, "/usr/bin/mdfind")
        XCTAssertEqual(DuplicateAppDetector.duplicateScanTimeout, 2)
        XCTAssertTrue(DuplicateAppDetector.duplicateScanExcludedPathFragments.contains("/Sparkle_generate_appcast/"))
        DuplicateAppDetector.testDuplicateScanRunner = nil
    }

    func testDetectDuplicateAppCopiesFallsBackWhenSpotlightTimesOut() async {
        let runner = SubprocessRunnerFake()
        await runner.setShouldTimeout(true)
        DuplicateAppDetector.testDuplicateScanRunner = runner

        let copies = await DuplicateAppDetector.detectDuplicateAppCopies()

        // A stalled Spotlight must degrade to the canonical locations, never hang, and
        // never report a location that does not exist (which read as a phantom duplicate).
        XCTAssertTrue(copies.allSatisfy { $0.hasSuffix("/KeyPath.app") })
        XCTAssertTrue(copies.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        DuplicateAppDetector.testDuplicateScanRunner = nil
    }

    /// Air, 2026-10-18: a mounted installer image (/Volumes/KeyPath) was listed as
    /// an installed copy that "Remove Extra Copies" could never trash.
    func testDetectDuplicateAppCopiesIgnoresReadOnlyVolumes() async {
        DuplicateAppDetector.testDuplicateAppPathsOverride = {
            ["/Applications/KeyPath.app", "/Volumes/KeyPath/KeyPath.app", "/Users/test/Old/KeyPath.app"]
        }
        DuplicateAppDetector.testReadOnlyVolumeOverride = { $0.hasPrefix("/Volumes/KeyPath/") }
        defer { DuplicateAppDetector.testReadOnlyVolumeOverride = nil }

        let copies = await DuplicateAppDetector.detectDuplicateAppCopies()
        XCTAssertEqual(copies, ["/Applications/KeyPath.app", "/Users/test/Old/KeyPath.app"])
    }

    func testDisplayLocationUsesFinderNamesForHomeAndICloud() {
        let home = "/Users/test"
        XCTAssertEqual(
            DuplicateAppDetector.displayLocation(
                forAppAt: home + "/Library/Mobile Documents/com~apple~CloudDocs/Documents/Codex/KeyPath.app", home: home
            ),
            "iCloud Drive \u{203A} Documents \u{203A} Codex"
        )
        XCTAssertEqual(DuplicateAppDetector.displayLocation(forAppAt: home + "/Downloads/KeyPath.app", home: home),
                       "Home \u{203A} Downloads")
        XCTAssertEqual(DuplicateAppDetector.displayLocation(forAppAt: "/Volumes/Backup/KeyPath.app", home: home),
                       "Volumes \u{203A} Backup")
    }
}
