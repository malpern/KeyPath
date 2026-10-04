import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import Testing

@MainActor
@Suite("Window Snapping Activation Mode Tests")
struct WindowSnappingActivationModeTests {
    private func createManagerWithWindowSnapping(supportedEntrance: Bool = true) async throws -> RuleCollectionsManager {
        TestEnvironment.forceTestMode = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-mode-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let collections = RuleCollectionStore.testStore(at: tempDir.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: tempDir.appendingPathComponent("CustomRules.json"))
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collections,
            customRulesStore: rules,
            configurationService: ConfigurationService.sessionTestService(configDirectory: tempDir.path, ruleCollectionStore: collections, customRulesStore: rules),
            eventListener: KanataEventListener()
        )

        // Seed from catalog so momentaryActivator etc. are populated
        let catalog = RuleCollectionCatalog()
        manager.ruleCollections = catalog.defaultCollections()

        // Mode changes need navigation content and an entrance, not just a
        // target-layer mapping. Tab enters navigation; l and w stay free for
        // the launcher/window entrances exercised by this fixture.
        if supportedEntrance {
            manager.ruleCollections.append(RuleCollection(
                id: UUID(), name: "Test Navigation", summary: "", category: .custom,
                mappings: [KeyMapping(input: "q", action: .keystroke(key: "esc"))],
                isEnabled: true, targetLayer: .navigation,
                momentaryActivator: MomentaryActivator(input: "tab", targetLayer: .navigation)
            ))
        }

        // Enable Window Snapping and Quick Launcher
        if let wsIdx = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.windowSnapping }) {
            manager.ruleCollections[wsIdx].isEnabled = true
        }
        if let launcherIdx = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
            manager.ruleCollections[launcherIdx].isEnabled = true
            // Exercise mode wiring with a supported launcher entrance. The
            // historical Hyper/Caps entrance has a separate refusal test.
            if supportedEntrance {
                manager.ruleCollections[launcherIdx].configuration = .launcherGrid(LauncherGridConfig(
                    activationMode: .leaderSequence
                ))
            }
        }

        if !supportedEntrance,
           let capsIndex = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        {
            // Keep the historical rejection tied to a real unsupported physical
            // Caps input, independently of supported layer-exit actions.
            manager.ruleCollections[capsIndex].isEnabled = true
        }

        manager.preferencesService.stageShortcutListGenerationInput(
            ShortcutListGenerationInput(triggerMode: .holdToShow, holdDelayPreset: .long, customHoldDelayMs: 200)
        )
        try await collections.saveCollections(manager.ruleCollections)
        try await rules.saveRules([])
        manager.onError = { error in
            Issue.record("Window activation generated profile refused: \(error)")
        }
        return manager
    }

    @Test("Unsupported historical Hyper entrance preserves activation state and sources")
    func unsupportedHyperEntranceRefusesBeforeJournalOrReload() async throws {
        let manager = try await createManagerWithWindowSnapping(supportedEntrance: false)
        let beforeCollections = manager.ruleCollections
        #expect(beforeCollections.contains { $0.id == RuleCollectionIdentifier.capsLockRemap && $0.isEnabled })
        let directory = URL(fileURLWithPath: manager.configurationService.configurationPath).deletingLastPathComponent()
        let before = try Data(contentsOf: directory.appendingPathComponent("RuleCollections.json"))
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
        }
        _ = await manager.updateWindowSnappingActivationMode(id: RuleCollectionIdentifier.windowSnapping, mode: .quickLauncher)
        #expect(reloads == 0)
        #expect(manager.ruleCollections == beforeCollections)
        #expect(try Data(contentsOf: directory.appendingPathComponent("RuleCollections.json")) == before)
        #expect(errors.contains { $0.contains("driverless session") })
        #expect(!FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
        #expect(!FileManager.default.fileExists(atPath: manager.configurationService.configurationPath))
    }

    @Test("Activation mode is stored on collection")
    func activationModeStored() async throws {
        let manager = try await createManagerWithWindowSnapping()

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.windowSnappingActivationMode == .quickLauncher)
    }

    @Test("Activation mode updates momentary activator sourceLayer")
    func activatorSourceLayer() async throws {
        let manager = try await createManagerWithWindowSnapping()

        let before = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(before?.momentaryActivator?.sourceLayer == .navigation)

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let after = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(after?.momentaryActivator?.sourceLayer == .custom("launcher"))
    }

    @Test("Quick Launcher mode auto-enables launcher collection")
    func autoEnablesLauncher() async throws {
        let manager = try await createManagerWithWindowSnapping()

        // Root edits refresh persisted sources, so the disabled premise must
        // reach the store before asking the manager to enable its provider.
        if let idx = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
            manager.ruleCollections[idx].isEnabled = false
        }
        try await manager.ruleCollectionStore.saveCollections(manager.ruleCollections)
        let stored = try await manager.ruleCollectionStore.loadForMutation()
        #expect(stored.first { $0.id == RuleCollectionIdentifier.launcher }?.isEnabled == false)

        let autoEnabled = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        #expect(autoEnabled == "Quick Launcher")
        let launcher = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        #expect(launcher?.isEnabled == true)
    }

    @Test("Catalog-only cancelled Home Row Mods edits resolve to catalog state")
    func catalogOnlyHomeRowModsFallback() {
        var attempted = HomeRowModsConfig()
        attempted.holdMode = .layers

        let persisted = KanataViewModel.persistedHomeRowModsConfig(
            collectionId: RuleCollectionIdentifier.homeRowMods,
            collections: []
        )

        #expect(persisted.holdMode == .modifiers)
        #expect(persisted != attempted)
    }

    @Test("Activation mode updates activation hint")
    func activationHint() async throws {
        let manager = try await createManagerWithWindowSnapping()

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.activationHint == "Hyper + w → action key")
    }

    @Test("Switching back to leader restores navigation sourceLayer")
    func switchBackToLeader() async throws {
        let manager = try await createManagerWithWindowSnapping()

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )
        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .leader
        )

        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.momentaryActivator?.sourceLayer == .navigation)
        #expect(ws?.activationHint == "Leader → w → action key")
    }

    @Test("Setting same mode twice is idempotent")
    func settingSameModeTwiceIsIdempotent() async throws {
        let manager = try await createManagerWithWindowSnapping()

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let wsAfterFirst = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        let modeAfterFirst = wsAfterFirst?.windowSnappingActivationMode
        let hintAfterFirst = wsAfterFirst?.activationHint

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let wsAfterSecond = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(wsAfterSecond?.windowSnappingActivationMode == modeAfterFirst)
        #expect(wsAfterSecond?.activationHint == hintAfterFirst)
    }

    @Test("Launcher already enabled returns nil for auto-enable")
    func launcherAlreadyEnabledReturnsNil() async throws {
        let manager = try await createManagerWithWindowSnapping()

        // Launcher is already enabled by createManagerWithWindowSnapping()
        let launcher = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        #expect(launcher?.isEnabled == true)

        let autoEnabled = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        #expect(autoEnabled == nil)
    }

    @Test("Activation hint for leader mode initially")
    func activationHintForLeaderModeInitially() async throws {
        let manager = try await createManagerWithWindowSnapping()

        // Before any mode change, the catalog default is leader mode
        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.activationHint == "Leader → w → action key")
    }

    @Test("Switching modes multiple times ends in correct state")
    func switchingModesMultipleTimesEndsCorrectly() async throws {
        let manager = try await createManagerWithWindowSnapping()

        // leader → quickLauncher → leader → quickLauncher
        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .leader
        )
        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )
        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .leader
        )
        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.windowSnappingActivationMode == .quickLauncher)
        #expect(ws?.momentaryActivator?.sourceLayer == .custom("launcher"))
        #expect(ws?.activationHint == "Hyper + w → action key")
    }
}
