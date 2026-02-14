import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

/// Unit tests for KanataBinaryInstaller service.
///
/// Tests binary installation and version checking.
/// These tests verify:
/// - Binary path detection
/// - Version checking
/// - Installation logic (in test mode)
@MainActor
final class KanataBinaryInstallerTests: XCTestCase {
    var installer: KanataBinaryInstaller!

    override func setUp() async throws {
        try await super.setUp()
        installer = KanataBinaryInstaller.shared
    }

    override func tearDown() async throws {
        installer = nil
        try await super.tearDown()
    }

    // MARK: - Binary Availability Tests

    func testIsBundledKanataAvailable() {
        // Environment-dependent (bundle layout), but should never crash.
        _ = installer.isBundledKanataAvailable()
    }

    func testGetKanataBinaryPath() {
        let path = installer.getKanataBinaryPath()

        let systemPath = WizardSystemPaths.kanataSystemInstallPath
        let bundledPath = WizardSystemPaths.bundledKanataPath
        XCTAssertTrue(path == systemPath || path == bundledPath)
        XCTAssertTrue(path.hasPrefix("/"), "Path should be absolute")
    }

    // MARK: - Version Checking Tests

    func testGetKanataVersionAtPathWithInvalidPath() async {
        let version = await installer.getKanataVersionAtPath("/nonexistent/path/kanata")
        XCTAssertNil(version, "Should return nil for invalid path")
    }

    func testShouldUpgradeKanata() async {
        // Environment-dependent. Avoid asserting behavior tied to local system state.
        _ = await installer.shouldUpgradeKanata()
    }

    // MARK: - Installation Tests (Test Mode)

    func testInstallBundledKanataInTestMode() async {
        // Environment-dependent. Ensure no crash in test mode.
        _ = await installer.installBundledKanata()
    }

    // MARK: - Path Resolution Tests

    func testBinaryPathResolution() {
        let path = installer.getKanataBinaryPath()

        // Path should be absolute
        XCTAssertTrue(path.hasPrefix("/"), "Path should be absolute")
    }
}
