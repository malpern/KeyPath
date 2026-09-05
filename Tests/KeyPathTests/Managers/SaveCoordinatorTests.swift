import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class SaveCoordinatorTests: KeyPathTestCase {
    private var tempDir: URL!
    private var configService: ConfigurationService!
    private var coordinator: SaveCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SaveCoordinatorTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        configService = ConfigurationService(
            configDirectory: tempDir.path,
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json"))
        )
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

    // MARK: - Save Result Contract

    func testGeneratedSavePreservesAppliedResult() async throws {
        try await assertGeneratedSave(disposition: .applied)
    }

    func testGeneratedSavePreservesPendingResultWithoutRollingBack() async throws {
        try await assertGeneratedSave(disposition: .pending)
    }

    func testGeneratedSavePreservesRejectionAndRestoresPreviousFile() async throws {
        try await assertGeneratedSave(disposition: .rejected)
    }

    func testGeneratedSavePreservesFailureAndRestoresPreviousFile() async throws {
        try await assertGeneratedSave(disposition: .failed)
    }

    func testMappingSavePreservesAppliedResult() async throws {
        try await assertMappingSave(disposition: .applied)
    }

    func testMappingSavePreservesPendingResult() async throws {
        try await assertMappingSave(disposition: .pending)
    }

    func testMappingSavePreservesRejectedResult() async throws {
        try await assertMappingSave(disposition: .rejected)
    }

    func testMappingSavePreservesFailedResult() async throws {
        try await assertMappingSave(disposition: .failed)
    }

    private func assertMappingSave(
        disposition: ReloadDisposition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let original = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json")),
            configurationService: configService
        )
        var reloadCount = 0
        let result = await coordinator.saveMapping(input: "a", output: "c", ruleCollectionsManager: manager) {
            reloadCount += 1
            return ReloadResult(
                success: disposition == .applied,
                response: nil,
                errorMessage: disposition == .applied ? nil : "injected \(disposition)",
                protocol: nil,
                disposition: disposition
            )
        }
        XCTAssertEqual(result.reloadResult?.disposition, disposition, file: file, line: line)
        XCTAssertEqual(reloadCount, 1, file: file, line: line)
        let saved = disposition == .applied || disposition == .pending
        XCTAssertEqual(result.success, saved, file: file, line: line)
        let content = try String(contentsOf: url, encoding: .utf8)
        if saved {
            XCTAssertNotEqual(content, original, file: file, line: line)
        } else {
            XCTAssertEqual(content, original, file: file, line: line)
        }
    }

    func testInvalidGeneratedSaveHasNoReloadResultAndLeavesFileUntouched() async throws {
        let original = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        var reloadCount = 0

        let result = await coordinator.saveGeneratedConfig(content: "") {
            reloadCount += 1
            return ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
        }

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertNil(result.reloadResult)
        XCTAssertEqual(reloadCount, 0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
    }

    private func assertGeneratedSave(
        disposition: ReloadDisposition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let original = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let updated = "(defcfg)\n(defsrc a)\n(deflayer base c)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        let expected = ReloadResult(
            success: disposition == .applied,
            response: disposition == .applied ? "ok" : nil,
            errorMessage: disposition == .applied ? nil : "injected \(disposition)",
            protocol: nil,
            disposition: disposition
        )
        var reloadCount = 0

        let result = await coordinator.saveGeneratedConfig(content: updated) {
            reloadCount += 1
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), updated, file: file, line: line)
            return expected
        }

        let saved = disposition == .applied || disposition == .pending
        XCTAssertEqual(result.success, saved, file: file, line: line)
        XCTAssertEqual(result.error == nil, saved, file: file, line: line)
        XCTAssertEqual(result.reloadResult?.disposition, disposition, file: file, line: line)
        XCTAssertEqual(result.reloadResult?.success, expected.success, file: file, line: line)
        XCTAssertEqual(result.reloadResult?.response, expected.response, file: file, line: line)
        XCTAssertEqual(result.reloadResult?.errorMessage, expected.errorMessage, file: file, line: line)
        XCTAssertEqual(reloadCount, 1, file: file, line: line)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), saved ? updated : original, file: file, line: line)
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
