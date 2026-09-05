import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CLIConfigurationOperationTests: KeyPathTestCase {
    func testCommandComposesSourceEditsAndPreviewUnderOneOwner() async throws {
        try await withDirectory { directory in
            try await CLIConfigurationOperation.run(configDirectory: directory.path) { operation in
                _ = try await operation.rules.addSimpleRemap(input: "f13", output: "f14")
                _ = try await operation.rules.addSimpleRemap(input: "f15", output: "f16")
                _ = try await operation.collections.createCollection(name: "Command test", category: "custom", summary: nil)
                let result = try await operation.config.applyConfiguration(dryRun: true)
                XCTAssertEqual(result.customRulesCount, 2)
                let collections = await operation.collections.loadRuleCollections()
                XCTAssertTrue(collections.contains { $0.name == "Command test" })
            }
            let stored = await CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json")).loadRules()
            XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f15"])
        }
    }

    func testEscapedCommandCannotWriteOrApplyAfterOwnershipEnds() async throws {
        try await withDirectory { directory in
            let escaped = try await CLIConfigurationOperation.run(configDirectory: directory.path) { $0 }
            do {
                _ = try await escaped.rules.addSimpleRemap(input: "f13", output: "f14")
                XCTFail("Expired command wrote rules")
            } catch ConfigurationOperationGate.Failure.invalidPermit {}
            do {
                _ = try await escaped.collections.createLayer(name: "expired")
                XCTFail("Expired command wrote collections")
            } catch ConfigurationOperationGate.Failure.invalidPermit {}
            do {
                _ = try await escaped.config.applyConfiguration(dryRun: true)
                XCTFail("Expired command applied")
            } catch ConfigurationOperationGate.Failure.invalidPermit {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("CustomRules.json").path))
        }
    }

    func testIndependentRuleWriterWaitsForWholeCommandAndPreservesBothEdits() async throws {
        try await withDirectory { directory in
            let entered = self.expectation(description: "command holds ownership")
            let prematureWrite = self.expectation(description: "independent write waits")
            prematureWrite.isInverted = true
            let phase = Phase()
            var resume: CheckedContinuation<Void, Never>?
            let command = Task { @MainActor in
                try await CLIConfigurationOperation.run(configDirectory: directory.path) { @MainActor operation in
                    _ = try await operation.rules.addSimpleRemap(input: "f13", output: "f14")
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                    _ = try await operation.rules.addSimpleRemap(input: "f15", output: "f16")
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let store = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
            let second = Task { @MainActor in
                _ = try await RulesFacade(store: store).addSimpleRemap(input: "f17", output: "f18")
                if phase.waiting { prematureWrite.fulfill() }
            }
            await self.fulfillment(of: [prematureWrite], timeout: 0.15)
            phase.waiting = false
            resume?.resume()
            try await command.value
            try await second.value
            let rules = await store.loadRules()
            XCTAssertEqual(Set(rules.map(\.input)), ["f13", "f15", "f17"])
        }
    }

    func testIndependentCollectionMutationsDoNotLoseConcurrentCreates() async throws {
        try await withDirectory { directory in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0 ..< 12 {
                    group.addTask {
                        let store = RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json"))
                        _ = try await CollectionsFacade(store: store).createCollection(
                            name: "Concurrent \(index)", category: "custom", summary: nil
                        )
                    }
                }
                try await group.waitForAll()
            }
            let store = RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json"))
            let collections = await store.loadCollections()
            XCTAssertEqual(Set(collections.map(\.name)).intersection(Set((0 ..< 12).map { "Concurrent \($0)" })).count, 12)
        }
    }

    func testUnreadableMetadataStopsPackCommandsBeforeSourceMutation() async throws {
        try await withDirectory { directory in
            let metadata = directory.appendingPathComponent("installed-packs.json")
            let malformed = Data("invalid metadata".utf8)
            try malformed.write(to: metadata)
            try await CLIConfigurationOperation.run(configDirectory: directory.path) { operation in
                do {
                    _ = try await operation.packs.installPack(nameOrId: "chord-groups")
                    XCTFail("Unreadable metadata must stop installation")
                } catch is DecodingError {}
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("CustomRules.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("RuleCollections.json").path))
            XCTAssertEqual(try Data(contentsOf: metadata), malformed)
        }
    }

    private final class Phase { var waiting = true }

    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cli-operation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
        }
        try await body(directory)
    }
}
