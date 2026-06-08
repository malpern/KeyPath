@testable import KeyPathAppKit
import XCTest

final class RuleCollectionStorePersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuleCollectionStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> RuleCollectionStore {
        let url = tempDir.appendingPathComponent("RuleCollections.json")
        return RuleCollectionStore.testStore(at: url)
    }

    // MARK: - Load: no file → defaults

    func testLoadCollections_NoFile_ReturnsDefaults() async {
        let store = makeStore()
        let collections = await store.loadCollections()
        XCTAssertFalse(collections.isEmpty)
        let ids = Set(collections.map(\.id))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.macFunctionKeys))
    }

    // MARK: - Save and reload round-trip

    func testSaveAndLoad_PreservesCollections() async throws {
        let store = makeStore()
        var collections = await store.loadCollections()

        // Enable one, disable another
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = false
        }

        try await store.saveCollections(collections)

        let store2 = makeStore()
        let reloaded = await store2.loadCollections()

        let capsReloaded = reloaded.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        let hrmReloaded = reloaded.first(where: { $0.id == RuleCollectionIdentifier.homeRowMods })
        XCTAssertTrue(capsReloaded?.isEnabled ?? false)
        XCTAssertFalse(hrmReloaded?.isEnabled ?? true)
    }

    func testSaveAndLoad_PreservesPerRuleOptionConfigurations() async throws {
        let store = makeStore()
        var collections = await store.loadCollections()

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
            collections[idx].configuration.updateSelectedTapOutput("esc")
            collections[idx].configuration.updateSelectedHoldOutput("lctl")
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            var timing = TimingConfig.default
            timing.tapWindow = 210
            timing.holdDelay = 170
            timing.quickTapEnabled = true
            timing.requirePriorIdleMs = 120
            collections[idx].isEnabled = true
            collections[idx].configuration = .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a", "s"],
                modifierAssignments: ["a": "lctl", "s": "lalt"],
                holdMode: .modifiers,
                timing: timing,
                keySelection: .custom,
                oppositeHandMode: .release
            ))
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }) {
            collections[idx].isEnabled = true
            collections[idx].configuration = .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: ["f"],
                layerAssignments: ["f": "nav"],
                keySelection: .custom,
                toggleMode: .toggle,
                showAdvanced: true,
                oppositeHandMode: .off
            ))
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.chordGroups }) {
            let chordGroup = ChordGroup(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "persist-jk",
                timeout: 180,
                chords: [
                    ChordDefinition(
                        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                        keys: ["j", "k"],
                        action: .keystroke(key: "esc")
                    )
                ]
            )
            collections[idx].isEnabled = true
            collections[idx].configuration = .chordGroups(ChordGroupsConfig(groups: [chordGroup], activeGroupID: chordGroup.id, showAdvanced: true))
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.sequences }) {
            let sequence = SequenceDefinition(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "Window",
                keys: ["space", "w"],
                action: .activateLayer(.custom("window"))
            )
            collections[idx].isEnabled = true
            collections[idx].configuration = .sequences(SequencesConfig(sequences: [sequence], activeSequenceID: sequence.id, globalTimeout: 750))
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.symbolLayer }) {
            collections[idx].isEnabled = true
            collections[idx].configuration.updateSelectedPreset("programmer")
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
            collections[idx].isEnabled = true
            collections[idx].configuration = .launcherGrid(LauncherGridConfig(
                activationMode: .holdHyper,
                hyperTriggerMode: .tap,
                mappings: [
                    LauncherMapping(key: "a", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")),
                    LauncherMapping(key: "u", action: .openURL("https://github.com")),
                ],
                hasSeenWelcome: true
            ))
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.autoShiftSymbols }) {
            var config = AutoShiftSymbolsConfig()
            config.enabledKeys = ["min", "eql"]
            config.timeoutMs = 190
            config.protectFastTyping = true
            collections[idx].isEnabled = true
            collections[idx].configuration = .autoShiftSymbols(config)
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.keyRepeatControl }) {
            collections[idx].isEnabled = true
            collections[idx].configuration = .keyRepeatControl(KeyRepeatControlConfig(
                isEnabled: true,
                globalDelayMs: 175,
                globalIntervalMs: 25,
                perKeyOverrides: [KeyRepeatOverride(key: "left", delayMs: 100, intervalMs: 15)]
            ))
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.windowSnapping }) {
            collections[idx].isEnabled = true
            collections[idx].windowKeyConvention = .vim
            collections[idx].windowSnappingActivationMode = .quickLauncher
            collections[idx].mappings = RuleCollectionCatalog.windowMappings(for: .vim)
        }

        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.macFunctionKeys }) {
            collections[idx].functionKeyMode = .function
            collections[idx].mappings = RuleCollectionCatalog.functionKeyMappings(for: .function)
        }

        try await store.saveCollections(collections)

        let reloaded = await makeStore().loadCollections()

        let caps = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.capsLockRemap })
        XCTAssertEqual(caps.configuration.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(caps.configuration.tapHoldPickerConfig?.selectedHoldOutput, "lctl")

        let hrm = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.homeRowMods })
        XCTAssertEqual(hrm.configuration.homeRowModsConfig?.enabledKeys, ["a", "s"])
        XCTAssertEqual(hrm.configuration.homeRowModsConfig?.timing.requirePriorIdleMs, 120)
        XCTAssertEqual(hrm.configuration.homeRowModsConfig?.oppositeHandMode, .release)

        let toggles = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles })
        XCTAssertEqual(toggles.configuration.homeRowLayerTogglesConfig?.layerAssignments["f"], "nav")
        XCTAssertEqual(toggles.configuration.homeRowLayerTogglesConfig?.toggleMode, .toggle)

        let chords = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.chordGroups })
        XCTAssertEqual(chords.configuration.chordGroupsConfig?.groups.first?.name, "persist-jk")
        XCTAssertEqual(chords.configuration.chordGroupsConfig?.showAdvanced, true)

        let sequences = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.sequences })
        XCTAssertEqual(sequences.configuration.sequencesConfig?.sequences.first?.keys, ["space", "w"])
        XCTAssertEqual(sequences.configuration.sequencesConfig?.globalTimeout, 750)

        let symbol = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.symbolLayer })
        XCTAssertEqual(symbol.configuration.layerPresetPickerConfig?.selectedPresetId, "programmer")

        let launcher = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.launcher })
        XCTAssertEqual(launcher.configuration.launcherGridConfig?.hyperTriggerMode, .tap)
        XCTAssertEqual(launcher.configuration.launcherGridConfig?.mappings.count, 2)

        let autoShift = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.autoShiftSymbols })
        XCTAssertEqual(autoShift.configuration.autoShiftSymbolsConfig?.enabledKeys, ["min", "eql"])
        XCTAssertEqual(autoShift.configuration.autoShiftSymbolsConfig?.protectFastTyping, true)

        let repeatControl = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.keyRepeatControl })
        XCTAssertEqual(repeatControl.configuration.keyRepeatControlConfig?.globalDelayMs, 175)
        XCTAssertEqual(repeatControl.configuration.keyRepeatControlConfig?.perKeyOverrides.first?.intervalMs, 15)

        let window = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.windowSnapping })
        XCTAssertEqual(window.windowKeyConvention, .vim)
        XCTAssertEqual(window.windowSnappingActivationMode, .quickLauncher)
        XCTAssertEqual(window.mappings.first?.input, "h")

        let functionKeys = try XCTUnwrap(reloaded.first { $0.id == RuleCollectionIdentifier.macFunctionKeys })
        XCTAssertEqual(functionKeys.functionKeyMode, .function)
        XCTAssertEqual(functionKeys.mappings.first?.action, .keystroke(key: "f1"))
    }

    // MARK: - Corrupt file → resilient recovery

    func testLoadCollections_CorruptFile_FallsBackToDefaults() async throws {
        let url = tempDir.appendingPathComponent("RuleCollections.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = RuleCollectionStore.testStore(at: url)
        let result = await store.loadCollectionsDetailed()
        XCTAssertFalse(result.collections.isEmpty)
        XCTAssertTrue(result.wasFullReset)
    }

    // MARK: - Missing collections get merged from catalog

    func testLoadCollections_MissingDefaults_GetMergedIn() async throws {
        let store = makeStore()
        // Save only one collection
        let justOne = [RuleCollectionCatalog().defaultCollections().first!]
        try await store.saveCollections(justOne)

        let store2 = makeStore()
        let reloaded = await store2.loadCollections()
        XCTAssertGreaterThan(reloaded.count, 1, "Catalog defaults should be merged back in")
        let ids = Set(reloaded.map(\.id))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.capsLockRemap))
    }

    // MARK: - Schema version

    func testSchemaVersion_IsPositive() {
        XCTAssertGreaterThan(RuleCollectionStore.currentSchemaVersion, 0)
    }
}
