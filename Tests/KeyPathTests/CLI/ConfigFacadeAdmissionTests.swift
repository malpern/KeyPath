import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class ConfigFacadeAdmissionTests: KeyPathTestCase {
    func testApplyLoadsSourcesOnlyAfterThePreviousWriterFinishes() async throws {
        try await withDirectory { directory in
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            let store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
            let entered = self.expectation(description: "writer admitted")
            let prematureLoad = self.expectation(description: "sources must wait")
            prematureLoad.isInverted = true
            let phase = Phase()
            var resume: CheckedContinuation<Void, Never>?
            let first = Task { @MainActor in
                try await gate.withOperation { @MainActor _ in
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                    try await store.saveRules([CustomRule(input: "f13", action: .keystroke(key: "f14"))])
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let facade = ConfigFacade(
                configDirectory: directory.path,
                ruleCollectionLoader: { [] },
                customRuleLoader: { @MainActor in
                    if phase.isWaiting { prematureLoad.fulfill() }
                    return await store.loadRules()
                },
                reloadHandler: { true }
            )
            let apply = Task { try await facade.applyConfiguration(dryRun: true) }
            await self.fulfillment(of: [prematureLoad], timeout: 0.15)
            phase.isWaiting = false
            resume?.resume()
            try await first.value
            let result = try await apply.value
            XCTAssertEqual(result.customRulesCount, 1, "Read the newly committed source, not a pre-admission snapshot")
        }
    }

    func testReloadCallbackCannotApplyBackUpOrRestoreThroughAnotherFacade() async throws {
        try await withDirectory { directory in
            let backup = directory.deletingLastPathComponent().appendingPathComponent("backup")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            try "must not replace generated config".write(to: backup.appendingPathComponent("keypath.kbd"), atomically: true, encoding: .utf8)
            let output = directory.deletingLastPathComponent().appendingPathComponent("forbidden-backup")
            let nested = ConfigFacade(configDirectory: directory.path)
            let facade = ConfigFacade(
                configDirectory: directory.path,
                ruleCollectionLoader: { [] },
                customRuleLoader: { [] },
                reloadHandler: {
                    do {
                        _ = try await nested.applyConfiguration(dryRun: true)
                        XCTFail("Callback apply must be rejected")
                    } catch ConfigurationOperationGate.Failure.recursiveOperation {} catch { XCTFail("Unexpected error: \(error)") }
                    do {
                        _ = try await nested.backupConfig(outputPath: output.path)
                        XCTFail("Callback backup must be rejected")
                    } catch ConfigurationOperationGate.Failure.recursiveOperation {} catch { XCTFail("Unexpected error: \(error)") }
                    do {
                        _ = try await nested.restoreConfig(from: backup.path, reload: false)
                        XCTFail("Callback restore must be rejected")
                    } catch ConfigurationOperationGate.Failure.recursiveOperation {} catch { XCTFail("Unexpected error: \(error)") }
                    return true
                }
            )
            let result = try await facade.applyConfiguration()
            XCTAssertTrue(result.reloadSuccess)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            let content = try String(contentsOf: directory.appendingPathComponent("keypath.kbd"), encoding: .utf8)
            XCTAssertFalse(content.contains("must not replace"))
        }
    }

    func testBackupWaitsForAdmittedWriterAndCopiesItsCompletedRevision() async throws {
        try await withDirectory { directory in
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            let output = directory.deletingLastPathComponent().appendingPathComponent("backup")
            let entered = self.expectation(description: "writer admitted")
            let prematureBackup = self.expectation(description: "backup must wait")
            prematureBackup.isInverted = true
            let phase = Phase()
            var resume: CheckedContinuation<Void, Never>?
            let first = Task { @MainActor in
                try await gate.withOperation { @MainActor _ in
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                    try "completed".write(to: directory.appendingPathComponent("keypath.kbd"), atomically: true, encoding: .utf8)
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let backup = Task { @MainActor in
                let result = try await ConfigFacade(configDirectory: directory.path).backupConfig(outputPath: output.path)
                if phase.isWaiting { prematureBackup.fulfill() }
                return result
            }
            await self.fulfillment(of: [prematureBackup], timeout: 0.15)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            phase.isWaiting = false
            resume?.resume()
            try await first.value
            _ = try await backup.value
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("keypath.kbd"), encoding: .utf8), "completed")
        }
    }

    func testDefaultLoadersReadTheRequestedConfigurationDirectory() async throws {
        try await withDirectory { directory in
            let store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
            try await store.saveRules([CustomRule(input: "f13", action: .keystroke(key: "f14"))])
            let result = try await ConfigFacade(configDirectory: directory.path).applyConfiguration(dryRun: true)
            XCTAssertEqual(result.customRulesCount, 1)
            XCTAssertEqual(result.changeset?.customRules, ["f13 → f14"])
        }
    }

    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cli-admission-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "original".write(to: directory.appendingPathComponent("keypath.kbd"), atomically: true, encoding: .utf8)
        try await body(directory)
    }

    private final class Phase {
        var isWaiting = true
    }
}
