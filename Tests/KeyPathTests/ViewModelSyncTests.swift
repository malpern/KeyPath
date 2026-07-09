import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import Testing

@MainActor
@Suite("Window Snapping Activation Mode Tests")
struct WindowSnappingActivationModeTests {
    private func createManagerWithWindowSnapping() async -> RuleCollectionsManager {
        TestEnvironment.forceTestMode = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-mode-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manager = RuleCollectionsManager(
            ruleCollectionStore: RuleCollectionStore(
                fileURL: tempDir.appendingPathComponent("RuleCollections.json")
            ),
            customRulesStore: CustomRulesStore(
                fileURL: tempDir.appendingPathComponent("CustomRules.json")
            ),
            configurationService: ConfigurationService(configDirectory: tempDir.path),
            eventListener: KanataEventListener()
        )

        // Seed from catalog so momentaryActivator etc. are populated
        let catalog = RuleCollectionCatalog()
        manager.ruleCollections = catalog.defaultCollections()

        // Enable Window Snapping and Quick Launcher
        if let wsIdx = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.windowSnapping }) {
            manager.ruleCollections[wsIdx].isEnabled = true
        }
        if let launcherIdx = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
            manager.ruleCollections[launcherIdx].isEnabled = true
        }

        return manager
    }

    @Test("Activation mode is stored on collection")
    func activationModeStored() async {
        let manager = await createManagerWithWindowSnapping()

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.windowSnappingActivationMode == .quickLauncher)
    }

    @Test("Activation mode updates momentary activator sourceLayer")
    func activatorSourceLayer() async {
        let manager = await createManagerWithWindowSnapping()

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
    func autoEnablesLauncher() async {
        let manager = await createManagerWithWindowSnapping()

        // Disable launcher
        if let idx = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
            manager.ruleCollections[idx].isEnabled = false
        }

        let autoEnabled = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        #expect(autoEnabled == "Quick Launcher")
        let launcher = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        #expect(launcher?.isEnabled == true)
    }

    @Test("Activation mode updates activation hint")
    func activationHint() async {
        let manager = await createManagerWithWindowSnapping()

        _ = await manager.updateWindowSnappingActivationMode(
            id: RuleCollectionIdentifier.windowSnapping,
            mode: .quickLauncher
        )

        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.activationHint == "Hyper + w → action key")
    }

    @Test("Switching back to leader restores navigation sourceLayer")
    func switchBackToLeader() async {
        let manager = await createManagerWithWindowSnapping()

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
    func settingSameModeTwiceIsIdempotent() async {
        let manager = await createManagerWithWindowSnapping()

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
    func launcherAlreadyEnabledReturnsNil() async {
        let manager = await createManagerWithWindowSnapping()

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
    func activationHintForLeaderModeInitially() async {
        let manager = await createManagerWithWindowSnapping()

        // Before any mode change, the catalog default is leader mode
        let ws = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.windowSnapping }
        #expect(ws?.activationHint == "Leader → w → action key")
    }

    @Test("Switching modes multiple times ends in correct state")
    func switchingModesMultipleTimesEndsCorrectly() async {
        let manager = await createManagerWithWindowSnapping()

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
