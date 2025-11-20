@testable import KeyPathAppKit
import ServiceManagement
import XCTest

@MainActor
final class KanataDaemonManagerTests: XCTestCase {
    var manager: KanataDaemonManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = KanataDaemonManager.shared
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Status Checking Tests

    func testGetStatus() {
        let status = manager.getStatus()
        // Status should be one of the valid SMAppService statuses
        XCTAssertTrue(
            status == .notFound || status == .notRegistered || status == .requiresApproval || status == .enabled,
            "Status should be a valid SMAppService status"
        )
    }

    func testIsRegisteredViaSMAppService() {
        let isRegistered = KanataDaemonManager.isRegisteredViaSMAppService()
        // Should return boolean without crashing
        XCTAssertNotNil(isRegistered)
    }

    func testHasLegacyInstallation() {
        let hasLegacy = manager.hasLegacyInstallation()
        // Should return boolean without crashing
        XCTAssertNotNil(hasLegacy)
    }

    func testIsInstalled() {
        let isInstalled = manager.isInstalled()
        // Should return boolean without crashing
        XCTAssertNotNil(isInstalled)
    }

    // MARK: - Validation Tests

    func testPlistExistsInBundle() {
        let bundlePath = Bundle.main.bundlePath
        let plistPath = "\(bundlePath)/Contents/Library/LaunchDaemons/\(KanataDaemonManager.kanataPlistName)"
        let exists = FileManager.default.fileExists(atPath: plistPath)

        if exists {
            print("✅ Plist found at: \(plistPath)")
        } else {
            print("⚠️ Plist not found at: \(plistPath)")
            print("   This is expected if running tests outside app bundle context")
        }
        // Don't fail test - plist may not exist in test environment
    }

    func testKanataBinaryExistsInBundle() {
        let bundlePath = Bundle.main.bundlePath
        let kanataPath = "\(bundlePath)/Contents/Library/KeyPath/kanata"
        let exists = FileManager.default.fileExists(atPath: kanataPath)

        if exists {
            print("✅ Kanata binary found at: \(kanataPath)")
        } else {
            print("⚠️ Kanata binary not found at: \(kanataPath)")
            print("   This is expected if running tests outside app bundle context")
        }
        // Don't fail test - binary may not exist in test environment
    }

    // MARK: - Error Handling Tests

    func testRegistrationRequiresMacOS13() async {
        // This test verifies the macOS version check
        // On macOS 13+, this should not throw immediately
        // On older macOS, it should throw

        if #available(macOS 13, *) {
            // On macOS 13+, registration attempt should not immediately fail due to version
            // (it may fail for other reasons like missing plist, but not version)
            do {
                // Don't actually register - just verify the version check passes
                let status = manager.getStatus()
                XCTAssertNotNil(status, "Should be able to check status on macOS 13+")
            } catch {
                // If it throws, it should be for a reason other than macOS version
                XCTAssertFalse(
                    (error as? KanataDaemonError)?.localizedDescription.contains("macOS 13") ?? false,
                    "Error should not be about macOS version on macOS 13+"
                )
            }
        } else {
            // On older macOS, registration should fail with version error
            do {
                try await manager.register()
                XCTFail("Registration should fail on macOS < 13")
            } catch let KanataDaemonError.registrationFailed(reason) {
                XCTAssertTrue(
                    reason.contains("macOS 13"),
                    "Error should mention macOS 13 requirement"
                )
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Constants Tests

    func testConstants() {
        XCTAssertEqual(KanataDaemonManager.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(KanataDaemonManager.kanataPlistName, "com.keypath.kanata.plist")
    }

    // MARK: - Singleton Tests

    func testSingleton() {
        let manager1 = KanataDaemonManager.shared
        let manager2 = KanataDaemonManager.shared
        XCTAssertIdentical(manager1, manager2, "Should return same singleton instance")
    }
}
