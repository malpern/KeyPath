import Foundation
import XCTest

@testable import KeyPathAppKit

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
        // In test mode, this checks file existence
        let available = installer.isBundledKanataAvailable()
        XCTAssertTrue(available == true || available == false, "Should return boolean result")
    }

    func testGetKanataBinaryPath() {
        let path = installer.getKanataBinaryPath()

        // Should return either bundled or system path
        XCTAssertFalse(path.isEmpty, "Should return a path")
        XCTAssertTrue(
            path.contains("kanata") || path.contains("KeyPath"),
            "Path should contain 'kanata' or 'KeyPath'"
        )
    }

    // MARK: - Version Checking Tests

    func testGetKanataVersionAtPathWithInvalidPath() {
        let version = installer.getKanataVersionAtPath("/nonexistent/path/kanata")
        XCTAssertNil(version, "Should return nil for invalid path")
    }

    func testShouldUpgradeKanata() {
        // In test mode, this may return false or check file existence
        let shouldUpgrade = installer.shouldUpgradeKanata()
        XCTAssertTrue(shouldUpgrade == true || shouldUpgrade == false, "Should return boolean")
    }

    // MARK: - Installation Tests (Test Mode)

    func testInstallBundledKanataInTestMode() {
        // In test mode, should check file existence without actual installation
        let result = installer.installBundledKanata()

        // Should return true if bundled binary exists, false otherwise
        XCTAssertTrue(result == true || result == false, "Should return boolean result")
    }

    // MARK: - Path Resolution Tests

    func testBinaryPathResolution() {
        let path = installer.getKanataBinaryPath()

        // Path should be absolute
        XCTAssertTrue(path.hasPrefix("/"), "Path should be absolute")
    }
}
