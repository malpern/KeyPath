import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class SharedConfigurationAdmissionTests: KeyPathTestCase {
    func testCollectionEditWaitsBeforeMutatingDuringGeneratedSaveRollback() async throws {
        try await withFixture { service, manager, coordinator in
            let entered = self.expectation(description: "first reload entered")
            let started = self.expectation(description: "collection edit requested")
            var resume: CheckedContinuation<Void, Never>?
            let first = Task { @MainActor in
                await coordinator.saveGeneratedConfig(content: "(defcfg)\n(defsrc a)\n(deflayer base b)") {
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                    return ReloadResult(success: false, response: nil, errorMessage: "reject", protocol: nil, disposition: .rejected)
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let rule = manager.makeCustomRule(input: "a", output: "c")
            let second = Task { @MainActor in
                started.fulfill()
                return await manager.saveCustomRule(rule)
            }
            await self.fulfillment(of: [started], timeout: 5)
            XCTAssertTrue(manager.customRules.isEmpty, "Queued edits must not stage state before admission")
            resume?.resume()
            let firstResult = await first.value
            let secondResult = await second.value
            XCTAssertFalse(firstResult.success)
            XCTAssertTrue(secondResult)
            XCTAssertEqual(manager.customRules.map(\.id), [rule.id])
            let stored = await manager.customRulesStore.loadRules()
            XCTAssertEqual(stored.map(\.id), [rule.id])
            let committed = await service.current()
            XCTAssertEqual(try String(contentsOfFile: service.configurationPath, encoding: .utf8), committed.content)
        }
    }

    func testReloadCallbackCannotReenterCollectionMutation() async throws {
        try await withFixture { _, manager, coordinator in
            var errors: [String] = []
            manager.onError = { errors.append($0) }
            let result = await coordinator.saveGeneratedConfig(content: "(defcfg)\n(defsrc a)\n(deflayer base b)") {
                let rule = manager.makeCustomRule(input: "a", output: "c")
                let nested = await manager.saveCustomRule(rule)
                XCTAssertFalse(nested)
                return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
            }
            XCTAssertTrue(result.success)
            XCTAssertTrue(manager.customRules.isEmpty)
            XCTAssertTrue(errors.contains { $0.contains("recursively") })
        }
    }

    func testQueuedCollectionCancellationDoesNotStageOrPersistRule() async throws {
        try await withFixture { service, manager, _ in
            let entered = self.expectation(description: "gate occupied")
            let started = self.expectation(description: "edit requested")
            var resume: CheckedContinuation<Void, Never>?
            let holder = Task { @MainActor in
                try await service.operationGate.withOperation { @MainActor _ in
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let rule = manager.makeCustomRule(input: "a", output: "c")
            let edit = Task { @MainActor in
                started.fulfill()
                return await manager.saveCustomRule(rule)
            }
            await self.fulfillment(of: [started], timeout: 5)
            edit.cancel()
            resume?.resume()
            try await holder.value
            let saved = await edit.value
            XCTAssertFalse(saved)
            XCTAssertTrue(manager.customRules.isEmpty)
            let stored = await manager.customRulesStore.loadRules()
            XCTAssertTrue(stored.isEmpty)
        }
    }

    func testTwoCoordinatorsShareAdmissionAcrossRejectedReload() async throws {
        try await withFixture { service, _, firstCoordinator in
            let secondCoordinator = SaveCoordinator(configurationService: service, engineClient: TCPEngineClient())
            let entered = self.expectation(description: "first reload entered")
            let started = self.expectation(description: "second save requested")
            var resume: CheckedContinuation<Void, Never>?
            var secondReloaded = false
            let first = Task { @MainActor in
                await firstCoordinator.saveGeneratedConfig(content: "(defcfg)\n(defsrc a)\n(deflayer base b)") {
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                    return ReloadResult(success: false, response: nil, errorMessage: "reject", protocol: nil, disposition: .rejected)
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let finalContent = "(defcfg)\n(defsrc a)\n(deflayer base c)"
            let second = Task { @MainActor in
                started.fulfill()
                return await secondCoordinator.saveGeneratedConfig(content: finalContent) {
                    secondReloaded = true
                    return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
                }
            }
            await self.fulfillment(of: [started], timeout: 5)
            XCTAssertFalse(secondReloaded)
            resume?.resume()
            let rejected = await first.value
            let accepted = await second.value
            XCTAssertFalse(rejected.success)
            XCTAssertTrue(accepted.success)
            XCTAssertEqual(try String(contentsOfFile: service.configurationPath, encoding: .utf8), finalContent)
        }
    }

    func testExplicitNestedPermitAndStalePermit() async throws {
        let gate = ConfigurationOperationGate()
        var previous: ConfigurationOperationGate.Permit?
        let value = try await gate.withOperation { @MainActor permit in
            previous = permit
            return try await gate.withOperation(using: permit) { _ in 7 }
        }
        XCTAssertEqual(value, 7)
        do {
            _ = try await gate.withOperation(using: XCTUnwrap(previous)) { _ in 8 }
            XCTFail("A finished operation must not authorize later nested writes")
        } catch ConfigurationOperationGate.Failure.invalidPermit {
            // Expected.
        }
        let next = try await gate.withOperation { _ in 9 }
        XCTAssertEqual(next, 9)
    }

    private func withFixture(
        _ body: @MainActor (ConfigurationService, RuleCollectionsManager, SaveCoordinator) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "SharedAdmissionTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        try "(defcfg)\n(defsrc a)\n(deflayer base a)".write(toFile: service.configurationPath, atomically: true, encoding: .utf8)
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service, keymapPreferences: preferences)
        manager.onRulesChanged = { ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil) }
        let coordinator = SaveCoordinator(configurationService: service, engineClient: TCPEngineClient())
        try await body(service, manager, coordinator)
    }
}
