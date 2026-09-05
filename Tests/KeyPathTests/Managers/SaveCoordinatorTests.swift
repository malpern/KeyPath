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
        coordinator = SaveCoordinator(
            configurationService: configService,
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
            if reloadCount > 1 { return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil) }
            return ReloadResult(
                success: disposition == .applied,
                response: nil,
                errorMessage: disposition == .applied ? nil : "injected \(disposition)",
                protocol: nil,
                disposition: disposition
            )
        }
        XCTAssertEqual(result.reloadResult?.disposition, disposition, file: file, line: line)
        let saved = disposition == .applied || disposition == .pending
        XCTAssertEqual(result.success, saved, file: file, line: line)
        XCTAssertEqual(reloadCount, saved ? 1 : 2, file: file, line: line)
        if saved {
            guard case .notAttempted = result.recoveryResult else {
                return XCTFail("Successful saves must not claim recovery", file: file, line: line)
            }
        } else {
            guard case .restoredPreviousRuleState = result.recoveryResult else {
                return XCTFail("Rejected/failed reload must report restored file", file: file, line: line)
            }
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        if saved {
            XCTAssertNotEqual(content, original, file: file, line: line)
        } else {
            XCTAssertEqual(content, original, file: file, line: line)
            XCTAssertTrue(manager.customRules.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("CustomRules.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("RuleCollections.json").path))
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
        guard case .notAttempted = result.recoveryResult else {
            return XCTFail("Validation rejection must not attempt recovery")
        }
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
        if saved {
            guard case .notAttempted = result.recoveryResult else {
                return XCTFail("Successful saves must not claim recovery", file: file, line: line)
            }
        } else {
            guard case .restoredPreviousConfig = result.recoveryResult else {
                return XCTFail("Rejected/failed reload must report restored file", file: file, line: line)
            }
        }
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

    func testMappingCancellationRestoresSourcesAndRunsUncancelledRecovery() async throws {
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json")),
            configurationService: configService
        )
        manager.customRules = [manager.makeCustomRule(input: "a", output: "b")]
        try await configService.saveRuleState(ruleCollections: [], customRules: manager.customRules,
                                              collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        let before = try ruleFiles()
        let oldRules = manager.customRules
        var reloadCount = 0
        var operation: Task<KeyPathAppKit.SaveResult, Never>?
        operation = Task { @MainActor in
            await self.coordinator.saveMapping(input: "c", output: "d", ruleCollectionsManager: manager) {
                reloadCount += 1
                if reloadCount == 1 { operation?.cancel() }
                else {
                    XCTAssertFalse(Task.isCancelled, "Recovery must survive caller cancellation")
                    do {
                        let restored = try self.ruleFiles()
                        XCTAssertEqual(restored, before)
                    } catch { XCTFail("Recovery files unavailable: \(error)") }
                }
                return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
            }
        }
        let result = await operation!.value
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.error is CancellationError)
        XCTAssertEqual(reloadCount, 2)
        XCTAssertEqual(try ruleFiles(), before)
        XCTAssertEqual(manager.customRules.map(\.id), oldRules.map(\.id))
        guard case let .restoredPreviousRuleState(recovery) = result.recoveryResult else { return XCTFail("Missing complete recovery") }
        XCTAssertEqual(recovery?.disposition, .applied)
    }

    func testMappingExternalEditPreservesJournalAndDoesNotRegenerateSnapshot() async throws {
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json")),
            configurationService: configService
        )
        try await configService.saveRuleState(ruleCollections: [], customRules: [],
                                              collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        var reloads = 0
        var externalRevision: [String: Data]?
        let result = await coordinator.saveMapping(input: "a", output: "b", ruleCollectionsManager: manager) {
            reloads += 1
            do {
                try "external edit".write(toFile: self.configService.configurationPath, atomically: true, encoding: .utf8)
                externalRevision = try self.ruleFiles()
            } catch { XCTFail("Could not inject external edit: \(error)") }
            return ReloadResult(success: false, response: nil, errorMessage: "rejected", protocol: nil, disposition: .rejected)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 1, "Do not reload a conflicted revision as recovery")
        guard case .ruleStateRecoveryFailed = result.recoveryResult else { return XCTFail("Missing recovery conflict") }
        XCTAssertEqual(try ruleFiles(), externalRevision)
        XCTAssertTrue(manager.customRules.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(tempDir).path))
    }

    func testMappingRetainsExistingCollectionConflictChoiceBeforeSingleReload() async {
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json")),
            configurationService: configService
        )
        var first = RuleCollection(name: "First", summary: "First", category: .custom,
                                   mappings: [KeyMapping(input: "a", action: .keystroke(key: "b")),
                                              KeyMapping(input: "a", action: .keystroke(key: "b"))], isEnabled: true)
        first.configuration = .tapHoldPicker(TapHoldPickerConfig(inputKey: "a", tapOptions: [], holdOptions: [], selectedTapOutput: "b", selectedHoldOutput: "lctl"))
        var second = RuleCollection(name: "Second", summary: "Second", category: .custom, mappings: [], isEnabled: true)
        second.configuration = .tapHoldPicker(TapHoldPickerConfig(inputKey: "a", tapOptions: [], holdOptions: [], selectedTapOutput: "c", selectedHoldOutput: "lalt"))
        manager.ruleCollections = [first, second]
        var choices = 0
        manager.onMappingConflictResolution = { _ in
            choices += 1
            return second.id
        }
        var reloads = 0
        let result = await coordinator.saveMapping(input: "d", output: "e", ruleCollectionsManager: manager) {
            reloads += 1
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
        }
        XCTAssertTrue(result.success)
        XCTAssertEqual(choices, 1)
        XCTAssertEqual(manager.ruleCollections.first?.mappings.count, 1, "Keep the existing pre-save mapping deduplication")
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(manager.ruleCollections.first { $0.id == second.id }?.isEnabled, false)
        let stored = await manager.ruleCollectionStore.loadCollections()
        XCTAssertEqual(stored.first { $0.id == second.id }?.isEnabled, false)
    }

    private func ruleFiles() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json"].map {
            try ($0, Data(contentsOf: tempDir.appendingPathComponent($0)))
        })
    }

    // MARK: - Rollback Fallback Tests

    func testGeneratedSaveReportsMinimalFallbackWhenPreviousFileIsEmpty() async throws {
        try await assertRecoveryOutcome(mapping: false, blockWrites: false)
    }

    func testMappingSaveRestoresExactEmptyFileAndSources() async throws {
        try await assertRecoveryOutcome(mapping: true, blockWrites: false)
    }

    func testGeneratedSavePreservesBothRecoveryErrorsAndReleasesOperation() async throws {
        try await assertRecoveryOutcome(mapping: false, blockWrites: true)
    }

    func testMappingSaveReportsJournalRecoveryFailureAndReleasesOperation() async throws {
        try await assertRecoveryOutcome(mapping: true, blockWrites: true)
    }

    private func assertRecoveryOutcome(mapping: Bool, blockWrites: Bool) async throws {
        let original = blockWrites ? "(defcfg)\n(defsrc a)\n(deflayer base b)" : ""
        let updated = "(defcfg)\n(defsrc a)\n(deflayer base c)"
        let url = URL(fileURLWithPath: configService.configurationPath)
        try original.write(to: url, atomically: true, encoding: .utf8)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .testStore(at: tempDir.appendingPathComponent("RuleCollections.json")),
            customRulesStore: .testStore(at: tempDir.appendingPathComponent("CustomRules.json")),
            configurationService: configService
        )
        var reloadCount = 0
        let reload: () async -> ReloadResult = {
            reloadCount += 1
            if blockWrites {
                // Replace this test's directory with a regular file. Both recovery
                // writes must fail, without relying on permissions or real services.
                do {
                    try FileManager.default.removeItem(at: self.tempDir)
                    try "blocked".write(to: self.tempDir, atomically: true, encoding: .utf8)
                } catch {
                    XCTFail("Could not inject write failure: \(error)")
                }
            }
            return ReloadResult(success: false, response: nil, errorMessage: "injected rejection", protocol: nil, disposition: .rejected)
        }
        let result: KeyPathAppKit.SaveResult = if mapping {
            await coordinator.saveMapping(input: "a", output: "c", ruleCollectionsManager: manager, reloadHandler: reload)
        } else {
            await coordinator.saveGeneratedConfig(content: updated, reloadHandler: reload)
        }
        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.reloadResult?.errorMessage, "injected rejection")
        XCTAssertEqual(result.reloadResult?.disposition, .rejected)
        if mapping {
            if blockWrites {
                XCTAssertEqual(reloadCount, 1)
                guard case .ruleStateRecoveryFailed = result.recoveryResult else { return XCTFail("Missing journal recovery failure") }
                XCTAssertTrue(result.error?.localizedDescription.contains("Recovery needs attention") == true)
                XCTAssertEqual(try String(contentsOf: tempDir, encoding: .utf8), "blocked")
                try FileManager.default.removeItem(at: tempDir)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try original.write(to: url, atomically: true, encoding: .utf8)
                let next = await coordinator.saveGeneratedConfig(content: updated) {
                    ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
                }
                XCTAssertTrue(next.success)
            } else {
                XCTAssertEqual(reloadCount, 2)
                guard case let .restoredPreviousRuleState(recoveryReload) = result.recoveryResult else { return XCTFail("Missing exact rule revision recovery") }
                XCTAssertEqual(recoveryReload?.disposition, .rejected)
                XCTAssertTrue(result.error?.localizedDescription.contains("Recovery needs attention") == true)
                XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
                XCTAssertTrue(manager.customRules.isEmpty)
            }
            return
        }
        XCTAssertEqual(reloadCount, 1, "Recovery must not issue a second reload")
        if blockWrites {
            guard case let .failed(backupError, fallbackError) = result.recoveryResult else {
                return XCTFail("Both recovery failures must be returned")
            }
            XCTAssertNotNil(backupError)
            XCTAssertFalse(fallbackError.localizedDescription.isEmpty)
            XCTAssertEqual(try String(contentsOf: tempDir, encoding: .utf8), "blocked")
            try FileManager.default.removeItem(at: tempDir)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try original.write(to: url, atomically: true, encoding: .utf8)
            let next = await coordinator.saveGeneratedConfig(content: updated) {
                ReloadResult(success: true, response: "ok", errorMessage: nil, protocol: nil)
            }
            XCTAssertTrue(next.success, "Failed recovery must release the save operation")
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), updated)
        } else {
            guard case let .wroteMinimalSafeConfig(backupError) = result.recoveryResult else {
                return XCTFail("An empty prior file must report minimal fallback, not restoration")
            }
            XCTAssertNotNil(backupError)
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(content.contains("(deflayer base)"))
            XCTAssertNotEqual(content, original)
            XCTAssertNotEqual(content, updated)
        }
    }

    func testExplicitRestorePreservesBothFailuresWhenFallbackCannotBeWritten() async throws {
        coordinator.backupCurrentConfig("(defcfg)\n(defsrc a)\n(deflayer base b)")
        try await assertExplicitRestoreFailure(hasBackup: true)
    }

    func testExplicitRestorePreservesMissingBackupWhenFallbackCannotBeWritten() async throws {
        try await assertExplicitRestoreFailure(hasBackup: false)
    }

    private func assertExplicitRestoreFailure(hasBackup: Bool) async throws {
        try FileManager.default.removeItem(at: tempDir)
        try "blocked".write(to: tempDir, atomically: true, encoding: .utf8)
        do {
            try await coordinator.restoreLastGoodConfig()
            XCTFail("Explicit restore must continue to throw on total recovery failure")
        } catch {
            let recoveryError = try XCTUnwrap(error as? SaveRecoveryError)
            XCTAssertEqual(recoveryError.backupError != nil, hasBackup)
            XCTAssertFalse(recoveryError.fallbackError.localizedDescription.isEmpty)
            XCTAssertEqual(recoveryError.localizedDescription, recoveryError.fallbackError.localizedDescription)
        }
    }

    func testRestoreLastGoodConfig_WritesMinimalSafeConfig_WhenNoBackupExists() async throws {
        // No backup has been set (lastGoodConfig is nil).
        // restoreLastGoodConfig should fall back to writing a minimal safe config.
        XCTAssertFalse(coordinator.hasBackup(), "Should have no backup initially")

        let recovery = try await coordinator.restoreLastGoodConfig()
        guard case let .wroteMinimalSafeConfig(backupError) = recovery else {
            return XCTFail("No backup must report minimal config fallback")
        }
        XCTAssertNil(backupError, "A missing backup is distinct from a failed backup write")

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
