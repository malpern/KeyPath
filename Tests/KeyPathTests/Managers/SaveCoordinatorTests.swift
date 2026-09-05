import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
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

    // MARK: - Save Isolation

    func testOverlappingGeneratedSavesWaitForPreviousReloadAndRollback() async throws {
        try await assertQueuedSave()
    }

    func testMappingSaveWaitsForGeneratedSaveRecovery() async throws {
        try await assertQueuedSave(mappingSecond: true)
    }

    func testCancelledQueuedSaveDoesNotWriteReloadOrBlockLaterSaves() async throws {
        try await assertQueuedSave(cancelSecond: true)
    }

    private func assertQueuedSave(mappingSecond: Bool = false, cancelSecond: Bool = false) async throws {
        let original = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let firstContent = "(defcfg)\n(defsrc a)\n(deflayer base c)"
        let secondContent = "(defcfg)\n(defsrc a)\n(deflayer base d)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        let firstReloadStarted = expectation(description: "first reload suspended")
        let secondStarted = expectation(description: "second save requested")
        let recorder = SaveStatusRecorder()
        coordinator.delegate = recorder
        var releaseFirst: CheckedContinuation<Void, Never>?
        let coordinator = try XCTUnwrap(coordinator)

        let first = Task { @MainActor in
            await coordinator.saveGeneratedConfig(content: firstContent) {
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                    firstReloadStarted.fulfill()
                }
                return ReloadResult(success: false, response: nil, errorMessage: "rejected", protocol: nil, disposition: .rejected)
            }
        }
        await fulfillment(of: [firstReloadStarted], timeout: 5)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json")),
            configurationService: configService
        )
        var secondReloadCount = 0
        let second = Task { @MainActor in
            secondStarted.fulfill()
            let reload = {
                secondReloadCount += 1
                return ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
            }
            if mappingSecond {
                return await coordinator.saveMapping(input: "a", output: "d", ruleCollectionsManager: manager, reloadHandler: reload)
            }
            return await coordinator.saveGeneratedConfig(content: secondContent, reloadHandler: reload)
        }
        await fulfillment(of: [secondStarted], timeout: 5)
        XCTAssertEqual(recorder.savingCount, 1, "Queued saves must not begin validation, backup, or status updates")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), firstContent)
        if cancelSecond { second.cancel() }
        releaseFirst?.resume()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertFalse(firstResult.success)
        if cancelSecond {
            XCTAssertFalse(secondResult.success)
            XCTAssertTrue(secondResult.error is CancellationError)
            XCTAssertNil(secondResult.reloadResult)
            XCTAssertEqual(secondReloadCount, 0)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
            let nextResult = await coordinator.saveGeneratedConfig(content: secondContent) {
                ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
            }
            XCTAssertTrue(nextResult.success, "Cancellation must release the operation slot")
        } else {
            XCTAssertTrue(secondResult.success)
            XCTAssertEqual(secondReloadCount, 1)
        }
        if mappingSecond {
            let savedRule = try XCTUnwrap(manager.customRules.first { $0.input == "a" })
            XCTAssertEqual(savedRule.action, .keystroke(key: "d"))
            XCTAssertNotEqual(try String(contentsOf: url, encoding: .utf8), original)
        } else {
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), secondContent)
        }
        // The second save must have backed up the restored original, not the
        // uncommitted first edit. Exercise that backup through the public API.
        try await coordinator.restoreLastGoodConfig()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
    }

    func testRejectedSaveRestoresLatestFileRatherThanStaleParsedCache() async throws {
        let original = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let accepted = "(defcfg)\n(defsrc a)\n(deflayer base c)"
        let rejected = "(defcfg)\n(defsrc a)\n(deflayer base d)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        _ = await configService.current() // Deliberately prime the older parsed cache.
        let first = await coordinator.saveGeneratedConfig(content: accepted) {
            ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
        }
        XCTAssertTrue(first.success)
        let second = await coordinator.saveGeneratedConfig(content: rejected) {
            // A separate backup request must not replace this save's snapshot.
            self.coordinator.backupCurrentConfig("unrelated backup")
            return ReloadResult(success: false, response: nil, errorMessage: "rejected", protocol: nil, disposition: .rejected)
        }
        XCTAssertFalse(second.success)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), accepted)
    }

    func testReentrantReloadSaveAndRestoreFailWithoutBlockingOuterSave() async throws {
        let original = "(defcfg)\n(defsrc a)\n(deflayer base b)"
        let updated = "(defcfg)\n(defsrc a)\n(deflayer base c)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        let coordinator = try XCTUnwrap(coordinator)
        let outer = await coordinator.saveGeneratedConfig(content: updated) {
            let nested = await coordinator.saveGeneratedConfig(content: original) {
                XCTFail("Recursive save must not reach reload")
                return ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
            }
            XCTAssertFalse(nested.success)
            XCTAssertNil(nested.reloadResult)
            XCTAssertTrue(nested.error?.localizedDescription.contains("recursively") == true)
            do {
                try await coordinator.restoreLastGoodConfig()
                XCTFail("Recursive restoration must fail rather than queue behind itself")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("recursively"))
            }
            return ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
        }
        XCTAssertTrue(outer.success)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), updated)
        try await coordinator.restoreLastGoodConfig()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
    }

    func testMissingConfigInitializesBackupBeforeGeneratedSave() async throws {
        let updated = "(defcfg)\n(defsrc a)\n(deflayer base c)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        var initializedContent: String?
        let result = await coordinator.saveGeneratedConfig(content: updated) {
            initializedContent = await self.configService.current().content
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), updated)
            return ReloadResult(success: false, response: nil, errorMessage: "rejected", protocol: nil, disposition: .rejected)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.reloadResult?.disposition, .rejected)
        let backup = try XCTUnwrap(initializedContent)
        XCTAssertFalse(backup.isEmpty)
        XCTAssertNotEqual(backup, updated)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), backup)
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

@MainActor
private final class SaveStatusRecorder: SaveCoordinatorDelegate {
    var savingCount = 0

    func saveStatusDidChange(_ status: SaveStatus) {
        if case .saving = status { savingCount += 1 }
    }

    func configDidUpdate(mappings _: [KeyMapping]) {}
}
