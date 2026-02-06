@testable import KeyPathAppKit
@preconcurrency import XCTest

// MARK: - HUDContentResolver Tests

final class HUDContentResolverTests: XCTestCase {
    // Layer name matching
    func testWindowLayerName() {
        let style = HUDContentResolver.resolve(layerName: "window", keyMap: [:], collections: [])
        XCTAssertEqual(style, .windowSnappingGrid)
    }

    func testSnapLayerName() {
        let style = HUDContentResolver.resolve(layerName: "snap", keyMap: [:], collections: [])
        XCTAssertEqual(style, .windowSnappingGrid)
    }

    func testWindowSnapCompoundName() {
        let style = HUDContentResolver.resolve(layerName: "window-snap", keyMap: [:], collections: [])
        XCTAssertEqual(style, .windowSnappingGrid)
    }

    func testLauncherLayerName() {
        let style = HUDContentResolver.resolve(layerName: "launcher", keyMap: [:], collections: [])
        XCTAssertEqual(style, .launcherIcons)
    }

    func testSymbolLayerName() {
        let style = HUDContentResolver.resolve(layerName: "sym", keyMap: [:], collections: [])
        XCTAssertEqual(style, .symbolPicker)
    }

    func testSymbolsLayerName() {
        let style = HUDContentResolver.resolve(layerName: "symbols", keyMap: [:], collections: [])
        XCTAssertEqual(style, .symbolPicker)
    }

    func testSymbolSingularLayerName() {
        let style = HUDContentResolver.resolve(layerName: "symbol", keyMap: [:], collections: [])
        XCTAssertEqual(style, .symbolPicker)
    }

    func testDefaultForUnknownLayer() {
        let style = HUDContentResolver.resolve(layerName: "nav", keyMap: [:], collections: [])
        XCTAssertEqual(style, .defaultList)
    }

    func testLayerNameCaseInsensitive() {
        let style = HUDContentResolver.resolve(layerName: "Window", keyMap: [:], collections: [])
        XCTAssertEqual(style, .windowSnappingGrid)
    }

    func testEmptyKeyMapDefaultsList() {
        let style = HUDContentResolver.resolve(layerName: "custom", keyMap: [:], collections: [])
        XCTAssertEqual(style, .defaultList)
    }

    // Collection-based resolution
    func testWindowSnappingCollectionOverridesDefault() {
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.windowSnapping),
        ]
        let style = HUDContentResolver.resolve(layerName: "custom", keyMap: keyMap, collections: [])
        XCTAssertEqual(style, .windowSnappingGrid)
    }

    func testLauncherCollectionOverridesDefault() {
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Safari", outputKey: "s", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.launcher),
        ]
        let style = HUDContentResolver.resolve(layerName: "custom", keyMap: keyMap, collections: [])
        XCTAssertEqual(style, .launcherIcons)
    }

    func testSymbolCollectionOverridesDefault() {
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "!", outputKey: "excl", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.symbolLayer),
        ]
        let style = HUDContentResolver.resolve(layerName: "custom", keyMap: keyMap, collections: [])
        XCTAssertEqual(style, .symbolPicker)
    }

    func testAppLaunchIdentifierTriggersLauncherStyle() {
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .appLaunch(appIdentifier: "com.apple.Safari"),
        ]
        let style = HUDContentResolver.resolve(layerName: "custom", keyMap: keyMap, collections: [])
        XCTAssertEqual(style, .launcherIcons)
    }

    func testTransparentKeysIgnoredForCollectionCounting() {
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .transparent(fallbackLabel: "A", collectionId: RuleCollectionIdentifier.windowSnapping),
        ]
        let style = HUDContentResolver.resolve(layerName: "custom", keyMap: keyMap, collections: [])
        XCTAssertEqual(style, .defaultList, "Transparent keys should not trigger collection-based resolution")
    }

    // Priority: layer name wins over collection
    func testLayerNameTakesPriorityOverCollectionId() {
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.vimNavigation),
        ]
        // Layer name says "window" -> windowSnappingGrid even though collection is vim
        let style = HUDContentResolver.resolve(layerName: "window", keyMap: keyMap, collections: [])
        XCTAssertEqual(style, .windowSnappingGrid)
    }
}

// MARK: - ContextHUDViewModel Tests

@MainActor
final class ContextHUDViewModelTests: XCTestCase {
    func testUpdatePopulatesGroups() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.vimNavigation),
            1: .mapped(displayLabel: "Down", outputKey: "down", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.vimNavigation),
        ]

        let collection = RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Vim keys",
            category: .navigation,
            mappings: [],
            targetLayer: .navigation
        )

        vm.update(layerName: "nav", keyMap: keyMap, collections: [collection], style: .defaultList)

        XCTAssertEqual(vm.layerName, "nav")
        XCTAssertEqual(vm.style, .defaultList)
        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups.first?.name, "Vim Navigation")
        XCTAssertEqual(vm.groups.first?.entries.count, 2)
    }

    func testFiltersTransparentKeys() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil),
            1: .transparent(fallbackLabel: "A"),
        ]

        vm.update(layerName: "nav", keyMap: keyMap, collections: [], style: .defaultList)

        XCTAssertEqual(vm.allEntries.count, 1)
        XCTAssertEqual(vm.allEntries.first?.action, "Left")
    }

    func testFiltersLayerSwitchKeysIncluded() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .layerSwitch(displayLabel: "NAV"),
        ]

        vm.update(layerName: "base", keyMap: keyMap, collections: [], style: .defaultList)

        XCTAssertEqual(vm.allEntries.count, 1, "Layer switch keys should be included")
        XCTAssertEqual(vm.allEntries.first?.action, "NAV")
    }

    func testClear() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil),
        ]

        vm.update(layerName: "nav", keyMap: keyMap, collections: [], style: .defaultList)
        XCTAssertFalse(vm.allEntries.isEmpty)

        vm.clear()
        XCTAssertTrue(vm.allEntries.isEmpty)
        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertEqual(vm.layerName, "")
        XCTAssertEqual(vm.style, .defaultList)
    }

    func testMultipleCollectionGroups() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.vimNavigation),
            1: .mapped(displayLabel: "Snap", outputKey: "s", outputKeyCode: nil,
                       collectionId: RuleCollectionIdentifier.windowSnapping),
        ]

        let collections = [
            RuleCollection(
                id: RuleCollectionIdentifier.vimNavigation,
                name: "Vim Navigation",
                summary: "", category: .navigation, mappings: [],
                targetLayer: .navigation
            ),
            RuleCollection(
                id: RuleCollectionIdentifier.windowSnapping,
                name: "Window Snapping",
                summary: "", category: .navigation, mappings: [],
                targetLayer: .custom("window")
            ),
        ]

        vm.update(layerName: "custom", keyMap: keyMap, collections: collections, style: .defaultList)

        XCTAssertEqual(vm.groups.count, 2)
        let names = vm.groups.map(\.name).sorted()
        XCTAssertEqual(names, ["Vim Navigation", "Window Snapping"])
    }

    func testEntriesSortedByKeyCode() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            10: .mapped(displayLabel: "J", outputKey: "j", outputKeyCode: nil),
            5: .mapped(displayLabel: "H", outputKey: "h", outputKeyCode: nil),
            15: .mapped(displayLabel: "L", outputKey: "l", outputKeyCode: nil),
        ]

        vm.update(layerName: "nav", keyMap: keyMap, collections: [], style: .defaultList)

        XCTAssertEqual(vm.allEntries.map(\.keyCode), [5, 10, 15])
    }

    func testEmptyKeyMap() {
        let vm = ContextHUDViewModel()
        vm.update(layerName: "nav", keyMap: [:], collections: [], style: .defaultList)

        XCTAssertEqual(vm.layerName, "nav")
        XCTAssertTrue(vm.allEntries.isEmpty)
        XCTAssertTrue(vm.groups.isEmpty)
    }

    func testAllTransparentKeysResultsInEmptyEntries() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .transparent(fallbackLabel: "A"),
            1: .transparent(fallbackLabel: "B"),
        ]

        vm.update(layerName: "nav", keyMap: keyMap, collections: [], style: .defaultList)

        XCTAssertTrue(vm.allEntries.isEmpty)
    }

    func testAppLaunchEntryPreservesIdentifier() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .appLaunch(appIdentifier: "com.apple.Safari"),
        ]

        vm.update(layerName: "launcher", keyMap: keyMap, collections: [], style: .launcherIcons)

        XCTAssertEqual(vm.allEntries.count, 1)
        XCTAssertEqual(vm.allEntries.first?.appIdentifier, "com.apple.Safari")
    }

    func testUrlEntryPreservesIdentifier() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .webURL(url: "https://github.com"),
        ]

        vm.update(layerName: "nav", keyMap: keyMap, collections: [], style: .defaultList)

        XCTAssertEqual(vm.allEntries.count, 1)
        XCTAssertEqual(vm.allEntries.first?.urlIdentifier, "https://github.com")
    }

    func testStyleIsPassedThrough() {
        let vm = ContextHUDViewModel()
        vm.update(layerName: "snap", keyMap: [:], collections: [], style: .windowSnappingGrid)
        XCTAssertEqual(vm.style, .windowSnappingGrid)

        vm.update(layerName: "launcher", keyMap: [:], collections: [], style: .launcherIcons)
        XCTAssertEqual(vm.style, .launcherIcons)
    }

    func testKeysWithNoCollectionGroupedAsDefault() {
        let vm = ContextHUDViewModel()
        let keyMap: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "Left", outputKey: "left", outputKeyCode: nil),
            1: .mapped(displayLabel: "Right", outputKey: "right", outputKeyCode: nil),
        ]

        vm.update(layerName: "nav", keyMap: keyMap, collections: [], style: .defaultList)

        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups.first?.name, "Keys")
        XCTAssertEqual(vm.groups.first?.entries.count, 2)
    }
}

// MARK: - ContextHUDController Tests

@MainActor
final class ContextHUDControllerTests: XCTestCase {
    private var controller: ContextHUDController!
    private var savedDisplayMode: ContextHUDDisplayMode!
    private var savedTriggerMode: ContextHUDTriggerMode!
    private var savedTimeout: TimeInterval!

    override func setUp() async throws {
        try await super.setUp()
        // Save original preferences
        savedDisplayMode = PreferencesService.shared.contextHUDDisplayMode
        savedTriggerMode = PreferencesService.shared.contextHUDTriggerMode
        savedTimeout = PreferencesService.shared.contextHUDTimeout
        // Create test controller (no notification observers)
        controller = ContextHUDController(testMode: true)
    }

    override func tearDown() async throws {
        controller.resetForTesting()
        controller = nil
        // Restore original preferences
        PreferencesService.shared.contextHUDDisplayMode = savedDisplayMode
        PreferencesService.shared.contextHUDTriggerMode = savedTriggerMode
        PreferencesService.shared.contextHUDTimeout = savedTimeout
        try await super.tearDown()
    }

    // MARK: - Display Mode Gating

    func testOverlayOnlyModeBlocksHUD() {
        PreferencesService.shared.contextHUDDisplayMode = .overlayOnly

        controller.handleLayerChange("nav", source: nil)

        // Should NOT have changed previous layer (early return before that logic)
        XCTAssertEqual(controller.currentPreviousLayer, "base")
    }

    func testHudOnlyModeAllowsHUD() {
        PreferencesService.shared.contextHUDDisplayMode = .hudOnly

        controller.handleLayerChange("nav", source: nil)

        XCTAssertEqual(controller.currentPreviousLayer, "nav")
    }

    func testBothModeAllowsHUD() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        controller.handleLayerChange("nav", source: nil)

        XCTAssertEqual(controller.currentPreviousLayer, "nav")
    }

    // MARK: - Layer Change Logic

    func testSameLayerSkipped() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        controller.handleLayerChange("nav", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "nav")

        // Same layer again - should be a no-op
        controller.handleLayerChange("nav", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "nav")
    }

    func testBaseLayerDismissesInHoldMode() {
        PreferencesService.shared.contextHUDDisplayMode = .both
        PreferencesService.shared.contextHUDTriggerMode = .holdToShow

        // Go to nav first
        controller.handleLayerChange("nav", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "nav")

        // Return to base - should update previousLayer (dismiss path)
        controller.handleLayerChange("base", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "base")
    }

    func testBaseLayerKeepsHUDInTapMode() {
        PreferencesService.shared.contextHUDDisplayMode = .both
        PreferencesService.shared.contextHUDTriggerMode = .tapToToggle

        // Go to nav first
        controller.handleLayerChange("nav", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "nav")

        // Return to base - tap mode still updates previousLayer but doesn't call dismiss
        controller.handleLayerChange("base", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "base")
    }

    func testLayerNameWhitespaceNormalized() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        controller.handleLayerChange("  nav  ", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "  nav  ")
    }

    func testLayerNameCaseInsensitiveComparison() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        controller.handleLayerChange("Nav", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "Nav")

        // "nav" should be treated as same layer (case insensitive)
        controller.handleLayerChange("nav", source: nil)
        XCTAssertEqual(controller.currentPreviousLayer, "Nav", "Should skip - same layer case-insensitive")
    }

    // MARK: - One-Shot Override

    func testPushSourceActivatesOneShot() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        controller.handleLayerChange("nav", source: "push")
        XCTAssertEqual(controller.currentPreviousLayer, "nav")
    }

    func testPushBaseClearsOneShot() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        controller.handleLayerChange("nav", source: "push")
        controller.handleLayerChange("base", source: "push")
        XCTAssertEqual(controller.currentPreviousLayer, "base")
    }

    func testKanataSourceIgnoredDuringOneShotOverride() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        // Activate one-shot for "nav"
        controller.handleLayerChange("nav", source: "push")

        // Kanata reports "base" while one-shot is active - should be ignored
        controller.handleLayerChange("base", source: "kanata")
        XCTAssertEqual(controller.currentPreviousLayer, "nav", "Kanata update should be ignored during one-shot override")
    }

    // MARK: - Key Input Handling

    func testEscDismisses() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        // No window visible, but dismiss path is still hit
        controller.handleKeyInput(key: "esc", action: "press")
        // No crash = passes (dismiss on nil window is a no-op)
    }

    func testReleaseActionIgnored() {
        PreferencesService.shared.contextHUDDisplayMode = .both

        // Release events should be ignored
        controller.handleKeyInput(key: "esc", action: "release")
        // No crash = passes
    }

    func testNilKeyIgnored() {
        controller.handleKeyInput(key: nil, action: "press")
        // No crash = passes
    }

    func testModifierKeyDoesNotDismissInHoldMode() {
        PreferencesService.shared.contextHUDTriggerMode = .holdToShow

        // Modifier keys should not dismiss
        controller.handleKeyInput(key: "leftshift", action: "press")
        controller.handleKeyInput(key: "leftmeta", action: "press")
        controller.handleKeyInput(key: "capslock", action: "press")
        // No crash = passes (modifier keys are filtered out)
    }
}

// MARK: - Preferences Persistence Tests

@MainActor
final class ContextHUDPreferencesTests: XCTestCase {
    private var savedDisplayMode: ContextHUDDisplayMode!
    private var savedTriggerMode: ContextHUDTriggerMode!
    private var savedTimeout: TimeInterval!

    override func setUp() async throws {
        try await super.setUp()
        savedDisplayMode = PreferencesService.shared.contextHUDDisplayMode
        savedTriggerMode = PreferencesService.shared.contextHUDTriggerMode
        savedTimeout = PreferencesService.shared.contextHUDTimeout
    }

    override func tearDown() async throws {
        PreferencesService.shared.contextHUDDisplayMode = savedDisplayMode
        PreferencesService.shared.contextHUDTriggerMode = savedTriggerMode
        PreferencesService.shared.contextHUDTimeout = savedTimeout
        try await super.tearDown()
    }

    func testDisplayModePersistence() {
        PreferencesService.shared.contextHUDDisplayMode = .hudOnly
        let stored = UserDefaults.standard.string(forKey: "KeyPath.ContextHUD.DisplayMode")
        XCTAssertEqual(stored, "hudOnly")
    }

    func testTriggerModePersistence() {
        PreferencesService.shared.contextHUDTriggerMode = .tapToToggle
        let stored = UserDefaults.standard.string(forKey: "KeyPath.ContextHUD.TriggerMode")
        XCTAssertEqual(stored, "tapToToggle")
    }

    func testTimeoutPersistence() {
        PreferencesService.shared.contextHUDTimeout = 7.5
        let stored = UserDefaults.standard.double(forKey: "KeyPath.ContextHUD.Timeout")
        XCTAssertEqual(stored, 7.5, accuracy: 0.01)
    }

    func testTimeoutClampedToMin() {
        PreferencesService.shared.contextHUDTimeout = 0.5
        XCTAssertEqual(PreferencesService.shared.contextHUDTimeout, 1.0, accuracy: 0.01)
    }

    func testTimeoutClampedToMax() {
        PreferencesService.shared.contextHUDTimeout = 15.0
        XCTAssertEqual(PreferencesService.shared.contextHUDTimeout, 10.0, accuracy: 0.01)
    }

    func testDisplayModeAllCasesExist() {
        XCTAssertEqual(ContextHUDDisplayMode.allCases.count, 3)
    }

    func testTriggerModeAllCasesExist() {
        XCTAssertEqual(ContextHUDTriggerMode.allCases.count, 2)
    }

    func testDisplayModeDisplayNames() {
        XCTAssertEqual(ContextHUDDisplayMode.overlayOnly.displayName, "Overlay Only")
        XCTAssertEqual(ContextHUDDisplayMode.hudOnly.displayName, "HUD Only")
        XCTAssertEqual(ContextHUDDisplayMode.both.displayName, "Both")
    }

    func testTriggerModeDisplayNames() {
        XCTAssertEqual(ContextHUDTriggerMode.holdToShow.displayName, "Hold to Show")
        XCTAssertEqual(ContextHUDTriggerMode.tapToToggle.displayName, "Tap to Toggle")
    }

    func testTriggerModeDescriptions() {
        XCTAssertFalse(ContextHUDTriggerMode.holdToShow.description.isEmpty)
        XCTAssertFalse(ContextHUDTriggerMode.tapToToggle.description.isEmpty)
    }
}
