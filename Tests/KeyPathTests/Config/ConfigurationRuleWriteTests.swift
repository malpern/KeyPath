import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class ConfigurationRuleWriteTests: KeyPathTestCase {
    private var directory: URL!
    private var collections: RuleCollectionStore!
    private var customRules: CustomRulesStore!
    private var service: ConfigurationService!

    override func setUp() async throws {
        try await super.setUp()
        try SessionBridgeTestFixture.requireAvailable()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        collections = .testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        customRules = .testStore(at: directory.appendingPathComponent("CustomRules.json"))
        service = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: customRules)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        collections = nil
        customRules = nil
        service = nil
        directory = nil
        try await super.tearDown()
    }

    private func collection(_ name: String) -> RuleCollection {
        RuleCollection(name: name, summary: name, category: .custom,
                       mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"))], isEnabled: true)
    }

    func testObserversSeeBothSourceStoresAlreadyCommitted() async throws {
        let expected = collection("Committed")
        let collectionStore = try XCTUnwrap(collections)
        let customStore = try XCTUnwrap(customRules)
        let observed = expectation(description: "committed observer")
        let token = service.observe { _ in
            let storedCollections = await collectionStore.loadCollections()
            let storedRules = await customStore.loadRules()
            XCTAssertTrue(storedCollections.contains { $0.id == expected.id })
            XCTAssertTrue(storedRules.isEmpty)
            observed.fulfill()
        }
        try await service.saveRuleState(ruleCollections: [expected], customRules: [], collectionStore: collections, customStore: customRules)
        await fulfillment(of: [observed], timeout: 2)
        withExtendedLifetime(token) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testUnreadableSourceStoreLeavesPriorConfigAndOtherStoreUntouched() async throws {
        let original = collection("Original")
        try await service.saveRuleState(ruleCollections: [original], customRules: [], collectionStore: collections, customStore: customRules)
        let configURL = URL(fileURLWithPath: service.configurationPath)
        let collectionURL = await collections.persistenceURL
        let customURL = await customRules.persistenceURL
        let oldConfig = try Data(contentsOf: configURL)
        let oldCollections = try Data(contentsOf: collectionURL)
        try FileManager.default.removeItem(at: customURL)
        try FileManager.default.createDirectory(at: customURL, withIntermediateDirectories: true)
        let count = ObservationCount()
        let token = service.observe { _ in await count.increment() }
        do {
            try await service.saveRuleState(ruleCollections: [collection("Candidate")], customRules: [], collectionStore: collections, customStore: customRules)
            XCTFail("An unreadable preimage must stop the operation")
        } catch {
            XCTAssertEqual(try Data(contentsOf: configURL), oldConfig)
            XCTAssertEqual(try Data(contentsOf: collectionURL), oldCollections)
            let notifications = await count.value
            XCTAssertEqual(notifications, 0)
        }
        withExtendedLifetime(token) {}
    }

    func testStagedRevisionNotifiesOnlyAfterCommit() async throws {
        let count = ObservationCount()
        let token = service.observe { _ in await count.increment() }
        try await service.operationGate.withOperation { @MainActor permit in
            let write = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Staged")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
            let stagedCount = await count.value
            XCTAssertEqual(stagedCount, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(self.directory).path))
            try await self.service.settleRuleWrite(write, commit: true, mutationPermit: permit)
            let committedCount = await count.value
            XCTAssertEqual(committedCount, 1)
        }
        withExtendedLifetime(token) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testStagedRollbackRestoresExactThreeFileRevisionWithoutNotification() async throws {
        try await service.saveRuleState(ruleCollections: [collection("Original")], customRules: [], collectionStore: collections, customStore: customRules)
        let before = try snapshot()
        let count = ObservationCount()
        let token = service.observe { _ in await count.increment() }
        try await service.operationGate.withOperation { @MainActor permit in
            let write = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Candidate")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
            try await self.service.settleRuleWrite(write, commit: false, mutationPermit: permit)
        }
        XCTAssertEqual(try snapshot(), before)
        let notifications = await count.value
        XCTAssertEqual(notifications, 0)
        withExtendedLifetime(token) {}
    }

    func testExternalEditAfterStagePreventsCommitAndRollback() async throws {
        try await service.saveRuleState(ruleCollections: [collection("Original")], customRules: [], collectionStore: collections, customStore: customRules)
        try await service.operationGate.withOperation { @MainActor permit in
            let write = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Candidate")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
            try "external edit".write(toFile: self.service.configurationPath, atomically: true, encoding: .utf8)
            let externalRevision = try self.snapshot()
            for commit in [true, false] {
                do {
                    try await self.service.settleRuleWrite(write, commit: commit, mutationPermit: permit)
                    XCTFail("External changes must stop settlement")
                } catch {
                    XCTAssertEqual(try self.snapshot(), externalRevision)
                }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testManualGlobalConfigIsPreservedBeforeSourceWrites() async throws {
        let original = collection("Original")
        try await service.saveRuleState(
            ruleCollections: [original], customRules: [],
            collectionStore: collections, customStore: customRules
        )
        let configURL = URL(fileURLWithPath: service.configurationPath)
        let collectionURL = await collections.persistenceURL
        let customURL = await customRules.persistenceURL
        let beforeCollections = try Data(contentsOf: collectionURL)
        let beforeRules = try Data(contentsOf: customURL)
        try ";; handwritten global configuration".write(to: configURL, atomically: true, encoding: .utf8)

        do {
            try await service.saveRuleState(
                ruleCollections: [collection("Candidate")], customRules: [],
                collectionStore: collections, customStore: customRules
            )
            XCTFail("A global writer must preserve a configuration it cannot reproduce")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("configuration was preserved"))
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), ";; handwritten global configuration")
        XCTAssertEqual(try Data(contentsOf: collectionURL), beforeCollections)
        XCTAssertEqual(try Data(contentsOf: customURL), beforeRules)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testStandaloneRegenerationPreservesManualGlobalConfig() async throws {
        let original = collection("Original")
        try await service.saveRuleState(
            ruleCollections: [original], customRules: [],
            collectionStore: collections, customStore: customRules
        )
        let configURL = URL(fileURLWithPath: service.configurationPath)
        let collectionURL = await collections.persistenceURL
        let beforeCollections = try Data(contentsOf: collectionURL)
        try ";; handwritten global configuration".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = RuleCollectionsManager(
            ruleCollectionStore: collections,
            customRulesStore: customRules,
            configurationService: service
        )
        manager.ruleCollections = [collection("Candidate")]
        let persisted = await manager.regenerateConfigFromCollections(skipReload: true)

        XCTAssertFalse(persisted)
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), ";; handwritten global configuration")
        XCTAssertEqual(try Data(contentsOf: collectionURL), beforeCollections)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testDeviceScopedCandidateIsRejectedBeforeAnySourceStoreChanges() async throws {
        try await service.saveRuleState(
            ruleCollections: [collection("Original")], customRules: [],
            collectionStore: collections, customStore: customRules
        )
        let configBefore = try Data(contentsOf: URL(fileURLWithPath: service.configurationPath))
        let collectionsURL = await collections.persistenceURL
        let customURL = await customRules.persistenceURL
        let collectionsBefore = try Data(contentsOf: collectionsURL)
        let customBefore = try Data(contentsOf: customURL)
        let connectedCache = DeviceSelectionCache()
        connectedCache.updateConnectedDevices([
            ConnectedDevice(hash: "disabled-device", vendorID: 1, productID: 2,
                            productKey: "Example Keyboard", isVirtualHID: false)
        ])
        let deviceURL = directory.appendingPathComponent("DeviceSelection.json")
        let deviceStore = DeviceSelectionStore(fileURL: deviceURL, cache: connectedCache)
        let candidateService = ConfigurationService.sessionTestService(
            configDirectory: directory.path, ruleCollectionStore: collections,
            customRulesStore: customRules, deviceSelectionStore: deviceStore
        )
        let selection = DeviceSelection(hash: "disabled-device", productKey: "Example Keyboard", isEnabled: false, lastSeen: Date())
        do {
            try await candidateService.operationGate.withOperation { @MainActor permit in
                _ = try await candidateService.stageRuleState(
                    ruleCollections: [collection("Candidate")], customRules: [],
                    collectionStore: self.collections, customStore: self.customRules,
                    mutationPermit: permit, deviceSelections: [selection]
                )
            }
            XCTFail("Device-scoped candidate must not be staged")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("driverless session"), error.localizedDescription)
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: service.configurationPath)), configBefore)
        XCTAssertEqual(try Data(contentsOf: collectionsURL), collectionsBefore)
        XCTAssertEqual(try Data(contentsOf: customURL), customBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deviceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .deviceRules).path))
    }

    func testManualDeviceDirectiveIsPreservedBeforeSourceWrites() async throws {
        let cache = DeviceSelectionCache()
        cache.updateConnectedDevices([
            ConnectedDevice(hash: "disabled-device", vendorID: 1, productID: 2,
                            productKey: "Example Keyboard", isVirtualHID: false)
        ])
        let deviceStore = DeviceSelectionStore(
            fileURL: directory.appendingPathComponent("DeviceSelection.json"), cache: cache
        )
        let service = ConfigurationService.sessionTestService(
            configDirectory: directory.path, ruleCollectionStore: collections,
            customRulesStore: customRules, deviceSelectionStore: deviceStore
        )
        let selection = DeviceSelection(
            hash: "disabled-device", productKey: "Example Keyboard",
            isEnabled: false, lastSeen: .distantPast
        )
        let original = collection("Original")
        try await service.saveRuleState(
            ruleCollections: [original], customRules: [],
            collectionStore: collections, customStore: customRules
        )
        // Model an existing advanced profile written before the driverless
        // experiment. New device-scoped writes must never be used as setup.
        let legacy = try await service.generateConfiguration(
            ruleCollections: [original], customRules: [],
            deviceGenerationInput: DeviceGenerationInput(
                selections: [selection], connectedDevices: cache.getConnectedDevices()
            )
        )
        let configURL = URL(fileURLWithPath: service.configurationPath)
        let handwritten = legacy.content
            .replacingOccurrences(of: "__keypath_no_devices__", with: "Handwritten Keyboard")
        try handwritten.write(to: configURL, atomically: true, encoding: .utf8)
        let collectionURL = await collections.persistenceURL
        let beforeCollections = try Data(contentsOf: collectionURL)

        do {
            try await service.saveRuleState(
                ruleCollections: [collection("Candidate")], customRules: [],
                collectionStore: collections, customStore: customRules
            )
            XCTFail("A hand-edited device directive must be preserved")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("configuration was preserved"))
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), handwritten)
        XCTAssertEqual(try Data(contentsOf: collectionURL), beforeCollections)
    }

    func testInterruptedStageIsRecoveredByFreshService() async throws {
        try await service.saveRuleState(ruleCollections: [collection("Original")], customRules: [], collectionStore: collections, customStore: customRules)
        let before = try snapshot()
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Interrupted")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
        }
        let fresh = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: customRules)
        try await fresh.recoverPendingRuleWrite(collectionStore: collections, customStore: customRules)
        XCTAssertEqual(try snapshot(), before)
    }

    private func snapshot() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json"].map {
            try ($0, Data(contentsOf: directory.appendingPathComponent($0)))
        })
    }

    func testBootstrapRecoversInterruptedWriteBeforeLoadingSourceStores() async throws {
        let original = collection("Original")
        let candidate = collection("Candidate")
        try await service.saveRuleState(ruleCollections: [original], customRules: [], collectionStore: collections, customStore: customRules)
        let files = await [
            "config": URL(fileURLWithPath: service.configurationPath),
            "collections": collections.persistenceURL,
            "customRules": customRules.persistenceURL
        ]
        var entries: [RecoverableRuleWrite.Entry] = []
        for role in files.keys.sorted() {
            let url = files[role]!
            let before = try Data(contentsOf: url)
            let after = role == "collections" ? try await collections.encodedCollections([candidate]) : before
            entries.append(.init(role: role, path: url.path, before: before, after: after))
        }
        let journal = RecoverableRuleWrite.Journal(version: 1, committed: false, entries: entries)
        try JSONEncoder().encode(journal).write(to: RecoverableRuleWrite.journalURL(directory))
        for entry in entries {
            try entry.after.write(to: files[entry.role]!)
        }
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: customRules, configurationService: service)
        await manager.bootstrap()
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == original.id })
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == candidate.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }
}

private actor ObservationCount {
    var value = 0
    func increment() {
        value += 1
    }
}
