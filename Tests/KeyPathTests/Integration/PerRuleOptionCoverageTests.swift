@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

@MainActor
final class PerRuleOptionCoverageTests: XCTestCase {
    func testShippingRuleInventoryAccountsForEveryCatalogCollection() {
        let expected: [UUID: (name: String, style: RuleCollectionDisplayStyle)] = [
            RuleCollectionIdentifier.macFunctionKeys: ("macOS Function Keys", .table),
            RuleCollectionIdentifier.leaderKey: ("Leader Key", .singleKeyPicker),
            RuleCollectionIdentifier.vimNavigation: ("Vim - Apple Keyboard Shortcuts", .table),
            RuleCollectionIdentifier.neovimTerminal: ("Neovim Terminal", .table),
            RuleCollectionIdentifier.missionControl: ("Mission Control", .table),
            RuleCollectionIdentifier.windowSnapping: ("Window Snapping", .table),
            RuleCollectionIdentifier.capsLockRemap: ("Caps Lock Remap", .tapHoldPicker),
            RuleCollectionIdentifier.backupCapsLock: ("Backup Caps Lock", .singleKeyPicker),
            RuleCollectionIdentifier.escapeRemap: ("Escape", .singleKeyPicker),
            RuleCollectionIdentifier.deleteRemap: ("Delete Enhancement", .singleKeyPicker),
            RuleCollectionIdentifier.homeRowMods: ("Home Row Mods", .homeRowMods),
            RuleCollectionIdentifier.homeRowLayerToggles: ("Home Row Layer Toggles", .homeRowLayerToggles),
            RuleCollectionIdentifier.chordGroups: ("Chord Groups", .chordGroups),
            RuleCollectionIdentifier.sequences: ("Sequences", .sequences),
            RuleCollectionIdentifier.numpadLayer: ("Numpad", .table),
            RuleCollectionIdentifier.symbolLayer: ("Symbol", .layerPresetPicker),
            RuleCollectionIdentifier.funLayer: ("Function", .table),
            RuleCollectionIdentifier.autoShiftSymbols: ("Auto Shift Symbols", .autoShiftSymbols),
            RuleCollectionIdentifier.keyRepeatControl: ("Fast Navigation", .keyRepeatControl),
            RuleCollectionIdentifier.homeRowArrows: ("Home Row Arrows", .layerPresetPicker),
            RuleCollectionIdentifier.vallackNavigation: ("Ben Vallack Nav", .table),
            RuleCollectionIdentifier.launcher: ("Quick Launcher", .launcherGrid)
        ]

        let collections = RuleCollectionCatalog().defaultCollections()
        XCTAssertEqual(Set(collections.map(\.id)), Set(expected.keys))

        for collection in collections {
            let coverage = expected[collection.id]
            XCTAssertEqual(collection.name, coverage?.name)
            XCTAssertEqual(collection.displayStyle, coverage?.style, collection.name)
        }
    }

    func testEveryEnabledTableCollectionEmitsDefaultConfigFragment() throws {
        let tableIDs = [
            RuleCollectionIdentifier.macFunctionKeys,
            RuleCollectionIdentifier.vimNavigation,
            RuleCollectionIdentifier.neovimTerminal,
            RuleCollectionIdentifier.missionControl,
            RuleCollectionIdentifier.windowSnapping,
            RuleCollectionIdentifier.numpadLayer,
            RuleCollectionIdentifier.funLayer,
            RuleCollectionIdentifier.vallackNavigation
        ]

        for id in tableIDs {
            var collection = try catalogCollection(id)
            collection.isEnabled = true

            let config = KanataConfiguration.generateFromCollections([collection])

            assertContains(config, "(deflayer \(collection.targetLayer.kanataName)", collection.name)
            let mapping = try XCTUnwrap(collection.mappings.first, collection.name)
            assertContains(config, mapping.action.kanataOutput, collection.name)
            assertBalanced(config, collection.name)
        }
    }

    func testFunctionKeyModeVariantsEmitMediaAndStandardFunctionOutputs() throws {
        var media = try catalogCollection(RuleCollectionIdentifier.macFunctionKeys)
        media.isEnabled = true
        media.functionKeyMode = .media
        media.mappings = RuleCollectionCatalog.functionKeyMappings(for: .media)
        let mediaConfig = KanataConfiguration.generateFromCollections([media])
        assertContains(mediaConfig, "brdn", "media mode should emit brightness down")
        assertContains(mediaConfig, "volu", "media mode should emit volume up")

        var function = try catalogCollection(RuleCollectionIdentifier.macFunctionKeys)
        function.isEnabled = true
        function.functionKeyMode = .function
        function.mappings = RuleCollectionCatalog.functionKeyMappings(for: .function)
        let functionConfig = KanataConfiguration.generateFromCollections([function])
        XCTAssertFalse(function.mappings.map(\.action.kanataOutput).contains("brdn"))
        XCTAssertFalse(function.mappings.map(\.action.kanataOutput).contains("volu"))
        assertContains(functionConfig, "(deflayer base", "function mode should still emit base layer")
        assertBalanced(functionConfig, "function key mode")
    }

    func testWindowSnappingConventionVariantsEmitExpectedActionKeys() throws {
        var standard = try catalogCollection(RuleCollectionIdentifier.windowSnapping)
        standard.isEnabled = true
        standard.windowKeyConvention = .standard
        standard.mappings = RuleCollectionCatalog.windowMappings(for: .standard)
        let standardConfig = KanataConfiguration.generateFromCollections([standard])
        assertContains(standardConfig, #"act_window_l (push-msg "window:left")"#, "standard window left")
        assertContains(standardConfig, #"act_window_r (push-msg "window:right")"#, "standard window right")

        var vim = try catalogCollection(RuleCollectionIdentifier.windowSnapping)
        vim.isEnabled = true
        vim.windowKeyConvention = .vim
        vim.mappings = RuleCollectionCatalog.windowMappings(for: .vim)
        let vimConfig = KanataConfiguration.generateFromCollections([vim])
        assertContains(vimConfig, #"act_window_h (push-msg "window:left")"#, "vim window left")
        assertContains(vimConfig, #"act_window_l (push-msg "window:right")"#, "vim window right")
    }

    func testPickerAndGeneratedStyleOptionsEmitSpecificConfigFragments() throws {
        var backupCaps = try catalogCollection(RuleCollectionIdentifier.backupCapsLock)
        backupCaps.isEnabled = true
        let backupConfig = KanataConfiguration.generateFromCollections([backupCaps])
        assertContains(backupConfig, "(defchordsv2", "backup caps chord block")
        assertContains(backupConfig, "(lsft rsft) caps $chord-timeout all-released ()", "backup caps chord")

        var caps = try catalogCollection(RuleCollectionIdentifier.capsLockRemap)
        caps.isEnabled = true
        caps.configuration = .tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "Escape", description: "")],
            holdOptions: [SingleKeyPreset(output: "lctl", label: "Control", description: "")],
            selectedTapOutput: "esc",
            selectedHoldOutput: "lctl"
        ))
        let capsConfig = KanataConfiguration.generateFromCollections([caps])
        assertContains(capsConfig, "beh_base_caps (tap-hold-press $tap-timeout $hold-timeout esc lctl)", "caps tap-hold picker")

        var symbol = try catalogCollection(RuleCollectionIdentifier.symbolLayer)
        symbol.isEnabled = true
        symbol.configuration.updateSelectedPreset("paired")
        let symbolConfig = KanataConfiguration.generateFromCollections([symbol])
        assertContains(symbolConfig, "(deflayer sym", "symbol layer")
        assertContains(symbolConfig, "(multi lsft grv)", "paired symbol preset")

        var arrows = try catalogCollection(RuleCollectionIdentifier.homeRowArrows)
        arrows.isEnabled = true
        arrows.configuration.updateSelectedPreset("vim")
        let arrowsConfig = KanataConfiguration.generateFromCollections([arrows])
        assertContains(arrowsConfig, "(deflayer home-arrows", "home row arrows layer")
        assertContains(arrowsConfig, "left", "vim arrow preset")
    }

    func testAdvancedGeneratedCollectionsEmitConfiguredFragments() {
        let hrm = collection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            configuration: .homeRowMods(HomeRowModsConfig(
                enabledKeys: ["a"],
                modifierAssignments: ["a": "lctl"],
                holdMode: .modifiers,
                oppositeHandMode: .off
            ))
        )
        assertContains(
            KanataConfiguration.generateFromCollections([hrm]),
            "beh_base_a (tap-hold-press $tap-timeout 150 a lctl)",
            "HRM modifier output"
        )

        let layerToggles = collection(
            id: RuleCollectionIdentifier.homeRowLayerToggles,
            name: "Home Row Layer Toggles",
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig(
                enabledKeys: ["f"],
                layerAssignments: ["f": "nav"],
                toggleMode: .toggle,
                oppositeHandMode: .off
            ))
        )
        assertContains(
            KanataConfiguration.generateFromCollections([layerToggles]),
            "beh_base_f (tap-hold-press $tap-timeout 150 f (layer-toggle nav))",
            "home row layer toggle"
        )

        let chordGroup = ChordGroup(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "kp-jk",
            timeout: 175,
            chords: [
                ChordDefinition(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    keys: ["j", "k"],
                    action: .keystroke(key: "esc")
                )
            ]
        )
        let chords = collection(
            id: RuleCollectionIdentifier.chordGroups,
            name: "Chord Groups",
            configuration: .chordGroups(ChordGroupsConfig(groups: [chordGroup]))
        )
        let chordConfig = KanataConfiguration.generateFromCollections([chords])
        assertContains(chordConfig, "(defchords kp-jk 175", "UI-authored chord group")
        assertContains(chordConfig, "(j k) esc", "UI-authored chord output")

        var autoShift = AutoShiftSymbolsConfig()
        autoShift.enabledKeys = ["min"]
        autoShift.timeoutMs = 175
        autoShift.protectFastTyping = true
        let autoShiftCollection = collection(
            id: RuleCollectionIdentifier.autoShiftSymbols,
            name: "Auto Shift Symbols",
            configuration: .autoShiftSymbols(autoShift)
        )
        let autoShiftConfig = KanataConfiguration.generateFromCollections([autoShiftCollection])
        assertContains(autoShiftConfig, "tap-hold-require-prior-idle 175", "auto-shift protect typing")
        assertContains(autoShiftConfig, "beh_base_min (tap-hold 175 175 min S-min)", "auto-shift output")

        var repeatConfig = KeyRepeatControlConfig()
        repeatConfig.isEnabled = true
        repeatConfig.globalDelayMs = 175
        repeatConfig.globalIntervalMs = 30
        repeatConfig.perKeyOverrides = [KeyRepeatOverride(key: "left", delayMs: 100, intervalMs: 15)]
        let repeatCollection = collection(
            id: RuleCollectionIdentifier.keyRepeatControl,
            name: "Fast Navigation",
            configuration: .keyRepeatControl(repeatConfig)
        )
        let repeatOutput = KanataConfiguration.generateFromCollections([repeatCollection])
        assertContains(repeatOutput, "managed-repeat-delay 175", "repeat global delay")
        assertContains(repeatOutput, "(left  100 15)", "repeat per-key override")
    }

    func testLauncherActionVariantsEmitPushMessages() {
        var launcher = LauncherGridConfig()
        launcher.hyperTriggerMode = .hold
        launcher.mappings = [
            LauncherMapping(key: "a", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")),
            LauncherMapping(key: "u", action: .openURL("https://github.com")),
            LauncherMapping(key: "f", action: .openFolder(path: "~/Downloads", name: "Downloads")),
            LauncherMapping(key: "s", action: .runScript(path: "~/bin/demo.sh", name: "Demo")),
            LauncherMapping(key: "m", action: .systemAction(id: "mission-control"))
        ]
        let launcherCollection = collection(
            id: RuleCollectionIdentifier.launcher,
            name: "Quick Launcher",
            targetLayer: .custom("launcher"),
            configuration: .launcherGrid(launcher)
        )

        let config = KanataConfiguration.generateFromCollections([launcherCollection])
        assertContains(config, #"launch:com.apple.Safari"#, "launcher app action")
        assertContains(config, #"open:https%3A%2F%2Fgithub.com"#, "launcher URL action")
        assertContains(config, #"folder:~/Downloads"#, "launcher folder action")
        assertContains(config, #"script:~/bin/demo.sh"#, "launcher script action")
        assertContains(config, #"system:mission-control"#, "launcher system action")
    }

    func testCustomRuleFamiliesEmitConfigFragments() {
        let collection = collection(
            id: RuleCollectionIdentifier.customMappings,
            name: "Custom Mappings",
            mappings: [
                KeyMapping(input: "caps", action: .keystroke(key: "esc")),
                KeyMapping(input: "1", action: .keystroke(key: "1"), shiftedOutput: "S-1"),
                KeyMapping(input: "a", action: .hyper),
                KeyMapping(
                    input: "s",
                    action: .keystroke(key: "s"),
                    behavior: .dualRole(DualRoleBehavior(
                        tapAction: .keystroke(key: "s"),
                        holdAction: .keystroke(key: "lalt"),
                        activateHoldOnOtherKey: true
                    ))
                ),
                KeyMapping(
                    input: "d",
                    action: .keystroke(key: "d"),
                    behavior: .tapOrTapDance(.tapDance(TapDanceBehavior.twoStep(
                        singleTap: .keystroke(key: "d"),
                        doubleTap: .keystroke(key: "del"),
                        windowMs: 175
                    )))
                ),
                KeyMapping(
                    input: "m",
                    action: .keystroke(key: "m"),
                    behavior: .macro(MacroBehavior(text: "ok"))
                )
            ]
        )

        let config = KanataConfiguration.generateFromCollections([collection])
        assertContains(config, "esc", "simple remap")
        assertContains(config, "fork 1 (multi lsft 1) (lsft rsft)", "shift-aware modifier variant")
        assertContains(config, "act_base_a (multi lctl lmet lalt lsft)", "hyper modifier action")
        assertContains(config, "tap-hold-press $tap-timeout $hold-timeout s lalt", "custom tap-hold")
        assertContains(config, "tap-dance 175 (d del)", "tap dance")
        assertContains(config, "(macro o k)", "text macro")
    }

    func testLeaderPreferenceAndPreservedSequencesEmitGeneratedConfigFragments() throws {
        var nav = try catalogCollection(RuleCollectionIdentifier.vimNavigation)
        nav.isEnabled = true

        let leaderConfig = KanataConfiguration.generateFromCollections(
            [nav],
            leaderKeyPreference: LeaderKeyPreference(key: "space", targetLayer: .navigation, enabled: true),
            navActivationMode: .tapToToggle
        )
        assertContains(leaderConfig, "layer_nav_spc", "leader preference alias")
        assertContains(leaderConfig, "(one-shot-press 65000 (layer-while-held nav))", "leader one-shot nav")

        let sequences = KanataDefseqParser.parseSequences(from: "(defseq window-leader (space w))")
        let sequenceConfig = KanataConfiguration.generateFromCollections([nav], sequences: sequences)
        assertContains(sequenceConfig, "(defseq", "preserved sequence block")
        assertContains(sequenceConfig, "window-leader (space w)", "preserved sequence")
    }

    private func catalogCollection(_ id: UUID) throws -> RuleCollection {
        try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections().first { $0.id == id },
            "Missing catalog collection \(id)"
        )
    }

    private func collection(
        id: UUID,
        name: String,
        mappings: [KeyMapping] = [],
        targetLayer: RuleCollectionLayer = .base,
        configuration: RuleCollectionConfiguration = .list
    ) -> RuleCollection {
        RuleCollection(
            id: id,
            name: name,
            summary: name,
            category: .custom,
            mappings: mappings,
            isEnabled: true,
            targetLayer: targetLayer,
            configuration: configuration
        )
    }

    private func assertContains(
        _ config: String,
        _ snippet: String,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            config.contains(snippet),
            "Expected \(context) to contain:\n\(snippet)\n\nActual output:\n\(config)",
            file: file,
            line: line
        )
    }

    private func assertBalanced(
        _ config: String,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            config.filter { $0 == "(" }.count,
            config.filter { $0 == ")" }.count,
            "Unbalanced generated config for \(context)\n\nActual output:\n\(config)",
            file: file,
            line: line
        )
    }
}
