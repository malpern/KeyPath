import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class RawConfigurationRecoveryTests: KeyPathTestCase {
    private var directory: URL!
    private var service: ConfigurationService!
    private var coordinator: SaveCoordinator!
    private let original = ";; handwritten comment\n(defcfg)\n(defsrc a)\n(deflayer base b)\n"
    private let proposed = "(defcfg)\n(defsrc a)\n(deflayer base c)\n"
    private var config: URL {
        directory.appendingPathComponent("keypath.kbd")
    }

    private var journal: URL {
        RecoverableRuleWrite.journalURL(directory, scope: .rawConfig)
    }

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try original.write(to: config, atomically: true, encoding: .utf8)
        service = ConfigurationService(configDirectory: directory.path,
                                       ruleCollectionStore: .testStore(at: directory.appendingPathComponent("RuleCollections.json")),
                                       customRulesStore: .testStore(at: directory.appendingPathComponent("CustomRules.json")))
        coordinator = SaveCoordinator(configurationService: service)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
        coordinator = nil
        service = nil
        directory = nil
        try await super.tearDown()
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: "injected \(disposition)", protocol: nil, disposition: disposition)
    }

    private func interruptRawWrite() async throws {
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await self.service.stageRawConfiguration(content: self.proposed, expectedContent: self.original, mutationPermit: permit)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    }

    func testInterruptedRawWriteRecoversBeforeCancelledTransform() async throws {
        try await interruptRawWrite()
        var reloads = 0
        let result = await coordinator.editConfiguration(transform: { content in
            XCTAssertEqual(reloads, 1)
            XCTAssertEqual(content, self.original)
            throw CancellationError()
        }) {
            reloads += 1
            XCTAssertEqual(try? String(contentsOf: self.config, encoding: .utf8), self.original)
            return Self.reload(.applied)
        }
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.error is CancellationError)
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testInterruptedRawWriteRecoversBeforeAppMutation() async throws {
        try await interruptRawWrite()
        var reloads = 0
        let result = await coordinator.saveAppKeymaps(store: AppKeymapStore(fileURL: directory.appendingPathComponent("AppKeymaps.json")), mutate: { _ in
            XCTAssertEqual(reloads, 1)
            throw CancellationError()
        }) {
            reloads += 1
            XCTAssertEqual(try? String(contentsOf: self.config, encoding: .utf8), self.original)
            return Self.reload(.pending)
        }
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.error is CancellationError)
        XCTAssertEqual(reloads, 1)
    }

    func testFreshServiceRecoversInterruptedRawWriteBeforeEditing() async throws {
        try await interruptRawWrite()
        let fresh = ConfigurationService(configDirectory: directory.path,
                                         ruleCollectionStore: .testStore(at: directory.appendingPathComponent("RuleCollections.json")),
                                         customRulesStore: .testStore(at: directory.appendingPathComponent("CustomRules.json")))
        var reloads = 0
        let result = await SaveCoordinator(configurationService: fresh).editConfiguration(transform: { content in
            XCTAssertEqual(content, self.original)
            throw CancellationError()
        }) {
            reloads += 1
            return Self.reload(.applied)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testChangedOriginalIsPreservedBeforeRawStage() async throws {
        let external = ";; external edit during preparation"
        try external.write(to: config, atomically: true, encoding: .utf8)
        do {
            try await service.operationGate.withOperation { @MainActor permit in
                _ = try await self.service.stageRawConfiguration(content: self.proposed, expectedContent: self.original, mutationPermit: permit)
            }
            XCTFail("Stale original must be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("changed outside this operation"))
        }
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), external)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testStartupBackupCapturesRecoveredOriginal() async throws {
        try await interruptRawWrite()
        await coordinator.ensureBackupExists()
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        try proposed.write(to: config, atomically: true, encoding: .utf8)
        _ = try await coordinator.restoreLastGoodConfig()
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
    }

    func testExplicitRestoreResolvesPendingRawJournalBeforeWritingBackup() async throws {
        let backup = "(defcfg)\n(defsrc a)\n(deflayer base z)\n"
        coordinator.backupCurrentConfig(backup)
        try await interruptRawWrite()
        _ = try await coordinator.restoreLastGoodConfig()
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        var reloads = 0
        let next = await coordinator.editConfiguration(transform: { _ in throw CancellationError() }) {
            reloads += 1
            XCTAssertEqual(try? String(contentsOf: self.config, encoding: .utf8), backup)
            return Self.reload(.applied)
        }
        XCTAssertFalse(next.success)
        XCTAssertEqual(reloads, 1)
    }

    func testExplicitRestorePreservesUnreadablePendingJournal() async throws {
        try await interruptRawWrite()
        let corrupt = Data("invalid journal".utf8)
        try corrupt.write(to: journal)
        coordinator.backupCurrentConfig(original)
        do {
            _ = try await coordinator.restoreLastGoodConfig()
            XCTFail("Explicit restore must not bypass a corrupt pending journal")
        } catch {}
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), proposed)
        XCTAssertEqual(try Data(contentsOf: journal), corrupt)
    }

    func testExternalEditDuringRejectedReloadIsPreservedWithJournal() async throws {
        let external = ";; newer external revision"
        let result = await coordinator.saveGeneratedConfig(content: proposed) {
            do { try external.write(to: self.config, atomically: true, encoding: .utf8) }
            catch { XCTFail("\(error)") }
            return Self.reload(.rejected)
        }
        XCTAssertFalse(result.success)
        guard case .rawConfigRecoveryFailed = result.recoveryResult else { return XCTFail("Expected preserved recovery conflict") }
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), external)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    }

    func testFailedRecoveryIsRetriedBeforeAnotherRawTransform() async throws {
        var reloads = 0
        let result = await coordinator.saveGeneratedConfig(content: proposed) {
            reloads += 1
            return Self.reload(.rejected)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 2)
        guard case .rawConfigRecoveryFailed = result.recoveryResult else { return XCTFail("Recovery rejection must be explicit") }
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        let nextOwner = SaveCoordinator(configurationService: service)
        let next = await nextOwner.editConfiguration(transform: { _ in
            XCTAssertEqual(reloads, 3)
            throw CancellationError()
        }) {
            reloads += 1
            return Self.reload(.applied)
        }
        XCTAssertFalse(next.success)
        XCTAssertTrue(next.error is CancellationError)
        XCTAssertEqual(reloads, 3)
    }

    func testValidatedReplacementCanRepairRejectedEmptyOriginal() async throws {
        try "".write(to: config, atomically: true, encoding: .utf8)
        let failed = await coordinator.saveGeneratedConfig(content: proposed) { Self.reload(.rejected) }
        XCTAssertFalse(failed.success)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "")
        let cancelled = await coordinator.editConfiguration(transform: { _ in throw CancellationError() }) { Self.reload(.rejected) }
        XCTAssertFalse(cancelled.success)
        XCTAssertFalse(cancelled.error is CancellationError, "Unresolved recovery must remain visible")
        let invalid = await coordinator.saveGeneratedConfig(content: "") { Self.reload(.rejected) }
        XCTAssertFalse(invalid.success)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "")
        let corrected = await coordinator.editConfiguration(transform: { current in
            XCTAssertEqual(current, "")
            return self.proposed
        }) {
            let current = try? String(contentsOf: self.config, encoding: .utf8)
            return Self.reload(current == self.proposed ? .applied : .rejected)
        }
        XCTAssertTrue(corrected.success)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), proposed)
        let next = await coordinator.editConfiguration(transform: { _ in throw CancellationError() }) {
            XCTFail("Accepted replacement must clear previous recovery")
            return Self.reload(.rejected)
        }
        XCTAssertTrue(next.error is CancellationError)
    }

    func testRawWriteDoesNotTouchSidecarFilesAndRefreshesCommittedCache() async throws {
        let sidecar = directory.appendingPathComponent("RuleCollections.json")
        let marker = Data("external source bytes".utf8)
        try marker.write(to: sidecar)
        _ = await service.current()
        let result = await coordinator.saveGeneratedConfig(content: proposed) { Self.reload(.pending) }
        XCTAssertTrue(result.success)
        XCTAssertEqual(try Data(contentsOf: sidecar), marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        let current = await service.current()
        XCTAssertEqual(current.content, proposed)
    }

    func testRejectedRawSaveRunsRecoveryWithoutCallerCancellation() async throws {
        var reloads = 0
        let owner = try XCTUnwrap(coordinator)
        let task = Task { @MainActor in
            await owner.saveGeneratedConfig(content: self.proposed) {
                reloads += 1
                if reloads == 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return Self.reload(.rejected)
                }
                XCTAssertFalse(Task.isCancelled)
                XCTAssertEqual(try? String(contentsOf: self.config, encoding: .utf8), self.original)
                return Self.reload(.applied)
            }
        }
        let result = await task.value
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 2)
        guard case let .restoredPreviousRawConfig(reload) = result.recoveryResult else { return XCTFail("Expected verified recovery") }
        XCTAssertEqual(reload?.disposition, .applied)
    }
}
