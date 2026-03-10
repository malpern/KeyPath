import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class SaveCoordinatorTests: XCTestCase {
    private var tempDir: URL!
    private var configService: ConfigurationService!
    private var coordinator: SaveCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SaveCoordinatorTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        configService = ConfigurationService(configDirectory: tempDir.path)
        let engine = TCPEngineClient()
        coordinator = SaveCoordinator(
            configurationService: configService,
            engineClient: engine,
            configFileWatcher: nil
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        coordinator = nil
        configService = nil
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - Rollback Fallback Tests

    func testRestoreLastGoodConfig_WritesMinimalSafeConfig_WhenNoBackupExists() async throws {
        // No backup has been set (lastGoodConfig is nil).
        // restoreLastGoodConfig should fall back to writing a minimal safe config.
        XCTAssertFalse(coordinator.hasBackup(), "Should have no backup initially")

        try await coordinator.restoreLastGoodConfig()

        // Verify the safe config was written
        let configPath = configService.configurationPath
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath),
            "Safe config file should exist after rollback fallback"
        )

        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertTrue(content.contains("(defcfg"), "Safe config should contain defcfg")
        XCTAssertTrue(content.contains("(defsrc)"), "Safe config should contain defsrc")
        XCTAssertTrue(content.contains("(deflayer base)"), "Safe config should contain deflayer")
    }

    func testRestoreLastGoodConfig_RestoresBackup_WhenBackupExists() async throws {
        let backupContent = "(defcfg)\n(defsrc caps)\n(deflayer base esc)"
        coordinator.backupCurrentConfig(backupContent)

        XCTAssertTrue(coordinator.hasBackup(), "Should have backup after setting one")

        try await coordinator.restoreLastGoodConfig()

        let configPath = configService.configurationPath
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertEqual(content, backupContent, "Should restore the backup content")
    }

    func testEnsureBackupExists_LoadsCurrentConfig() async throws {
        // Write a config to disk first
        let existingConfig = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let configPath = configService.configurationPath
        try existingConfig.write(
            to: URL(fileURLWithPath: configPath),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertFalse(coordinator.hasBackup(), "Should have no backup initially")

        await coordinator.ensureBackupExists()

        XCTAssertTrue(coordinator.hasBackup(), "Should have backup after ensureBackupExists")
    }
}
