@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Config pipeline tests: mutate pack config → generate kanata → verify output.
/// Tests the path from user interaction (slider, picker, toggle) through
/// config generation to verify the correct kanata syntax is produced.
final class PackConfigPipelineTests: XCTestCase {

    // MARK: - Home Row Mods

    @MainActor
    func testHRM_ModifierMode_DefaultCAGS() {
        let config = HomeRowModsConfig()
        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        XCTAssertEqual(mappings.count, 8, "Should generate 8 HRM mappings (ASDF + JKL;)")

        let aMapping = mappings.first { $0.input == "a" }
        XCTAssertNotNil(aMapping)
        if case let .dualRole(behavior) = aMapping?.behavior {
            XCTAssertEqual(behavior.tapAction, "a")
            XCTAssertFalse(behavior.holdAction.isEmpty,
                           "A should have a hold action in CAGS layout")
        } else {
            XCTFail("A mapping should have dualRole behavior")
        }
    }

    @MainActor
    func testHRM_LayerMode_GeneratesLayerSwitch() {
        var config = HomeRowModsConfig()
        config.holdMode = .layers
        config.layerAssignments = ["a": "nav", "s": "sym"]
        config.enabledKeys = Set(["a", "s"])

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        let aMapping = mappings.first { $0.input == "a" }
        if case let .dualRole(behavior) = aMapping?.behavior {
            XCTAssertTrue(behavior.holdAction.contains("nav"),
                          "A should hold to layer 'nav' in layer mode")
        } else {
            XCTFail("A mapping should have dualRole behavior")
        }
    }

    @MainActor
    func testHRM_TimingChange_AffectsOutput() {
        var config = HomeRowModsConfig()
        config.timing.tapWindow = 250
        config.timing.holdDelay = 300

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        if case let .dualRole(behavior) = mappings.first?.behavior {
            XCTAssertEqual(behavior.tapTimeout, 250)
            XCTAssertEqual(behavior.holdTimeout, 300)
        } else {
            XCTFail("Should have dualRole behavior with custom timing")
        }
    }

    @MainActor
    func testHRM_PerKeyTimingOffset() {
        var config = HomeRowModsConfig()
        config.timing.tapOffsets = ["a": 20]
        config.timing.holdOffsets = ["a": -10]

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        let aMapping = mappings.first { $0.input == "a" }
        let otherMapping = mappings.first { $0.input == "s" }

        if case let .dualRole(aBehavior) = aMapping?.behavior,
           case let .dualRole(sBehavior) = otherMapping?.behavior
        {
            XCTAssertNotEqual(aBehavior.tapTimeout, sBehavior.tapTimeout,
                              "A should have different timing from S due to per-key offset")
        }
    }

    @MainActor
    func testHRM_OppositeHandActivation() {
        var config = HomeRowModsConfig()
        config.oppositeHandMode = .press

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        if case let .dualRole(behavior) = mappings.first?.behavior {
            XCTAssertTrue(behavior.useOppositeHand,
                          "Should use opposite hand activation when mode is .press")
        }
    }

    @MainActor
    func testHRM_DisabledKey_NotInOutput() {
        var config = HomeRowModsConfig()
        config.enabledKeys = Set(["a", "s"])

        let mappings = KanataConfiguration.generateHomeRowModsMappings(from: config)

        XCTAssertEqual(mappings.count, 2, "Should only generate mappings for enabled keys")
        XCTAssertTrue(mappings.allSatisfy { $0.input == "a" || $0.input == "s" })
    }

    // MARK: - Caps Lock Remap (Tap-Hold Picker)

    @MainActor
    func testCapsLockRemap_DefaultTapHold() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        guard let capsCollection = catalog.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) else {
            return XCTFail("Caps Lock collection not found")
        }

        if case let .tapHoldPicker(config) = capsCollection.configuration {
            XCTAssertFalse(config.tapOptions.isEmpty, "Should have tap options")
            XCTAssertFalse(config.holdOptions.isEmpty, "Should have hold options")
        } else {
            XCTFail("Caps Lock should use tapHoldPicker configuration")
        }
    }

    @MainActor
    func testCapsLockRemap_GeneratesValidConfig() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        XCTAssertTrue(config.contains("caps"), "Config should reference caps lock key")
    }

    // MARK: - Window Snapping

    @MainActor
    func testWindowSnapping_StandardConvention() {
        let mappings = RuleCollectionCatalog.windowMappings(for: .standard)
        XCTAssertFalse(mappings.isEmpty, "Standard convention should produce mappings")

        let hasLeft = mappings.contains { ($0.description ?? "").lowercased().contains("left") }
        let hasRight = mappings.contains { ($0.description ?? "").lowercased().contains("right") }
        XCTAssertTrue(hasLeft, "Should have left half mapping")
        XCTAssertTrue(hasRight, "Should have right half mapping")
    }

    @MainActor
    func testWindowSnapping_VimConvention() {
        let mappings = RuleCollectionCatalog.windowMappings(for: .vim)
        XCTAssertFalse(mappings.isEmpty, "Vim convention should produce mappings")
    }

    @MainActor
    func testWindowSnapping_ConventionsDiffer() {
        let standard = RuleCollectionCatalog.windowMappings(for: .standard)
        let vim = RuleCollectionCatalog.windowMappings(for: .vim)

        let standardInputs = Set(standard.map(\.input))
        let vimInputs = Set(vim.map(\.input))

        XCTAssertNotEqual(standardInputs, vimInputs,
                          "Standard and Vim conventions should use different key bindings")
    }

    // MARK: - Single Key Picker (Escape Remap, Delete Enhancement)

    @MainActor
    func testSingleKeyPicker_HasPresetOptions() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        guard let escCollection = catalog.first(where: { $0.id == RuleCollectionIdentifier.escapeRemap }) else {
            return XCTFail("Escape collection not found")
        }

        if case let .singleKeyPicker(config) = escCollection.configuration {
            XCTAssertFalse(config.presetOptions.isEmpty, "Should have preset options")
            XCTAssertFalse(config.inputKey.isEmpty, "Should have an input key")
        } else {
            XCTFail("Escape should use singleKeyPicker configuration")
        }
    }

    // MARK: - Auto Shift Symbols

    @MainActor
    func testAutoShift_DefaultConfig() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        guard let autoShift = catalog.first(where: { $0.id == RuleCollectionIdentifier.autoShiftSymbols }) else {
            return XCTFail("Auto Shift collection not found")
        }

        if case let .autoShiftSymbols(config) = autoShift.configuration {
            XCTAssertFalse(config.enabledKeys.isEmpty, "Should have enabled keys by default")
        } else {
            XCTFail("Auto Shift should use autoShiftSymbols configuration")
        }
    }

    // MARK: - Function Key Mode

    @MainActor
    func testFunctionKeys_MediaMode() {
        let mappings = RuleCollectionCatalog.functionKeyMappings(for: .media)
        XCTAssertFalse(mappings.isEmpty)
    }

    @MainActor
    func testFunctionKeys_StandardMode() {
        let mappings = RuleCollectionCatalog.functionKeyMappings(for: .function)
        XCTAssertFalse(mappings.isEmpty)
    }

    // MARK: - Full Config Generation Smoke Tests

    @MainActor
    func testAllPacksCombined_GeneratesValidConfig() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices {
            collections[i].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        XCTAssertFalse(config.isEmpty)
        XCTAssertTrue(config.contains("defsrc"), "Should have defsrc block")
        XCTAssertTrue(config.contains("deflayer"), "Should have at least one layer")
    }

    @MainActor
    func testNoPacksEnabled_GeneratesMinimalConfig() {
        var collections = RuleCollectionCatalog().defaultCollections()
        for i in collections.indices {
            collections[i].isEnabled = false
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        XCTAssertFalse(config.isEmpty, "Should still generate a minimal config")
        XCTAssertTrue(config.contains("defsrc"), "Should have defsrc even with nothing enabled")
    }
}
