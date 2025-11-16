import XCTest
@testable import KeyPath

@MainActor
final class HelperMaintenanceTests: XCTestCase {
    override func tearDown() async throws {
        try await super.tearDown()
        HelperMaintenance.testDuplicateAppPathsOverride = nil
        HelperMaintenance.shared.applyTestHooks(nil)
        HelperManager.testHelperFunctionalityOverride = nil
        HelperManager.testInstallHelperOverride = nil
    }

    func testDetectDuplicateAppCopiesFiltersBuildPathsAndSortsApplicationsFirst() {
        HelperMaintenance.testDuplicateAppPathsOverride = {
            [
                "/Users/test/Downloads/KeyPath.app",
                "/dist/KeyPath.app",
                "/Applications/KeyPath.app",
                "/Users/test/KeyPath.app"
            ]
        }

        let copies = HelperMaintenance.shared.detectDuplicateAppCopies()
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

    func testRunCleanupLogsWarningForDuplicateCopies() async {
        HelperMaintenance.testDuplicateAppPathsOverride = {
            [
                "/Applications/KeyPath.app",
                "/Users/other/KeyPath.app"
            ]
        }

        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: { },
            bootoutHelperJob: { },
            removeLegacyHelperArtifacts: { _ in true },
            registerHelper: { true },
            runAppleScript: { _ in (false, "User cancelled") }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
        XCTAssertTrue(success)
        XCTAssertTrue(HelperMaintenance.shared.logLines.contains { $0.contains("Multiple KeyPath.app copies detected:") })
    }

    func testRunCleanupLogsFallbackFailureWhenAppleScriptDenied() async {
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }

        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: { },
            bootoutHelperJob: { },
            removeLegacyHelperArtifacts: { _ in false },
            registerHelper: { true },
            runAppleScript: { _ in (false, "User canceled") }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let success = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: true)
        XCTAssertFalse(success)
        XCTAssertTrue(HelperMaintenance.shared.logLines.contains { $0.contains("AppleScript cleanup failed") })
    }

    func testRunCleanupIsIdempotentWithoutDuplicates() async {
        HelperMaintenance.testDuplicateAppPathsOverride = { ["/Applications/KeyPath.app"] }
        let hooks = HelperMaintenance.TestHooks(
            unregisterHelper: { },
            bootoutHelperJob: { },
            removeLegacyHelperArtifacts: { _ in true },
            registerHelper: { true }
        )
        HelperMaintenance.shared.applyTestHooks(hooks)
        HelperManager.testHelperFunctionalityOverride = { true }

        let first = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
        XCTAssertTrue(first)
        let second = await HelperMaintenance.shared.runCleanupAndRepair(useAppleScriptFallback: false)
        XCTAssertTrue(second)
    }
}
